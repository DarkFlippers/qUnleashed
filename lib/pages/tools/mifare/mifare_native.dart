import 'dart:ffi';
import 'dart:io';

/// Opens the bundled `qunleashed_mfkey32` native library, which exports both the
/// mfkey32 and the nested recovery entry points (see `lib/modules/cpp/mfkey32`).
DynamicLibrary openMifareNativeLibrary() {
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('libqunleashed_mfkey32.so');
  }
  if (Platform.isWindows) {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final bundledPath =
        '$executableDir${Platform.pathSeparator}qunleashed_mfkey32.dll';
    if (File(bundledPath).existsSync()) {
      return DynamicLibrary.open(bundledPath);
    }
    return DynamicLibrary.open('qunleashed_mfkey32.dll');
  }
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.process();
  }
  throw UnsupportedError('Unsupported platform for the MIFARE native library');
}
