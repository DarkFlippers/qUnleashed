import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/archive/models/key.dart';
import 'package:qunleashed/pages/archive/overview/category/bulk_save.dart';

import 'kept_lines.dart';

/// Saving a selection of keys to a folder the user picked, and what it says
/// when some of them do not land.
///
/// The toast the caller shows carries the count - "Saved 3 of 5" - and that
/// is all anyone got. #111 declined to record the cause because a hundred
/// keys against a full disk fail a hundred times for one reason, and a line
/// each would fill the log screen from a single tap. One entry for the
/// selection is what it was waiting for. #103, ADR 0008.
ArchiveKey key(String name, {String? localPath}) => ArchiveKey(
  name: name,
  category: ArchiveCategory.subghz,
  state: ArchiveKeyState.local,
  extension: 'sub',
  localPath: localPath,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  late io.Directory source;
  late io.Directory dest;
  late int logBase;

  io.File real(String name) {
    final file = io.File('${source.path}${io.Platform.pathSeparator}$name')
      ..writeAsStringSync('Filetype: Flipper SubGhz Key File\n');
    return file;
  }

  setUp(() {
    source = io.Directory.systemTemp.createTempSync('bulk_save_src');
    dest = io.Directory.systemTemp.createTempSync('bulk_save_dst');
    clearKeptLines();
    logBase = keptLines.length;
    addTearDown(() {
      if (source.existsSync()) source.deleteSync(recursive: true);
      if (dest.existsSync()) dest.deleteSync(recursive: true);
    });
  });

  Iterable<String> lines(String fragment) =>
      keptLines.skip(logBase).where((l) => l.contains(fragment));

  group('a selection that did not all land', () {
    test('is reported once, however many files failed', () async {
      final saved = await saveKeysInto([
        key('a', localPath: real('a.sub').path),
        key('b', localPath: '${source.path}/gone-1.sub'),
        key('c', localPath: '${source.path}/gone-2.sub'),
      ], dest.path);

      expect(saved, 1);
      expect(lines('[Archive]'), hasLength(1));
    });

    test('says how many of how many landed', () async {
      await saveKeysInto([
        key('a', localPath: real('a.sub').path),
        key('b', localPath: '${source.path}/gone.sub'),
      ], dest.path);

      expect(lines('saved 1 of 2'), hasLength(1));
    });

    // The count was already on screen. This is the part that was not.
    test('carries the cause of the first one', () async {
      await saveKeysInto([
        key('b', localPath: '${source.path}/gone.sub'),
      ], dest.path);

      expect(lines('b.sub'), isNotEmpty);
      expect(lines('first failure'), hasLength(1));
    });

    // Which one it names matters: the first is the one that started the run
    // of them, and the last is whichever the loop happened to end on.
    test('names the first that failed, not the last', () async {
      await saveKeysInto([
        key('b', localPath: '${source.path}/gone-1.sub'),
        key('c', localPath: '${source.path}/gone-2.sub'),
      ], dest.path);

      expect(lines('b.sub'), hasLength(1));
      expect(lines('c.sub'), isEmpty);
    });

    // A key with no local copy at all never reaches the read, so a catch
    // alone would let it through as a silent success.
    test('counts a key with no local copy as one of them', () async {
      final saved = await saveKeysInto([key('b')], dest.path);

      expect(saved, 0);
      expect(lines('no local copy'), hasLength(1));
    });
  });

  group('a selection that all landed', () {
    test('says nothing', () async {
      final saved = await saveKeysInto([
        key('a', localPath: real('a.sub').path),
        key('b', localPath: real('b.sub').path),
      ], dest.path);

      expect(saved, 2);
      expect(lines('[Archive]'), isEmpty);
    });

    test('actually writes the files', () async {
      await saveKeysInto([key('a', localPath: real('a.sub').path)], dest.path);

      final written = io.File('${dest.path}${io.Platform.pathSeparator}a.sub');
      expect(written.existsSync(), isTrue);
      expect(written.readAsStringSync(), contains('Flipper SubGhz Key File'));
    });
  });
}
