import 'dart:ffi';
import 'dart:io';

/// Opens a bundled qUnleashed native FFI library by its base name (without the
/// `lib` prefix / platform extension).
DynamicLibrary openNativeLibrary(String base) {
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
  throw UnsupportedError('Unsupported platform for the MIFARE native library');
}

/// The `qunleashed_mfkey32` library: mfkey32 + nested/static recovery entry
/// points (see `lib/modules/cpp/mfkey32`).
DynamicLibrary openMifareNativeLibrary() =>
    openNativeLibrary('qunleashed_mfkey32');

/// The `qunleashed_hardnested` library: the host-side hardnested attack
/// (see `lib/modules/cpp/hardnested`).
DynamicLibrary openHardnestedNativeLibrary() =>
    openNativeLibrary('qunleashed_hardnested');
