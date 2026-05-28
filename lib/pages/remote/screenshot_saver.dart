import 'dart:io' as io;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:super_clipboard/super_clipboard.dart';

Future<void> copyScreenshotToClipboard(Uint8List png) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) throw StateError('Clipboard not available');
  final item = DataWriterItem()..add(Formats.png(png));
  await clipboard.write([item]);
}

Future<String> saveScreenshotToPictures(Uint8List png) async {
  final fileName = 'flipper_screenshot_${DateTime.now().millisecondsSinceEpoch}.png';

  if (io.Platform.isAndroid || io.Platform.isIOS) {
    if (!await _ensureGalleryPermission()) {
      throw StateError('Gallery permission denied');
    }
    await SaverGallery.saveImage(
      png,
      quality: 100,
      fileName: fileName,
      skipIfExists: false,
      androidRelativePath: 'Pictures/Qunleashed',
    );
    return io.Platform.isAndroid ? 'Pictures/Qunleashed/$fileName' : 'Photos';
  }

  final dir = _systemPicturesDirectory();
  await dir.create(recursive: true);
  final sep = io.Platform.pathSeparator;
  final file = io.File('${dir.path}$sep$fileName');
  await file.writeAsBytes(png, flush: true);
  return file.path;
}

/// Saves a GIF to the Pictures directory and returns the full file path.
Future<String> saveGifToPictures(Uint8List gif) async {
  final fileName =
      'flipper_recording_${DateTime.now().millisecondsSinceEpoch}.gif';

  if (io.Platform.isAndroid || io.Platform.isIOS) {
    if (!await _ensureGalleryPermission()) {
      throw StateError('Gallery permission denied');
    }
    // SaverGallery.saveFile requires a file path, so write to a temp file first.
    final tmpDir = await getTemporaryDirectory();
    final tmpFile = io.File('${tmpDir.path}${io.Platform.pathSeparator}$fileName');
    await tmpFile.writeAsBytes(gif, flush: true);
    await SaverGallery.saveFile(
      filePath: tmpFile.path,
      fileName: fileName,
      skipIfExists: false,
      androidRelativePath: 'Pictures/Qunleashed',
    );
    await tmpFile.delete();
    return io.Platform.isAndroid ? 'Pictures/Qunleashed/$fileName' : 'Photos';
  }

  final dir = _systemPicturesDirectory();
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
  final item = DataWriterItem()
    ..add(Formats.fileUri(Uri.file(filePath)));
  await clipboard.write([item]);
}

Future<bool> _ensureGalleryPermission() async {
  if (io.Platform.isIOS) {
    final s = await Permission.photosAddOnly.request();
    return s.isGranted || s.isLimited;
  }
  if (io.Platform.isAndroid) {
    final photos = await Permission.photos.request();
    if (photos.isGranted || photos.isLimited) return true;
    return (await Permission.storage.request()).isGranted;
  }
  return true;
}

io.Directory _systemPicturesDirectory() {
  final pics = io.Platform.environment['XDG_PICTURES_DIR'];
  if (pics != null && pics.isNotEmpty) return io.Directory(pics);
  if (io.Platform.isWindows) {
    final user = io.Platform.environment['USERPROFILE'];
    if (user != null && user.isNotEmpty) return io.Directory('$user\\Pictures');
  }
  final home = io.Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) return io.Directory('$home/Pictures');
  return io.Directory.current;
}
