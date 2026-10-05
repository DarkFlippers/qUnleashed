import 'dart:convert';

import 'package:flipperlib/flipperlib.dart'
    show FlipperRpcStorageNotExistException, Main;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/existed_keys_storage.dart';

Future<List<int>> _notExist(String path) async =>
    throw FlipperRpcStorageNotExistException(Main());

Future<void> _noWrite(String path, List<int> data) async {}

void main() {
  _backupGroup();
  _normalisationGroup();
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
      // Loaded as empty, so any key is new, not a duplicate.
      expect(storage.registerKey('FFFFFFFFFFFF'), isTrue);
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

    test(
      'registerKey reports new vs already-known (drives the live tag)',
      () async {
        final storage = ExistedKeysStorage.withSeams(
          reader: (path) async {
            if (path == flipperDictUserPath) {
              return utf8.encode('A0A1A2A3A4A5\n');
            }
            if (path == flipperDictPath) return utf8.encode('FFFFFFFFFFFF\n');
            return const <int>[];
          },
          writer: _noWrite,
        );
        await storage.load();

        // A key already in the user or system dict is not new.
        expect(storage.registerKey('A0A1A2A3A4A5'), isFalse);
        expect(storage.registerKey('FFFFFFFFFFFF'), isFalse);
        // A genuinely unseen key is new.
        expect(storage.registerKey('B0B1B2B3B4B5'), isTrue);
      },
    );

    test('upload propagates a write failure (no false success)', () async {
      final storage = ExistedKeysStorage.withSeams(
        reader: _notExist,
        writer: (path, data) async => throw Exception('disk full'),
      );
      await storage.load();
      storage.registerKey('A0A1A2A3A4A5');
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
        storage.registerKey('A0A1A2A3A4A5'); // duplicate of the existing key
        storage.registerKey('B0B1B2B3B4B5'); // new key

        final added = await storage.upload();
        expect(added, ['B0B1B2B3B4B5']); // only the new key is reported
        // The whole set (existing + new) is written back — existing not lost.
        expect(written[flipperDictUserPath], contains('A0A1A2A3A4A5'));
        expect(written[flipperDictUserPath], contains('B0B1B2B3B4B5'));
      },
    );
  });
}

/// The dictionary is rewritten whole, and the firmware truncates the file on
/// the write's first frame. A write that then fails leaves the user with
/// neither their old keys nor the new ones - which is worse than the run
/// failing, because what is lost was collected over months.
void _backupGroup() {
  group('upload keeps what it is about to overwrite', () {
    test('copies the existing dictionary before writing', () async {
      final writes = <String>[];
      final storage = ExistedKeysStorage.withSeams(
        reader: (path) async => path == flipperDictUserPath
            ? utf8.encode('AAAAAAAAAAAA\n')
            : const <int>[],
        writer: (path, data) async => writes.add(path),
        deleter: (path) async => writes.add('deleted $path'),
      );
      await storage.load();
      storage.registerKey('BBBBBBBBBBBB');

      await storage.upload();

      expect(writes, [
        flipperDictUserBackupPath,
        flipperDictUserPath,
        'deleted $flipperDictUserBackupPath',
      ], reason: 'the copy has to be made first and cleared only on success');
      expect(storage.backupKept, isFalse);
    });

    test('leaves the copy behind when the write fails', () async {
      final written = <String, List<int>>{};
      final storage = ExistedKeysStorage.withSeams(
        reader: (path) async => path == flipperDictUserPath
            ? utf8.encode('AAAAAAAAAAAA\n')
            : const <int>[],
        writer: (path, data) async {
          if (path == flipperDictUserPath) throw Exception('card full');
          written[path] = data;
        },
      );
      await storage.load();
      storage.registerKey('BBBBBBBBBBBB');

      await expectLater(storage.upload(), throwsA(isA<Exception>()));

      expect(storage.backupKept, isTrue);
      expect(
        utf8.decode(written[flipperDictUserBackupPath]!),
        contains('AAAAAAAAAAAA'),
        reason: 'the copy must hold the keys that were there before',
      );
    });

    test('does not copy when there is nothing to lose', () async {
      final writes = <String>[];
      final storage = ExistedKeysStorage.withSeams(
        reader: _notExist,
        writer: (path, data) async => writes.add(path),
      );
      await storage.load();
      storage.registerKey('BBBBBBBBBBBB');

      await storage.upload();

      expect(writes, [flipperDictUserPath]);
    });
  });
}

/// The dictionary is a text file people edit. What comes out of it has to match
/// what the app puts in, or the same key is both "already known" and "new".
void _normalisationGroup() {
  group('dictionary lines are normalised', () {
    test('a lowercase entry is not re-added in upper case', () async {
      final written = <String>[];
      final storage = ExistedKeysStorage.withSeams(
        reader: (path) async => path == flipperDictUserPath
            ? utf8.encode('a0a1a2a3a4a5\n')
            : const <int>[],
        writer: (path, data) async => written.add(utf8.decode(data)),
      );
      await storage.load();

      expect(
        storage.registerKey('A0A1A2A3A4A5'),
        isFalse,
        reason: 'the card already has this key, in the other case',
      );
      expect(await storage.upload(), isEmpty);
      expect(
        written,
        isEmpty,
        reason: 'nothing changed, so nothing is written',
      );
    });

    test('a CRLF dictionary is still usable', () async {
      final storage = ExistedKeysStorage.withSeams(
        reader: (path) async => path == flipperDictUserPath
            ? utf8.encode('A0A1A2A3A4A5\r\nFFFFFFFFFFFF\r\n')
            : const <int>[],
        writer: (path, data) async {},
      );
      await storage.load();

      expect(storage.knownKeys, containsAll(['A0A1A2A3A4A5', 'FFFFFFFFFFFF']));
    });
  });
}
