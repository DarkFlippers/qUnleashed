// The frame the three archive overview pages are built in. #404.
//
// Each of them used to carry its own copy, and what is tested here is the part
// that is easy to get wrong once and never notice three times: the selection
// indicator taking width off the columns, the empty view still answering a
// pull, and a back gesture leaving the selection instead of the page.
//
// Driven against the two widgets rather than through a page, because a page
// brings a controller, a device and real disk with it - and those tests exist
// already: `archive_sort_page_test.dart` mounts the favourites and category
// pages, `archive_selection_filter_test.dart` the category page and
// `archive_bulk_outlives_page_test.dart` the deleted one. What those cannot
// show is the arithmetic, and what this cannot show is that a page wired it
// up; between them both are covered.
//
// Mutations run, each against the single case it is named against. Killed
// here: the column width with and without the indicator, the empty view's
// scroll view, the condition that chooses it, the empty view built while rows
// are up, the slot's height, `canPop`, the toolbar switch, the bar drawn over
// the body instead of above it, and - the one a review had to measure before
// anybody noticed - the body swapping child type when the bar appears, which
// tore the list down and scrolled it back to the top. Two more are killed in
// `selection_guard_test.dart`, by 'a widget passing on what its parent gave
// it' and 'a mutable field of that name is the page keeping its own'.
//
// **Two survive, and both are a page's argument rather than the frame's
// shape**: laying the category's columns out against the wrong list, and the
// same for favourites. The cases here cannot see either, because they pass
// `const []` for the keys - what they are about is the width - and
// `archive_selection_filter_test.dart` is where a column assertion would go.
//
// Two mutations are **equivalent, not surviving**. `Expanded` widened to
// `Flexible` around the `ListView` cannot be observed at all, because a
// viewport takes `constraints.biggest` in the main axis under a loose
// constraint as much as a tight one. And dropping `if (!didPop)` from the pop
// handler changes nothing now that the handler calls `picking?.onClose()`: a
// permitted pop only happens with no selection, where the call is a no-op. The
// guard stays as the statement of intent - act on a *prevented* pop - not
// because a test holds it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/filelist/columns.dart';
import 'package:qunleashed/components/filelist/key_table.dart';
import 'package:qunleashed/components/filelist/list_scaffold.dart';
import 'package:qunleashed/components/filelist/table.dart';
import 'package:qunleashed/components/filelist/toolbar.dart';
import 'package:qunleashed/theme/theme.dart';

import 'view_size.dart';

final ThemeData _theme = buildAppTheme(
  Brightness.dark,
  const Color(0xFFCC241D),
);

/// The widths [ArchiveKeyTable] asked its caller to lay columns out in.
final List<double> widths = [];

/// How many times [_CountedBody] has been created from scratch.
int bodyInits = 0;

/// A body that notices being thrown away: `initState` runs again only if the
/// element was torn down rather than updated in place.
class _CountedBody extends StatefulWidget {
  const _CountedBody();

  @override
  State<_CountedBody> createState() => _CountedBodyState();
}

class _CountedBodyState extends State<_CountedBody> {
  @override
  void initState() {
    super.initState();
    bodyInits++;
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      for (var i = 0; i < 60; i++) SizedBox(height: 40, child: Text('row $i')),
    ],
  );
}

/// How many times it asked for the empty view, which it should not do while
/// there are rows: the pages build theirs out of several `l10n` lookups and
/// rebuild on every transfer tick.
int empties = 0;

Widget _table({
  required bool selectionMode,
  int itemCount = 3,
  Future<void> Function()? onRefresh,
}) {
  return MaterialApp(
    theme: _theme,
    home: Scaffold(
      body: ArchiveKeyTable(
        columns: (width) {
          widths.add(width);
          return layoutColumns(deletedColumns(), width, const []);
        },
        sort: (key: 'name', asc: true, opts: const [], onSort: (_) {}),
        selectionMode: selectionMode,
        accent: const Color(0xFF458588),
        onRefresh: onRefresh ?? () async {},
        empty: () {
          empties++;
          return const Center(child: Text('nothing here'));
        },
        itemCount: itemCount,
        itemBuilder: (i, cols) => SizedBox(height: 40, child: Text('row $i')),
      ),
    ),
  );
}

void main() {
  setUp(() {
    widths.clear();
    empties = 0;
    bodyInits = 0;
  });

  group('the table', () {
    testWidgets('lays the columns out in the width it was given', (
      tester,
    ) async {
      sizeView(tester, const Size(800, 1200));

      await tester.pumpWidget(_table(selectionMode: false));

      expect(widths, isNotEmpty);
      expect(widths.last, 800);
    });

    /// The one piece of arithmetic in here, and the reason this file exists: a
    /// page that forgot it laid its columns out in the full width and pushed
    /// the last one off the row the moment a selection opened.
    testWidgets('and in the width left by the selection indicator', (
      tester,
    ) async {
      sizeView(tester, const Size(800, 1200));

      await tester.pumpWidget(_table(selectionMode: true));

      expect(widths.last, 800 - kSelectionIndicatorWidth);
      expect(
        kSelectionIndicatorWidth,
        greaterThan(0),
        reason: 'otherwise the case above and this one are the same case',
      );
    });

    testWidgets('shows the rows under a header that is not in the scrollable', (
      tester,
    ) async {
      await tester.pumpWidget(_table(selectionMode: false));

      expect(find.text('row 0'), findsOneWidget);
      expect(find.byType(ArchiveColumnHeader), findsOneWidget);
      // The header is a sibling of the list, not an item in it: a header
      // inside the `ListView` scrolls away with the rows.
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(ArchiveColumnHeader),
        ),
        findsNothing,
      );
    });

    testWidgets('shows the empty view instead when there is nothing', (
      tester,
    ) async {
      await tester.pumpWidget(_table(selectionMode: false, itemCount: 0));

      expect(find.text('nothing here'), findsOneWidget);
      expect(find.byType(ArchiveColumnHeader), findsNothing);
      expect(empties, greaterThan(0));
    });

    testWidgets('and does not even build it while there are rows', (
      tester,
    ) async {
      await tester.pumpWidget(_table(selectionMode: false));

      expect(find.text('row 0'), findsOneWidget);
      expect(
        empties,
        0,
        reason: 'the empty view costs l10n lookups on every transfer tick',
      );
    });

    /// What the `SingleChildScrollView` and its `AlwaysScrollableScrollPhysics`
    /// are for: with nothing scrollable the user has no way to drag, so the one
    /// gesture that could fix an empty list - pull to refresh - is the one it
    /// takes away. **The forced height is not what holds this** (a probe
    /// refreshes fine without it); that is what makes the empty view fill the
    /// viewport instead of sitting in a strip at the top, which the case below
    /// is for.
    testWidgets('and an empty list can still be pulled to refresh', (
      tester,
    ) async {
      var refreshed = 0;
      await tester.pumpWidget(
        _table(
          selectionMode: false,
          itemCount: 0,
          onRefresh: () async => refreshed++,
        ),
      );

      await tester.fling(find.text('nothing here'), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(refreshed, 1);
    });
  });

  group('the frame', () {
    /// Both toolbars are the page's, and which one is on screen is the frame's
    /// The frame on a **pushed** route, which the back-gesture cases need.
    ///
    /// On the last route in a navigator a *permitted* pop bubbles instead of
    /// popping, so the page never leaves and the `didPop: true` branch is
    /// unreachable - which is the branch 'and lets one through' is about. A
    /// *prevented* pop does still invoke the callback there, so the selecting
    /// case would have worked either way; the first version of this file had
    /// no route underneath and the `didPop` mutation walked through it.
    Future<void> pumpFrame(
      WidgetTester tester, {
      required SelectionControl? selection,
      Widget? topBar,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ArchiveListScaffold(
                    headerColor: const Color(0xFF458588),
                    title: const Text('Keys'),
                    toolbar: const SizedBox(
                      height: 50,
                      child: Text('browsing'),
                    ),
                    selection: selection,
                    topBar: topBar,
                    // Top-left, not centred: the bar case compares the
                    // body's top edge against the bar's bottom, and a centred
                    // body sits mid-screen whether the bar is above it or
                    // drawn over it.
                    body: const Align(
                      alignment: Alignment.topLeft,
                      child: Text('body'),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    SelectionControl picked({VoidCallback? onClose}) => (
      count: 2,
      allSelected: false,
      onClose: onClose ?? () {},
      onToggleAll: () {},
      onActions: () {},
    );

    testWidgets('shows the browsing toolbar with no selection', (tester) async {
      await pumpFrame(tester, selection: null);

      expect(find.text('browsing'), findsOneWidget);
      expect(find.byType(CategorySelectionToolbar), findsNothing);
      expect(find.text('body'), findsOneWidget);
      // The slot is reserved, not merely occupied: `toolbarHeight` set to zero
      // leaves the toolbar in the tree, laid out flat, and every assertion
      // above still passes.
      expect(
        tester.getSize(find.byType(PreferredSize)).height,
        ArchiveListScaffold.toolbarHeight,
      );
    });

    testWidgets('and the selection toolbar once there is one', (tester) async {
      await pumpFrame(tester, selection: picked());

      expect(find.byType(CategorySelectionToolbar), findsOneWidget);
      expect(find.text('browsing'), findsNothing);
    });

    /// A back gesture while selecting leaves the selection, not the page -
    /// which is what every one of these pages wanted and each wired for
    /// itself. The `PopScope` has to refuse the pop *and* act on it; refusing
    /// alone would wedge the back button.
    testWidgets('swallows a back gesture and leaves the selection', (
      tester,
    ) async {
      var exits = 0;
      await pumpFrame(tester, selection: picked(onClose: () => exits++));

      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await tester.pumpAndSettle();

      // The callback, not `maybePop`'s answer: that is true for "handled",
      // which a prevented pop is as much as a real one.
      expect(exits, 1);
      expect(
        find.byType(ArchiveListScaffold),
        findsOneWidget,
        reason: 'the page stays and only the selection goes',
      );
    });

    /// The slot the category page's sync progress goes in, and the only part
    /// of the frame that is optional. Nothing showed that bar before this
    /// file: it lived in the page as `if (_ctrl.syncing) _syncBar(...)`, which
    /// needs a sync in flight to reach.
    testWidgets('puts the bar it is given above the body', (tester) async {
      await pumpFrame(
        tester,
        selection: null,
        topBar: const SizedBox(height: 20, child: Text('syncing')),
      );

      expect(find.text('syncing'), findsOneWidget);
      // The body's *top* against the bar's *bottom*. Comparing two tops
      // passes against a bar drawn over the body - a `Stack` in place of the
      // `Column` keeps every other case here green - because the body's text
      // sits mid-screen either way.
      expect(
        tester.getTopLeft(find.text('body')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('syncing')).dy),
      );
    });

    testWidgets('and no slot at all when it is given none', (tester) async {
      await pumpFrame(tester, selection: null);

      expect(find.text('syncing'), findsNothing);
      expect(find.text('body'), findsOneWidget);
    });

    /// **The bar appearing must not take the list with it.** The body is one
    /// child of a `Column` whether the bar is there or not, and the absent bar
    /// is a zero-size box rather than nothing - because unkeyed children are
    /// matched by position, so a body that was the only child and becomes the
    /// second one is a *different* child: torn down, re-created, scrolled back
    /// to the top.
    ///
    /// This is the shape the category page flips at both ends of every sync,
    /// and the refactor had it wrong until a review measured it. Two
    /// assertions, because one is the symptom and the other the mechanism.
    testWidgets('keeps the list it is scrolled to when the bar appears', (
      tester,
    ) async {
      Widget framed({Widget? topBar}) => MaterialApp(
        theme: _theme,
        home: ArchiveListScaffold(
          headerColor: const Color(0xFF458588),
          title: const Text('Keys'),
          toolbar: const SizedBox(height: 50, child: Text('browsing')),
          topBar: topBar,
          body: const _CountedBody(),
        ),
      );

      await tester.pumpWidget(framed());
      expect(bodyInits, 1);

      final list = tester.state<ScrollableState>(find.byType(Scrollable));
      list.position.jumpTo(400);
      await tester.pump();
      expect(list.position.pixels, 400);

      // The sync starts.
      await tester.pumpWidget(
        framed(topBar: const SizedBox(height: 20, child: Text('syncing'))),
      );

      expect(find.text('syncing'), findsOneWidget);
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        400,
        reason: 'the list was rebuilt from scratch and lost its offset',
      );
      expect(bodyInits, 1, reason: 'the body element was re-created');

      // And the same at the other end, when the sync finishes.
      await tester.pumpWidget(framed());
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        400,
      );
      expect(bodyInits, 1);
    });

    testWidgets('and lets one through when nothing is selected', (
      tester,
    ) async {
      // No selection, so nothing to count: what this case holds is that the
      // frame does not reach for an exit it was not given. With the old
      // `onExitSelection` parameter it could; now `picking?.onClose()` cannot.
      await pumpFrame(tester, selection: null);

      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await tester.pumpAndSettle();

      expect(
        find.byType(ArchiveListScaffold),
        findsNothing,
        reason: 'with nothing selected the back gesture is the page leaving',
      );
      // The pop *did* happen here, so `onPopInvokedWithResult` ran with
      // `didPop` true. That is what makes this the case that fails if the
      // handler stops reading it: an unconditional `picking?.onClose()` is
      // harmless with no selection, but an unconditional exit on a page that
      // *is* selecting would leave the selection on the way out.
      expect(find.text('body'), findsNothing);
    });
  });
}
