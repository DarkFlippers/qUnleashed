// The plumbing every native feature in this app needs: loading a bundled
// library, looking a symbol up in it, spawning the isolate the call blocks in,
// and the shared memory a running engine reports through.
//
// Outside any feature folder on purpose. It lived in `pages/tools/mifare/` for
// as long as MIFARE key recovery was the only caller, and then SubGHz seed
// recovery imported it from a sibling tool's folder, which is how its own prose
// came to describe half of its callers. Whatever is added here addresses *a*
// native engine, not one of them.
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

/// Opens a bundled qUnleashed native FFI library by its base name (without the
/// `lib` prefix / platform extension).
///
/// Raises [NativeEngineUnavailable] when the library is missing or the platform
/// has no build of it, so that a packaging fault can be told apart from an
/// engine that ran and failed.
DynamicLibrary openNativeLibrary(String base) {
  try {
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('lib$base.so');
    }
    if (Platform.isWindows) {
      final executableDir = File(Platform.resolvedExecutable).parent.path;
      final bundledPath = '$executableDir${Platform.pathSeparator}$base.dll';
      if (File(bundledPath).existsSync()) {
        return DynamicLibrary.open(bundledPath);
      }
      return DynamicLibrary.open('$base.dll');
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return DynamicLibrary.process();
    }
  } catch (e) {
    throw NativeEngineUnavailable(e);
  }
  throw NativeEngineUnavailable(
    UnsupportedError('no $base build for this platform'),
  );
}

/// Looks [symbol] up in [library], raising [NativeEngineUnavailable] when it is
/// not there.
///
/// A library that loads but is missing a symbol is the same packaging fault as
/// one that does not load at all, and [openNativeLibrary] already promises to
/// report that as [NativeEngineUnavailable]. `lookupFunction` signals it with a
/// bare `ArgumentError`, which this codebase cannot tell apart from an FFI
/// allocation failure or a refused dictionary entry - `_staticFailureNote` in
/// `recover_controller.dart` says so - so every lookup goes through here and
/// the caller gets one answer whichever way the build is broken.
///
/// It has happened: the Apple builds shipped without these symbols at all. See
/// the note on `QUNLEASHED_EXPORT` in `lib/modules/cpp/mfkey32/nested_bridge.c`.
/// Takes the lookup as a callback rather than the symbol name because
/// `lookupFunction` will not accept a type variable for its native signature -
/// the analyzer requires both types to be written out at the call site.
F lookupNativeFunction<F extends Function>(F Function() lookup) {
  try {
    return lookup();
  } on ArgumentError catch (e) {
    throw NativeEngineUnavailable(e);
  }
}

/// The `qunleashed_mfkey32` library: mfkey32 + nested/static recovery entry
/// points (see `lib/modules/cpp/mfkey32`).
DynamicLibrary openMifareNativeLibrary() =>
    openNativeLibrary('qunleashed_mfkey32');

/// The `qunleashed_hardnested` library: the host-side hardnested attack
/// (see `lib/modules/cpp/hardnested`).
DynamicLibrary openHardnestedNativeLibrary() =>
    openNativeLibrary('qunleashed_hardnested');

/// The `qunleashed_faaccrack` library: SubGHz rolling-code seed recovery
/// (see `lib/modules/cpp/faaccrack`).
DynamicLibrary openFaaccrackNativeLibrary() =>
    openNativeLibrary('qunleashed_faaccrack');

/// A bundled native library, or a symbol in it, could not be loaded.
///
/// Distinct from a failure while running an engine: this one means the build is
/// missing a component, and nothing the user does with the card or the remote
/// will help.
class NativeEngineUnavailable implements Exception {
  const NativeEngineUnavailable(this.cause);

  final Object cause;

  @override
  String toString() => 'NativeEngineUnavailable: $cause';
}

/// The window a running native engine reports through, and the way to stop one.
///
/// Shared memory rather than an FFI callback: an engine reports from its own
/// worker threads, and a callback would have to be marshalled back to the
/// isolate that owns it. The caller allocates this, hands over the address, and
/// reads it on a timer while the engine blocks inside another isolate - native
/// memory is process-scoped, so both see the same words.
///
/// One declaration for both engines, which is the whole reason it is here.
/// `qunleashed_hn_progress` is the first three words; `struct
/// faaccrack_progress` is all four. The C structs stay separate - coupling two
/// independent libraries' ABIs to share three words is a worse trade than one
/// Dart mirror with four - so this is deliberately the *longer* of the two:
///
///  * Under hardnested the fourth word is slack. `calloc` zeroes it, the engine
///    never writes it, and [threadsStarted] therefore reads 0 - which is why no
///    hardnested caller may read that field. The engine reads only the twelve
///    bytes its own header declares, so the extra four are never touched.
///  * Under faaccrack all four are live, and the bridge's exported
///    `qunleashed_faaccrack_progress_size` is checked against `sizeOf` at
///    runtime, in release, before any result is read.
///
/// Adding a field here is therefore free for hardnested and an ABI change for
/// faaccrack. `test/native_struct_mirror_test.dart` holds the order and the
/// widths to both headers, in both directions.
final class NativeProgress extends Struct {
  /// Engine -> caller. Completion in thousandths, 0..1000, of whichever phase
  /// the engine says it is reporting. Both headers describe what theirs covers;
  /// neither claims a figure before [started].
  @Uint32()
  external int permille;

  /// Caller -> engine. Set non-zero to ask it to stop. Neither engine clears
  /// it, and neither stops instantly: the grain is one block for hardnested and
  /// one claimed chunk for faaccrack.
  @Uint32()
  external int abort;

  /// Engine -> caller. Latches when the engine begins publishing, so a caller
  /// can tell "nothing has begun" from "zero percent of something that has".
  /// Not a liveness signal.
  @Uint32()
  external int started;

  /// Engine -> caller, **faaccrack only**. Workers that actually started, which
  /// may be fewer than the count asked for. Reads 0 under hardnested, whose C
  /// struct ends one word earlier.
  @Uint32()
  external int threadsStarted;
}

/// The one place a native engine's isolate is spawned.
///
/// Here rather than at each recoverer because the hazard is not obvious and has
/// already shipped once. A Dart closure captures the *context of the scope it is
/// written in*, not merely the variables it names - so a spawn written inline
/// beside a sibling closure carries whatever that closure holds. In
/// `NativeHardnestedRecoverer.recoverKey` the sibling was
/// `isCancelled: () => _stopping`, which reaches the RecoverController, which
/// holds a FlipperClient, which holds a Future. Futures cannot cross an isolate
/// boundary, so every single attack was rejected before any native code ran:
///
///   Illegal argument in isolate message: object is unsendable
///     - Library:'dart:async' Class: _Future
///     <- Instance of 'FlipperClient'
///     <- Instance of 'RecoverController'
///
/// reported to the user as "the engine failed". Hardnested was not slow; it
/// never started.
///
/// This function's scope holds its two parameters and no sibling closure, so
/// there is nothing else for the sent closure to drag along. Pass [body] as a
/// static tear-off and [payload] as something sendable, and add nothing else
/// here - an extra local with a closure over it would reintroduce the bug for
/// every caller at once.
///
/// Every engine goes through it, including the ones whose signatures carry no
/// callback today and so cannot reach the hazard yet. That is the point: the
/// first one to gain an `onProgress` does not have to rediscover it.
Future<R> spawnAttackIsolate<P, R>(R Function(P) body, P payload) =>
    Isolate.run(() => body(payload));
