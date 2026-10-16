import 'dart:io' as io;
import 'dart:typed_data';

import 'format.dart';

/// Thrown by [ensurePickedFileFits] for a file past the limit it was given.
class PickedFileTooLarge implements Exception {
  const PickedFileTooLarge(this.size, this.limit)
    : assert(size > limit, 'not too large');

  /// Size of the file the user picked, in bytes.
  final int size;

  /// The limit it was measured against, in bytes.
  ///
  /// Carried rather than read back from a shared constant, because there is
  /// no shared constant: what an importer can hold depends on what it does
  /// with the bytes afterwards, and the two differ by a factor of eight.
  final int limit;

  @override
  String toString() =>
      'PickedFileTooLarge: ${formatBytes(size)} picked, '
      '${formatBytes(limit)} allowed';
}

/// Throws [PickedFileTooLarge] unless the file at [path] is within [limit].
///
/// Separate from [readPickedFile] for the importer that does not read the
/// picked file itself - Pixel Draw's dolphin branch picks a `meta.txt` and
/// then walks the folder around it - so that the comparison has one home and
/// one `>` to get right.
///
/// The size is this side's own `stat`, not the one the pick reports.
/// `file_picker` does report a real on-disk size nearly everywhere - Android
/// stats the copy it has already streamed into the cache in 8 KB chunks, iOS
/// asks `NSFileManager` - but the desktop pickers return `0` for a path that
/// no longer exists, and the whole fix rests on this one comparison.
Future<int> ensurePickedFileFits(String path, {required int limit}) async {
  final size = await io.File(path).length();
  if (size > limit) throw PickedFileTooLarge(size, limit);
  return size;
}

/// Reads a file the user picked, or throws [PickedFileTooLarge].
///
/// Pick with `withData: false` - the default - and read the bytes here.
/// `withData: true` has the platform load the whole file *and* hand it back
/// across the method channel, so the bytes exist twice before Dart sees them.
/// On Android the second copy is the fatal one: `StandardMessageCodec` grows
/// its buffer by doubling, so a 116 MB pick asked for a single contiguous
/// 232 MB allocation against a heap the crashing device limited to 256 MB
/// (`dalvik.vm.heapgrowthlimit`, which varies by device). The app died with an
/// uncaught `OutOfMemoryError` on the main thread, where no Dart `try` can see
/// it - Sentry QUNLEASHED-E. `test/picker_bytes_guard_test.dart` keeps the
/// argument out of `lib/`.
///
/// [limit] is required and has no default on purpose. A shared number would
/// have to be the largest any importer can hold, which makes it wrong for
/// every other one - and the number that matters is not the file's size but
/// what the importer turns it into. A `stat` is not a read, so a refusal
/// still costs nothing on this side.
///
/// What the limit does **not** buy back is the copy: on Android the platform
/// has already streamed the whole file into the app cache before the picker
/// returns, and nothing here deletes it.
Future<Uint8List> readPickedFile(String path, {required int limit}) async {
  await ensurePickedFileFits(path, limit: limit);
  return io.File(path).readAsBytes();
}
