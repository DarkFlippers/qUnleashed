import 'dart:io' as io;
import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';

import '../../../../components/path.dart';
import '../../../../components/share.dart';
import '../../../../services/storage/paths.dart';

Future<void> copyScreenshotToClipboard(Uint8List png) =>
    Pasteboard.writeImage(png);

Future<String> saveScreenshotToAppStorage(Uint8List png) async {
  final fileName =
      'flipper_screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
  final dir = await appScreenshotsDirectory();
  await dir.create(recursive: true);
  final file = io.File(pathJoin([dir.path, fileName]));
  await file.writeAsBytes(png, flush: true);
  return file.path;
}

/// Saves a GIF to the app recordings directory and returns the full file path.
Future<String> saveGifToAppStorage(Uint8List gif) async {
  final fileName =
      'flipper_recording_${DateTime.now().millisecondsSinceEpoch}.gif';
  final dir = await appRecordingsDirectory();
  await dir.create(recursive: true);
  final file = io.File(pathJoin([dir.path, fileName]));
  await file.writeAsBytes(gif, flush: true);
  return file.path;
}

/// Copies the GIF file at [filePath] to the system clipboard as a file
/// reference (paste-as-file on desktop, no-op on mobile).
Future<void> copyGifFileToClipboard(String filePath) =>
    copyFileToClipboard(filePath);
