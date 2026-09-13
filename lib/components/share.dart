import 'dart:io' as io;

import 'package:pasteboard/pasteboard.dart';

/// Only desktop clipboards carry file references; on mobile a pasted file URI
/// is meaningless, so callers fall back to the share sheet there.
bool get supportsClipboardFileUri =>
    io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS;

/// Copies the file at [path] to the system clipboard as a file reference
/// (paste-as-file on desktop). Returns false when the platform or the
/// clipboard cannot carry one.
Future<bool> copyFileToClipboard(String path) async {
  if (!supportsClipboardFileUri) return false;
  try {
    return await Pasteboard.writeFiles([io.File(path).absolute.path]);
  } catch (_) {
    return false;
  }
}
