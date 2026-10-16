// The size gate every importer reads a picked file through.
//
// `lib/components/picked_file.dart` carries the account of QUNLEASHED-E and
// why the bytes are read here rather than handed over by the platform. What
// this file holds is narrower: that the gate measures the file itself, that
// it runs before the read, and that `>` is not `>=`.
//
// The limit is deliberately not pinned here. There is no shared one - each
// importer names its own from what it does with the bytes - so every test
// below passes a small one and the real numbers live next to the importers
// that chose them.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/picked_file.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('picked_file_test');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  // Bytes that count up, so a test asserting on content can tell a file that
  // was read from a buffer of the right length that was not.
  String writeFile(String name, int length) {
    final bytes = Uint8List.fromList([
      for (var i = 0; i < length; i++) i % 256,
    ]);
    final file = File('${dir.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  group('readPickedFile', () {
    test('reads the file it is pointed at', () async {
      final path = writeFile('capture.ir', 1024);

      final bytes = await readPickedFile(path, limit: 4096);

      expect(bytes, hasLength(1024));
      expect(bytes.first, 0);
      expect(bytes[513], 1);
    });

    test('refuses a file past the limit', () async {
      final path = writeFile('clip.mp4', 4096);

      await expectLater(
        readPickedFile(path, limit: 1024),
        throwsA(
          isA<PickedFileTooLarge>()
              .having((e) => e.size, 'size', 4096)
              .having((e) => e.limit, 'limit', 1024),
        ),
      );
    });
  });

  group('ensurePickedFileFits', () {
    test('measures the file, not anything it was told', () async {
      // The whole fix rests on this one comparison, and the number a picker
      // reports is not this side's: it crosses the method channel on Android,
      // and the desktop pickers report 0 for a path that no longer exists.
      // Nothing but the file itself decides.
      final path = writeFile('clip.mp4', 4096);

      expect(await ensurePickedFileFits(path, limit: 4096), 4096);
      await expectLater(
        ensurePickedFileFits(path, limit: 4095),
        throwsA(isA<PickedFileTooLarge>()),
      );
    });

    test('takes a file exactly at the limit', () async {
      // Pins the comparison: `>` and not `>=`.
      final path = writeFile('edge.bm', 2048);

      expect(await ensurePickedFileFits(path, limit: 2048), 2048);
    });
  });

  group('PickedFileTooLarge', () {
    test('says both figures', () {
      // Nothing logs this today - both callers catch it and render
      // `commonFileTooLarge` - but a third caller that does should not get a
      // bare "too large". 121375736 is the pick from the incident; the
      // allocation that killed the app was twice it.
      expect(
        const PickedFileTooLarge(121375736, 32 * 1024 * 1024).toString(),
        allOf(
          contains('PickedFileTooLarge'),
          contains('115.8 MB'),
          contains('32.0 MB'),
        ),
      );
    });
  });
}
