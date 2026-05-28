import 'dart:io' as io;
import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart';

import '../../storage/app.dart';

Future<void> copyScreenshotToClipboard(Uint8List png) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) throw StateError('Clipboard not available');
  final item = DataWriterItem()..add(Formats.png(png));
  await clipboard.write([item]);
}

Future<String> saveScreenshotToAppStorage(Uint8List png) async {
  final fileName =
      'flipper_screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
  final dir = await appScreenshotsDirectory();
  await dir.create(recursive: true);
  final sep = io.Platform.pathSeparator;
  final file = io.File('${dir.path}$sep$fileName');
  await file.writeAsBytes(png, flush: true);
  return file.path;
}

/// Saves a GIF to the app recordings directory and returns the full file path.
Future<String> saveGifToAppStorage(Uint8List gif) async {
  final fileName =
      'flipper_recording_${DateTime.now().millisecondsSinceEpoch}.gif';
  final dir = await appRecordingsDirectory();
  await dir.create(recursive: true);
  final sep = io.Platform.pathSeparator;
  final file = io.File('${dir.path}$sep$fileName');
  await file.writeAsBytes(gif, flush: true);
  return file.path;
}

/// Copies the GIF file at [filePath] to the system clipboard as a file
/// reference (paste-as-file on desktop, no-op on mobile).
Future<void> copyGifFileToClipboard(String filePath) async {
  if (io.Platform.isAndroid || io.Platform.isIOS) return;
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) throw StateError('Clipboard not available');
  final item = DataWriterItem()..add(Formats.fileUri(Uri.file(filePath)));
  await clipboard.write([item]);
}
