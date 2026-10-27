import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/filelist/columns.dart';
import 'package:qunleashed/components/filelist/toolbar.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';

import 'view_size.dart';

/// The toolbar control that reaches the folder sort.
///
/// It exists because the archive table has no folder column to tap: a file's
/// name and the folder it is in share one cell, under one header whose sort
/// key is the name (#122). A unit test on the comparator cannot say the user
/// can get to it, and this is where the toolbar's own behaviour is held -
/// `apps_folder_sort_test.dart` builds it too, for what an apps-manager
/// control carries into it rather than for what the sheet then does.
void main() {
  late QAppColors colors;
  late TextEditingController searchCtrl;

  setUp(() {
    colors = buildAppTheme(
      Brightness.dark,
      const Color(0xFFCC241D),
    ).extension<QAppColors>()!;
    searchCtrl = TextEditingController();
  });

  tearDown(() => searchCtrl.dispose());

  /// The keys handed to `onSort`, in the order the toolbar reported them.
  late List<String> sorted;

  /// The values handed to `onFilterChanged`, likewise.
  late List<String?> filtered;

  Future<void> pump(
    WidgetTester tester, {
    String sortKey = 'name',
    bool sortAsc = true,
    List<SortOption>? opts,
    bool withSort = true,
    List<String> filterOpts = const [],
    bool withStar = false,
  }) async {
    sorted = [];
    filtered = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryToolbar(
            searchCtrl: searchCtrl,
            query: '',
            filterVal: null,
            filterOpts: filterOpts,
            sort: withSort
                ? (
                    key: sortKey,
                    asc: sortAsc,
                    opts:
                        opts ??
                        sortOptionsFor(columnsFor(ArchiveCategory.infrared)),
                    onSort: sorted.add,
                  )
                : null,
            catColor: const Color(0xFFCC241D),
            colors: colors,
            onQueryChanged: (_) {},
            onFilterChanged: filtered.add,
            onStarredToggle: withStar ? () {} : null,
          ),
        ),
      ),
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.sort_rounded));
    await tester.pumpAndSettle();
  }

  testWidgets('offers the folder sort, which no column header does', (
    tester,
  ) async {
    await pump(tester);
    await openSheet(tester);

    expect(find.text(l10n.sortByFolder), findsOneWidget);

    await tester.tap(find.text(l10n.sortByFolder));
    await tester.pumpAndSettle();

    expect(sorted, ['folder']);
  });

  testWidgets('marks the sort in force with the direction it runs in', (
    tester,
  ) async {
    await pump(tester, sortKey: 'folder', sortAsc: false);
    await openSheet(tester);

    // One arrow, on the entry in force, pointing the way the list runs. The
    // sheet is the only place the chosen sort is named: the button has room
    // for the direction and not for the field.
    final down = find.descendant(
      of: find.widgetWithText(ListTile, l10n.sortByFolder),
      matching: find.byIcon(Icons.arrow_downward_rounded),
    );
    expect(down, findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, l10n.sortByName),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
  });

  testWidgets('hands the page a bare key, not a key and a direction', (
    tester,
  ) async {
    // Turning a sort around is the page's `_onSort`, the same handler a column
    // header tap goes through. The toolbar forwarding the key unchanged is
    // what keeps the two surfaces from drifting into disagreeing about what a
    // second tap means - so picking the sort already in force must report it
    // exactly as picking a new one does, and not pre-flip anything.
    await pump(tester, sortKey: 'folder', sortAsc: false);
    await openSheet(tester);
    await tester.tap(find.text(l10n.sortByFolder));
    await tester.pumpAndSettle();

    expect(sorted, ['folder']);
  });

  testWidgets('carries a sort whose column a phone has hidden', (tester) async {
    // `layoutColumns` drops columns until the name fits, and a dropped column
    // takes its header - and with it the only way to sort by that field -
    // off the screen. The sheet is built from `columnsFor`, not from the laid
    // out subset, so it keeps the sort reachable.
    //
    // Asserting the sheet lists what it was handed would be a tautology over
    // `_SortBtn`'s own loop. What makes this a test is the second half: the
    // column really is gone at this width, so the row really is the only way
    // left to that sort.
    const cat = ArchiveCategory.infrared;
    const narrow = 320.0;
    sizeView(tester, const Size(narrow, 640));

    final laidOut = layoutColumns(
      columnsFor(cat),
      narrow,
      const [],
    ).map((c) => c.col.sortKey).toSet();
    final hidden = sortOptionsFor(columnsFor(cat))
        .where((o) => o.key != 'folder' && !laidOut.contains(o.key))
        .toList();
    expect(
      hidden,
      isNotEmpty,
      reason: 'nothing is hidden at $narrow, so this proves nothing',
    );

    await pump(tester);
    await openSheet(tester);

    for (final o in hidden) {
      expect(find.text(o.label), findsOneWidget, reason: '${o.key} is missing');
    }
  });

  testWidgets('fits a phone with the filter and star beside it', (
    tester,
  ) async {
    // The sort pill went into a row that already held an `Expanded` search
    // field, the filter and the star. 320 is the narrowest width the project
    // declares.
    sizeView(tester, const Size(320, 640));

    await pump(
      tester,
      filterOpts: const ['NEC'],
      sortKey: 'folder',
      withStar: true,
    );

    // All four present, so the row really is as full as it gets.
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('says the list is not in its opening order', (tester) async {
    // Name ascending is what a page opens in and the one order the button
    // stays quiet about; anything else and it carries the direction.
    await pump(tester);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);

    await pump(tester, sortKey: 'folder');
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    await pump(tester, sortKey: 'name', sortAsc: false);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
  });

  testWidgets('stays off where there is nothing to offer', (tester) async {
    // The nullable arm, which is how a table with nothing to sort says so -
    // `toolbar_sort_guard_test.dart` holds that as the only permitted shape and
    // counts anything else. It was how the two apps-manager tables kept the
    // toolbar they already had until #314 gave them a sort to pass.
    await pump(tester, withSort: false);

    expect(find.byIcon(Icons.sort_rounded), findsNothing);
  });

  testWidgets('the filter sheet still picks, sharing the sort sheet chrome', (
    tester,
  ) async {
    // The two buttons open one `showPickerSheet` between them. Nothing in
    // `test/` built the filter sheet before, so this is what says the sort
    // button did not take it down with it on the way in.
    await pump(tester, filterOpts: const ['NEC', 'RC6']);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    expect(find.text(l10n.filterTitle), findsOneWidget);
    expect(find.text(l10n.filterAll), findsOneWidget);

    await tester.tap(find.text('RC6'));
    await tester.pumpAndSettle();

    expect(filtered, ['RC6']);
    expect(
      find.text(l10n.filterTitle),
      findsNothing,
      reason: 'sheet stayed up',
    );
  });
}
