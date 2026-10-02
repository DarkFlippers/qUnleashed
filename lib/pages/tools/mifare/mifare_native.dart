import 'dart:ffi';
import 'dart:io';

/// Opens a bundled qUnleashed native FFI library by its base name (without the
/// `lib` prefix / platform extension).
///
/// Raises [NativeEngineUnavailable] when the library is missing or the platform
/// has no build of it, so that a packaging fault can be told apart from an
/// attack that ran and failed.
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

/// A bundled native library, or a symbol in it, could not be loaded.
///
/// Distinct from a failure while running an attack: this one means the build
/// is missing a component, and nothing the user does with the card will help.
class NativeEngineUnavailable implements Exception {
  const NativeEngineUnavailable(this.cause);

  final Object cause;

  @override
  String toString() => 'NativeEngineUnavailable: $cause';
}
