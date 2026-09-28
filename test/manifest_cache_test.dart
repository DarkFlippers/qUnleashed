import 'dart:convert';
import 'dart:io';

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/data/manifest_registry.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/storage/paths.dart';

/// The list of installed apps the screen shows before the Flipper answers.
///
/// It is read off disk, written by this app - including by an older build of
/// it - and it used to be decoded under a single `catch (_) {}` around the
/// whole loop. A throw on the fifth of fifty entries left four apps indexed,
/// the rest missing, and nothing said anywhere. #138.
///
/// Entry by entry now, with a count of what would not read. The same shape
/// #133 gave the firmware directory.
class FakeCatalogClient implements FlipperClient {
  /// What `awaitName` answers, or the error it raises instead.
  String name = 'Kitchen';
  Object? nameThrows;

  @override
  Future<String> awaitName() async {
    if (nameThrows != null) throw nameThrows!;
    return name;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One cached record, in the shape the app writes.
Map<String, dynamic> record(
  String alias, {
  String uid = 'u',
  String path = '/ext/apps/Tools/x.fap',
  Object? md5 = 'abc',
  Object? devCatalog = false,
}) => {
  'alias': alias,
  'uid': uid,
  'version_uid': 'v',
  'full_name': alias,
  'path': path,
  'sdk_api': '86.0',
  'icon_base64': '',
  'dev_catalog': devCatalog,
  'md5': md5,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late FakeCatalogClient client;
  late ManifestRegistry registry;
  late int logBase;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('manifest_cache_test');
    // Not through `PathProviderPlatform`: on desktop `userDocumentsDirectory`
    // reads USERPROFILE or HOME directly and never asks the plugin, so a
    // stubbed platform interface writes into the developer's real
    // `Documents/qUnleashed` and leaves it there. The first version of this
    // file did exactly that.
    debugUseDocumentsRoot(root);
    LogService.clearHistory();
    // Read after clearing rather than trusting it: the history is a process
    // singleton, and a line from the case before this one has been seen to
    // land after its setUp ran. Only what this case adds is looked at.
    logBase = LogService.history.length;
    client = FakeCatalogClient();
    registry = ManifestRegistry(client: client);
    addTearDown(() {
      registry.dispose();
      debugUseDocumentsRoot(null);
      root.deleteSync(recursive: true);
    });
  });

  /// Writes [manifests] into the catalogue file the registry reads.
  Future<void> writeCache(Object? manifests) async {
    final file = await installedCatalogFile(client.name);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'manifests': manifests}));
  }

  Future<void> writeRaw(String body) async {
    final file = await installedCatalogFile(client.name);
    await file.parent.create(recursive: true);
    await file.writeAsString(body);
  }

  List<String> kept() => registry.all.map((m) => m.path).toList();

  bool said(String fragment) =>
      LogService.history.skip(logBase).any((l) => l.contains(fragment));

  group('a catalogue that reads cleanly', () {
    test('indexes every entry', () async {
      await writeCache([record('a'), record('b'), record('c')]);

      await registry.readCacheFile();

      expect(registry.all, hasLength(3));
    });

    test('says nothing about it', () async {
      await writeCache([record('a')]);

      await registry.readCacheFile();

      expect(said('dropped'), isFalse);
      expect(said('unreadable'), isFalse);
    });
  });

  group('one entry that will not read', () {
    // The defect, in one case: a record whose shape changed used to take
    // every record after it with it.
    test('costs itself and nothing after it', () async {
      await writeCache([
        record('a'),
        {'alias': 'broken', 'path': 42},
        record('c'),
        record('d'),
      ]);

      await registry.readCacheFile();

      expect(registry.all, hasLength(3));
      expect(kept(), isNot(contains(42)));
    });

    test('is counted, once, with the total', () async {
      await writeCache([
        record('a'),
        {'alias': 'broken'},
        record('c'),
      ]);

      await registry.readCacheFile();

      expect(said('dropped 1 of 3'), isTrue);
    });

    test('is counted per entry, not per field', () async {
      await writeCache([
        {'alias': 1, 'path': 2, 'uid': 3},
        {'alias': 4, 'path': 5},
      ]);

      await registry.readCacheFile();

      expect(said('dropped 2 of 2'), isTrue);
    });

    // A record with no alias or no path cannot be indexed under anything.
    // It used to be skipped in silence, which is the same loss with less
    // evidence.
    test('includes one with nothing to index it under', () async {
      await writeCache([record('a'), record('')]);

      await registry.readCacheFile();

      expect(registry.all, hasLength(1));
      expect(said('dropped 1 of 2'), isTrue);
    });

    test('includes one that is not a record at all', () async {
      await writeCache([record('a'), 'not an object', 7]);

      await registry.readCacheFile();

      expect(registry.all, hasLength(1));
      expect(said('dropped 2 of 3'), isTrue);
    });
  });

  group('a field of the wrong type', () {
    // Written by an older build, or by one that is newer. A string that
    // arrives as a number is not worth the app forgetting an installed app
    // over - the field falls back and the record stays.
    test('falls back without losing the record', () async {
      await writeCache([record('a', uid: '', md5: 7, devCatalog: 'yes')]);

      await registry.readCacheFile();

      expect(registry.all, hasLength(1));
      expect(registry.all.single.devCatalog, isFalse);
    });
  });

  group('a catalogue that cannot be read at all', () {
    test('says so when the device has no name yet', () async {
      client.nameThrows = StateError('no session');

      await registry.readCacheFile();

      expect(registry.all, isEmpty);
      expect(said('unreadable'), isTrue);
    });

    test('says so when the file is not JSON', () async {
      await writeRaw('{ this is not');

      await registry.readCacheFile();

      expect(said('is not one'), isTrue);
    });

    test('says so when the file is JSON of the wrong shape', () async {
      await writeRaw('[1, 2, 3]');

      await registry.readCacheFile();

      expect(said('is not one'), isTrue);
    });

    // Not every absence is a failure. A Flipper seen for the first time has
    // no catalogue yet, and saying so on every launch would be noise.
    test('says nothing when there is no file', () async {
      await registry.readCacheFile();

      expect(registry.all, isEmpty);
      expect(said('unreadable'), isFalse);
      expect(said('is not one'), isFalse);
    });

    test('says nothing when the file is empty', () async {
      await writeRaw('   ');

      await registry.readCacheFile();

      expect(said('is not one'), isFalse);
    });
  });
}
