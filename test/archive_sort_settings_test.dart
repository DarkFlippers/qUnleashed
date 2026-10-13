import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/archive/sort_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kept_lines.dart';
import 'unopenable_prefs.dart';

/// Remembering how the archive is ordered across launches.
///
/// Unlike its siblings this store is not a `static final instance` - the
/// pages are handed one by `AppShell` (ADR 0002) - so each test builds its
/// own and there is no state to `reset()` between them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  // `AppShell` owns the store and so owns the one read of it; the pages it
  // hands the store to consume it and do not prime it.
  //
  // That makes this the single point of failure for half of #122: delete the
  // call and nothing else fails, while the stored sort is dead on every
  // launch and every table opens on name ascending for ever. The shell is not
  // pumpable - `diagnostics_notice_test.dart` says so and why - so this reads
  // the source, the way the reach and budget tests in this directory do. It
  // is a weak test; it is stronger than the nothing it replaces.
  test('the shell reads the stored sort, and is the only one that does', () {
    final shell = File('lib/app/shell.dart').readAsStringSync();

    expect(
      shell,
      contains('_archiveSort.load'),
      reason: 'nothing would read the stored sort',
    );

    final pages = [
      'lib/pages/archive/overview/category/category_page.dart',
      'lib/pages/archive/overview/category/deleted_page.dart',
      'lib/pages/archive/overview/category/favorites_page.dart',
    ];
    for (final page in pages) {
      expect(
        File(page).readAsStringSync(),
        isNot(contains('sortSettings.load')),
        reason: '$page primes a store it was handed',
      );
    }
  });

  /// Every table offers at least these two - `sortOptionsFor` always prepends
  /// folder, and every column set has a name column - which is what makes
  /// `name` safe as the fallback.
  const everywhere = ['folder', 'name'];

  late ArchiveSortSettings settings;

  setUp(() {
    clearKeptLines();
    SharedPreferences.setMockInitialValues(const {});
    settings = ArchiveSortSettings();
    addTearDown(settings.dispose);
  });

  test('a stored sort comes back', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'archive.sort': 'folder:desc',
    });

    await settings.load();

    expect(settings.resolve(everywhere), (key: 'folder', asc: false));
    expect(keptLines, isEmpty, reason: 'a clean read says nothing');
  });

  test('nothing stored is name ascending, not an error', () async {
    await settings.load();

    expect(settings.resolve(everywhere), (key: 'name', asc: true));
    expect(settings.loaded, isTrue);
    expect(keptLines, isEmpty);
  });

  test('a pick is readable before it has been written', () async {
    // The list reorders on the tap, not on the round trip to disk. Nothing
    // awaits `setSort` on the way to the next build.
    final pending = settings.setSort('folder', asc: false);

    expect(settings.resolve(everywhere), (key: 'folder', asc: false));
    await pending;
  });

  test('a pick notifies, so the other mounted tables follow it', () async {
    var notifications = 0;
    void count() => notifications++;
    settings.addListener(count);
    addTearDown(() => settings.removeListener(count));

    await settings.setSort('folder', asc: true);

    expect(notifications, 1);
  });

  test('re-picking what is already in force notifies nobody', () async {
    await settings.setSort('folder', asc: true);
    var notifications = 0;
    void count() => notifications++;
    settings.addListener(count);
    addTearDown(() => settings.removeListener(count));

    await settings.setSort('folder', asc: true);

    expect(notifications, 0);
  });

  group('a pick from a header or the sheet', () {
    test('starts a new key ascending', () async {
      await settings.setSort('name', asc: false);

      await settings.pick('folder', offered: everywhere);

      expect(settings.resolve(everywhere), (key: 'folder', asc: true));
    });

    test('turns the key already in force around', () async {
      await settings.pick('folder', offered: everywhere);
      await settings.pick('folder', offered: everywhere);

      expect(settings.resolve(everywhere), (key: 'folder', asc: false));
    });

    test('reads "in force" as the asking table sees it', () async {
      // Stored `uid`, which the deleted table cannot offer, so that table is
      // showing the `name` fallback, ascending. A tap on its name header has
      // to turn the list it is looking at around. Comparing the tap against
      // the raw stored `uid` instead would call it a new key, set name
      // ascending - which is what is already on screen - and the header would
      // read as dead.
      SharedPreferences.setMockInitialValues(const <String, Object>{
        'archive.sort': 'uid:asc',
      });
      await settings.load();

      await settings.pick('name', offered: everywhere);

      expect(settings.resolve(everywhere), (key: 'name', asc: false));
    });
  });

  test('a key this table cannot offer falls back to name', () async {
    // `uid` is NFC's column and nothing else's. Handed to the deleted table
    // it would not throw - `sortArchiveKeys` orders by name on an unknown key
    // - but the sort pill would light up and its sheet would mark no row, so
    // the screen would claim an order the list is not in.
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'archive.sort': 'uid:desc',
    });

    await settings.load();

    expect(settings.resolve(everywhere), (key: 'name', asc: true));
  });

  test('the fallback does not overwrite the key it stood in for', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'archive.sort': 'uid:desc',
    });

    await settings.load();
    settings.resolve(everywhere);

    // Passing through a table that cannot do `uid` must not cost it: going
    // back to NFC sorts by UID again.
    expect(settings.resolve(const ['name', 'uid']), (key: 'uid', asc: false));
  });

  test('a wrong-typed value reverts to the default and says so', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'archive.sort': 99,
    });

    await settings.load();

    expect(settings.resolve(everywhere), (key: 'name', asc: true));
    expect(settings.loaded, isTrue, reason: 'one key, not the read');
    final kept = keptLines.where((l) => l.contains('[ArchiveSort]')).toList();
    expect(kept, hasLength(1));
    expect(kept.single, contains('archive.sort'));
  });

  // The field and its direction are one preference because they cannot be
  // written as two. `persistSetting` swallows its own failure, so a pair of
  // calls is a pair of independent ones: the field lands, the direction does
  // not, and the next launch opens on a sort nobody picked.
  test('the sort is stored as one value', () async {
    await settings.setSort('folder', asc: false);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), ['archive.sort']);
    expect(prefs.getString('archive.sort'), 'folder:desc');
  });

  test('a stored shape that does not parse leaves the defaults', () async {
    // Only setSort writes this, so this is a hand-edited store or one left
    // by a build that is no longer installed. It costs a re-pick, like an
    // empty store, and says nothing a user could act on.
    for (final junk in const ['folder', 'folder:sideways', ':asc', '']) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'archive.sort': junk,
      });
      final store = ArchiveSortSettings();
      addTearDown(store.dispose);

      await store.load();

      expect(store.resolve(everywhere), (
        key: 'name',
        asc: true,
      ), reason: 'stored \$junk');
    }
  });

  // The read is started by AppShell and is a platform round trip. Its
  // continuation used to run second and put the stored pair back: the table
  // snapped out of the order the user had just chosen, and the pick - which
  // did reach the disk - turned up at the next launch instead.
  test('a pick made while the read is out survives it', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'archive.sort': 'mtime:desc',
    });

    final reading = settings.load();
    await settings.setSort('folder', asc: true);
    await reading;

    expect(settings.resolve(everywhere), (key: 'folder', asc: true));
  });

  test('re-picking what is in force also holds off a read in flight', () async {
    // The early return in setSort is before the write but must not be before
    // the claim: name ascending is the default, so this pick changes nothing
    // and persists nothing, yet it is still the order the user chose to keep.
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'archive.sort': 'mtime:desc',
    });

    final reading = settings.load();
    await settings.setSort('name', asc: true);
    await reading;

    expect(settings.resolve(everywhere), (key: 'name', asc: true));
  });

  test('a store that will not open leaves the defaults and says so', () async {
    useUnopenablePrefs();

    await expectLater(settings.load(), completes);

    expect(settings.resolve(everywhere), (key: 'name', asc: true));
    expect(settings.loaded, isFalse, reason: 'a failed read is not a read');
    expect(
      keptLines.where((l) => l.contains('[ArchiveSort] load failed')),
      hasLength(1),
    );
  });
}
