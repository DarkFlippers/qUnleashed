import 'dart:io' as io;
import 'dart:typed_data';

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
