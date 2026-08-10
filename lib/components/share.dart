import 'dart:io' as io;

import 'package:super_clipboard/super_clipboard.dart';

import 'path.dart';

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
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return false;
    final file = io.File(path);
    final item = DataWriterItem(
      suggestedName: basename(path.replaceAll('\\', '/')),
    )..add(Formats.fileUri(file.absolute.uri));
    await clipboard.write([item]);
    return true;
  } catch (_) {
    return false;
  }
}
