import 'dart:convert';

import 'package:flipperlib/flipperlib.dart'
    show FlipperRpcStorageNotExistException, Main;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/existed_keys_storage.dart';
import 'package:qunleashed/pages/tools/mifare/mfkey32_models.dart';

Future<List<int>> _notExist(String path) async =>
    throw FlipperRpcStorageNotExistException(Main());

Future<void> _noWrite(String path, List<int> data) async {}

void main() {
  group('ExistedKeysStorage', () {
    test('load rethrows a real user-dict read error (data-loss guard)', () async {
      // A transient (non-missing-file) read failure of the user dict must abort
      // — otherwise upload() would overwrite it with a truncated set.
      final storage = ExistedKeysStorage.withSeams(
        reader: (path) async {
          if (path == flipperDictUserPath) throw Exception('transient read');
          return const [];
        },
        writer: _noWrite,
      );
      await expectLater(storage.load(), throwsA(isA<Exception>()));
    });

    test('load treats a missing file as empty (first run works)', () async {
      final storage = ExistedKeysStorage.withSeams(
        reader: _notExist,
        writer: _noWrite,
      );
      await storage.load(); // must not throw
      storage.onNewKey(
        const FoundedKey(sectorName: '0', keyName: 'A', key: 'FFFFFFFFFFFF'),
      );
      // Loaded as empty, so the key is new, not a duplicate.
      expect(storage.foundedInformation.uniqueKeys, contains('FFFFFFFFFFFF'));
      expect(storage.foundedInformation.duplicated, isEmpty);
    });

    test(
      'optional system-dict read failure degrades to empty (no throw)',
      () async {
        final storage = ExistedKeysStorage.withSeams(
          reader: (path) async {
            if (path == flipperDictPath) throw Exception('system dict read');
            throw FlipperRpcStorageNotExistException(
              Main(),
            ); // user dict absent
          },
          writer: _noWrite,
        );
        await storage.load(); // system-dict failure is swallowed
      },
    );

    test('onNewKey reports new vs already-known (drives the live tag)', () async {
      final storage = ExistedKeysStorage.withSeams(
        reader: (path) async {
          if (path == flipperDictUserPath) return utf8.encode('A0A1A2A3A4A5\n');
          if (path == flipperDictPath) return utf8.encode('FFFFFFFFFFFF\n');
          return const <int>[];
        },
        writer: _noWrite,
      );
      await storage.load();

      // A key already in the user or system dict is not new.
      expect(
        storage.onNewKey(
          const FoundedKey(sectorName: '0', keyName: 'A', key: 'A0A1A2A3A4A5'),
        ),
        isFalse,
      );
      expect(
        storage.onNewKey(
          const FoundedKey(sectorName: '0', keyName: 'B', key: 'FFFFFFFFFFFF'),
        ),
        isFalse,
      );
      // A genuinely unseen key is new; a null (unrecovered) key gives no verdict.
      expect(
        storage.onNewKey(
          const FoundedKey(sectorName: '1', keyName: 'A', key: 'B0B1B2B3B4B5'),
        ),
        isTrue,
      );
      expect(
        storage.onNewKey(
          const FoundedKey(sectorName: '2', keyName: 'A', key: null),
        ),
        isNull,
      );
    });

    test('upload propagates a write failure (no false success)', () async {
      final storage = ExistedKeysStorage.withSeams(
        reader: _notExist,
        writer: (path, data) async => throw Exception('disk full'),
      );
      await storage.load();
      storage.onNewKey(
        const FoundedKey(sectorName: '0', keyName: 'A', key: 'A0A1A2A3A4A5'),
      );
      await expectLater(storage.upload(), throwsA(isA<Exception>()));
    });

    test(
      'upload preserves existing keys and returns only the new ones',
      () async {
        final written = <String, String>{};
        final storage = ExistedKeysStorage.withSeams(
          reader: (path) async => path == flipperDictUserPath
              ? utf8.encode('A0A1A2A3A4A5\n')
              : const [],
          writer: (path, data) async => written[path] = utf8.decode(data),
        );
        await storage.load(); // seeds the user dict with the existing key
        storage.onNewKey(
          const FoundedKey(sectorName: '0', keyName: 'A', key: 'A0A1A2A3A4A5'),
        ); // duplicate of the existing key
        storage.onNewKey(
          const FoundedKey(sectorName: '1', keyName: 'B', key: 'B0B1B2B3B4B5'),
        ); // new key

        final added = await storage.upload();
        expect(added, ['B0B1B2B3B4B5']); // only the new key is reported
        // The whole set (existing + new) is written back — existing not lost.
        expect(written[flipperDictUserPath], contains('A0A1A2A3A4A5'));
        expect(written[flipperDictUserPath], contains('B0B1B2B3B4B5'));
      },
    );
  });
}
