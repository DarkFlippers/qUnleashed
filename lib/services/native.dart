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
/// `recover_controller.dart` is one example of that collision - so every lookup
/// goes through here and the caller gets one answer whichever way the build is
/// broken.
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

// The libraries this app ships, one opener each.
//
// Named here rather than beside the feature that uses each one because
// [openNativeLibrary] is where the per-platform rules live, and a second copy
// of them is how one platform ends up loading a library a different way from
// the others. Knowing a library's base name is not knowing what it does.

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
/// missing a component, and nothing the user does will help.
class NativeEngineUnavailable implements Exception {
  const NativeEngineUnavailable(this.cause);

  final Object cause;

  @override
  String toString() => 'NativeEngineUnavailable: $cause';
}

/// The window a running native engine reports through, and the way to stop one.
///
/// Why it is polled shared memory and not an FFI callback, and why the C fields
/// are `volatile` and not `_Atomic`, is in
/// `lib/modules/cpp/hardnested/qunleashed_hn_progress.h`, which both headers
/// treat as the canonical account. What matters on this side: the caller
/// allocates it, **zeroed** - both headers state that as a requirement, not a
/// courtesy, which is why every call site uses `calloc` - hands over the
/// address, and reads it on a timer while the engine blocks in another isolate.
///
/// One Dart declaration for two C structs that stay separate.
/// `qunleashed_hn_progress` is the first three words; `struct
/// faaccrack_progress` is all four, and this mirror is deliberately the longer
/// of the two. Under hardnested the fourth word is slack the engine *cannot*
/// reach - it only ever holds a pointer to the three words its own header
/// declares - so the extra four bytes are allocated and never touched. Under
/// faaccrack all four are live in the ABI, and the bridge's exported
/// `qunleashed_faaccrack_progress_size` is checked against `sizeOf` before any
/// result is read, in release.
///
/// So adding a field here is free for hardnested and an ABI change for
/// faaccrack. `docs/adr/0015-hand-written-ffi-bindings.md` is the decision and
/// the alternatives; `test/native_struct_mirror_test.dart` and
/// `test/native_progress_layout_test.dart` are what hold it.
///
/// The per-field notes below say what is *shared*. Where the two engines differ
/// the difference is called out, because `faaccrack.h` is explicit that these
/// semantics must not be carried across.
final class NativeProgress extends Struct {
  /// Engine -> caller. Completion in thousandths, 0..1000. What it is a
  /// fraction *of* differs - faaccrack's is the seed space handed out,
  /// hardnested's the brute-force phase only - and neither publishes a figure
  /// before [started]. Each header says what its own covers.
  @Uint32()
  external int permille;

  /// Caller -> engine. Set non-zero to ask it to stop; neither engine clears
  /// it, so a channel reused after a stop refuses the next search.
  ///
  /// Neither stops instantly, and the two are not comparable. faaccrack reads
  /// it once per claimed chunk, which is milliseconds. hardnested reads it per
  /// block *once inside the brute force* and not at all during the phases
  /// before it - table decompression, nonce ingestion, candidate generation -
  /// so a stop during one of those waits it out. That has already reached a
  /// user as a button that greyed out while the attack carried on.
  @Uint32()
  external int abort;

  /// Engine -> caller. Latches once the engine begins publishing, so a caller
  /// can tell "nothing has begun" from "zero percent of something that has".
  /// Not a liveness signal, and not the same moment on both: faaccrack sets it
  /// before the workers launch, hardnested when a percentage is first
  /// published - which is after those long early phases.
  @Uint32()
  external int started;

  /// Engine -> caller. Workers that actually started, which may be fewer than
  /// the count asked for.
  ///
  /// Zero means no count has been published, on either engine: hardnested never
  /// publishes one, and faaccrack publishes at least 1 once the sweep begins -
  /// it sweeps on the calling thread if no worker could be created. So zero is
  /// never "zero workers are sweeping", and nothing here has to know which
  /// engine filled the struct.
  ///
  /// No Dart caller reads it yet. It is declared because it is what makes this
  /// mirror the 16 bytes faaccrack's ABI requires.
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
/// Every spawn goes through it, including the recoverers whose signatures carry
/// no callback today and so cannot reach the hazard yet. That is the point: the
/// first one to gain an `onProgress` does not have to rediscover it. The one
/// native caller that does not appear here is `known_key_filter.dart`, which
/// runs its engine on the calling isolate and spawns nothing.
Future<R> spawnAttackIsolate<P, R>(R Function(P) body, P payload) =>
    Isolate.run(() => body(payload));
