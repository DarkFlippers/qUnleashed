// Ordering the apps manager by the folder an app lives in.
//
// Two of #314's three defects are what a user sees. Descending negated the
// whole comparator, so "folders Z-A" handed back each folder's apps backwards
// - the archive settled that in #312 as `ORDER BY folder DESC, name ASC`, and
// the two screens disagreed about what the same gesture meant. And below 460
// logical pixels of table width `appsTableColumns` drops the folder column,
// taking its header - the only way to reach the sort - with it, which left
// every phone in portrait with #122's original complaint.
//
// The third, a plain `compareTo` splitting a folder's subtree, is **not
// reachable with this table's data**: an apps folder is one segment, because
// the device walk is one level only and the install table's folder is a
// catalog field, and for a string with no `/` `folderSortKey` only
// lowercases. The cases below that feed a nested folder say what the shared
// key guarantees if that ever changes; they are not a bug report. The point
// of routing through the shared helpers is that this table stops holding a
// second answer to a settled question.
//
// No *comparator* test can say the user is able to reach any of this, and
// pumping the manager page is not on - it reaches `AppsBackend.instance` and
// primes a device and an update registry in `initState` - which is why
// `AppsSortState.control` exists to be read on its own, and why
// `toolbar_sort_guard_test.dart` holds the call sites.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/archive/models/key.dart';
import 'package:qunleashed/components/filelist/toolbar.dart';
import 'package:qunleashed/pages/apps/manager/widgets/apps_table.dart';
import 'package:qunleashed/pages/archive/overview/category/sort.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';

AppsRowFacts _app(
  String folder,
  String name, {
  int size = 0,
  String v = '1.0',
}) => (name: name, folder: folder, size: size, version: v);

/// `'<folder>/<name>'` per row, which is what the assertions read against.
List<String> _paths(List<AppsRowFacts> rows) => [
  for (final r in rows) r.folder.isEmpty ? r.name : '${r.folder}/${r.name}',
];

List<AppsRowFacts> _sorted(
  List<AppsRowFacts> rows, {
  String key = 'folder',
  bool asc = true,
}) {
  final state = AppsSortState()
    ..key = key
    ..asc = asc;
  return [...rows]..sort(state.compare);
}

/// The same rows as archive keys, ordered by the archive's own comparator.
///
/// For the one case that claims the two screens agree: asserting that against
/// a hand-written list would stay green if the archive changed its mind.
List<String> _archiveOrder(List<AppsRowFacts> rows) => [
  for (final k in sortArchiveKeys(
    [
      for (final r in rows)
        ArchiveKey(
          name: r.name,
          category: ArchiveCategory.infrared,
          state: ArchiveKeyState.synced,
          subFolder: r.folder,
        ),
    ],
    'folder',
    true,
  ))
    k.subFolder.isEmpty ? k.name : '${k.subFolder}/${k.name}',
];

void main() {
  group('by folder', () {
    test('groups a folder and orders it by name', () {
      final rows = [
        _app('Tools', 'Backup'),
        _app('Games', 'Snake'),
        _app('Tools', 'Apdu'),
        _app('Games', 'Arkanoid'),
      ];

      expect(_paths(_sorted(rows)), [
        'Games/Arkanoid',
        'Games/Snake',
        'Tools/Apdu',
        'Tools/Backup',
      ]);
    });

    test('keeps a nested folder and its subtree unbroken', () {
      // What the shared key guarantees, for input this table does not produce
      // today: `/` is 0x2F and a space is 0x20, so a plain `compareTo` would
      // put `Tools Beta` between `Tools`' own apps and `Tools`' subfolder.
      // Here because the key is the archive's and should keep behaving like
      // it, not because a user can see this.
      final sorted = _sorted([
        _app('Tools/Sub', 'Nested'),
        _app('Tools Beta', 'Sibling'),
        _app('Tools', 'Direct'),
      ]);

      expect(_paths(sorted), [
        'Tools/Direct',
        'Tools/Sub/Nested',
        'Tools Beta/Sibling',
      ]);
    });

    test('is the same order the archive puts those files in', () {
      // Through `sortArchiveKeys` itself, so the claim is about two
      // comparators agreeing rather than about one list someone typed.
      final rows = [
        _app('Flipper-IRDB/TV/Sony', 'Bravia'),
        _app('Flipper-IRDB/TV Shows', 'Netflix'),
        _app('Flipper-IRDB/TV', 'Generic'),
        _app('Tools', 'Apdu'),
      ];

      expect(_paths(_sorted(rows)), _archiveOrder(rows));
    });

    test('turns the folders around and leaves the names alone', () {
      // `ORDER BY folder DESC, name ASC`. The name is a tiebreak nobody
      // picked a direction for; negating the pair gave each folder's apps
      // back in reverse. One of the two defects a user could see.
      final rows = [
        _app('Games', 'Snake'),
        _app('Games', 'Arkanoid'),
        _app('Tools', 'Backup'),
        _app('Tools', 'Apdu'),
      ];

      expect(_paths(_sorted(rows, asc: false)), [
        'Tools/Apdu',
        'Tools/Backup',
        'Games/Arkanoid',
        'Games/Snake',
      ]);
    });

    test('ignores case, as the column shows it', () {
      // `BOILERS` is what makes this a test: case-sensitively the three order
      // `Audio, BOILERS, audio`, because every capital sorts below every
      // lowercase letter. A pair alone would pass either way.
      expect(
        _paths(
          _sorted([
            _app('audio', 'c'),
            _app('Audio', 'a'),
            _app('BOILERS', 'b'),
          ]),
        ),
        ['Audio/a', 'audio/c', 'BOILERS/b'],
      );
    });

    test('puts an app with no folder before every folder', () {
      // The empty string sorts below anything, and `/ext/apps` has loose
      // `.fap`s in it - an app installed before it had a category.
      expect(_paths(_sorted([_app('Tools', 'Backup'), _app('', 'Loose')])), [
        'Loose',
        'Tools/Backup',
      ]);
    });
  });

  group('the other keys', () {
    test('still reverse whole when the direction flips', () {
      // The folder branch returns early now, so this says the other three
      // were not changed on the way past.
      final rows = [
        _app('a', 'one', size: 10, v: '1.2'),
        _app('b', 'two', size: 30, v: '1.10'),
        _app('c', 'three', size: 20, v: '1.3'),
      ];

      expect(_sorted(rows, key: 'size', asc: false).map((r) => r.size), [
        30,
        20,
        10,
      ]);
      expect(_sorted(rows, key: 'name', asc: false).map((r) => r.name), [
        'two',
        'three',
        'one',
      ]);
      // A plain string compare, which is why `1.10` lands below `1.2`. Pinned
      // as it is rather than as it should be: the fix is a version parser and
      // a decision about what the column means, which is not #314's.
      expect(_sorted(rows, key: 'version').map((r) => r.version), [
        '1.10',
        '1.2',
        '1.3',
      ]);
    });
  });

  group('the sort button', () {
    test('offers the folder sort once, not twice', () {
      // `sortOptionsFor` prepends a folder entry for the archive, whose name
      // and folder share one cell. This table has a folder column of its own
      // wherever it has the width for one, so going through that helper would
      // offer the same sort twice.
      final keys = appsSortOptions().map((o) => o.key).toList();

      expect(keys, ['name', 'folder', 'version', 'size']);
    });

    test('offers the same four sorts at every width', () {
      // Which is the reason the list is fixed rather than read off the laid
      // out columns - and the half that makes the button worth having: below
      // 460 logical pixels of table width there is no folder column, so no
      // header carries that sort.
      final narrow = appsTableColumns(400).map((c) => c.col.sortKey);

      expect(narrow, isNot(contains('folder')));
      expect(
        appsTableColumns(800).map((c) => c.col.sortKey),
        contains('folder'),
        reason: 'the column is there at a width that has room for it',
      );
      expect(appsSortOptions().map((o) => o.key), contains('folder'));
    });

    test('carries the sort in force, so the sheet can mark it', () {
      final state = AppsSortState()
        ..select('folder')
        ..select('folder');

      final control = state.control((_) {});

      expect(control.key, 'folder');
      expect(control.asc, isFalse, reason: 'a second pick turns it around');
    });

    testWidgets('hands the page a bare key when the sheet is used', (
      tester,
    ) async {
      // The sheet's own forwarding is `archive_sort_button_test.dart`'s
      // subject; what this adds is that an apps table's control reaches it
      // intact - the options it was built with and the key it reports.
      final colors = buildAppTheme(
        Brightness.dark,
        const Color(0xFFCC241D),
      ).extension<QAppColors>()!;
      final searchCtrl = TextEditingController();
      addTearDown(searchCtrl.dispose);
      final picked = <String>[];
      final state = AppsSortState();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CategoryToolbar(
              searchCtrl: searchCtrl,
              query: '',
              filterVal: null,
              filterOpts: const [],
              sort: state.control(picked.add),
              catColor: const Color(0xFFCC241D),
              colors: colors,
              showStar: false,
              onQueryChanged: (_) {},
              onFilterChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.sort_rounded));
      await tester.pumpAndSettle();
      expect(find.text(l10n.sortByFolder), findsOneWidget);

      await tester.tap(find.text(l10n.sortByFolder));
      await tester.pumpAndSettle();

      expect(picked, ['folder'], reason: 'a bare key, as a header tap sends');
    });
  });
}
