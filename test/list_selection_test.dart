// The selection the four archive pages share, tested where they share it.
//
// #375. Each page had its own copy of the flag, the set, three methods and a
// select-all of its own shape, so nothing tested any of it directly: what held
// the one behaviour that had cost something - the exit landing on a disposed
// `State`, QUNLEASHED-P - was one page's bulk restore in
// `archive_bulk_outlives_page_test.dart`, and nothing at all on the other
// three. That file stays, because it is the only thing that proves a real
// bulk action still hands the exit to async code; this one covers the rules it
// cannot see from up there.
//
// Driven through the `State` rather than through a UI. The mixin's whole job is
// to be mixed into somebody else's page, so a harness with buttons would be
// testing the buttons - and `tester.state` reaches the same methods the pages
// call, with the real framework underneath deciding what `mounted` says.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/selection.dart';

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with ListSelection<_Host> {
  /// How many times the framework has rebuilt this, which is what a selection
  /// change is *for*: the toolbars and the row ticks are all read out of
  /// `build`.
  int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return const SizedBox.shrink();
  }
}

void main() {
  late _HostState state;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(const _Host());
    state = tester.state<_HostState>(find.byType(_Host));
    expect(state.selectionMode, isFalse, reason: 'it starts out browsing');
  }

  /// Applies [change] and lets the framework rebuild, answering how many
  /// builds that cost - zero being a change that nothing on screen sees.
  Future<int> buildsFor(WidgetTester tester, VoidCallback change) async {
    final before = state.builds;
    change();
    await tester.pump();
    return state.builds - before;
  }

  testWidgets('a long press starts selecting that row alone', (tester) async {
    await pumpHost(tester);

    expect(await buildsFor(tester, () => state.enterSelection('a')), 1);
    expect(state.selectionMode, isTrue);
    expect(state.selectedCount, 1);
    expect(state.isSelected('a'), isTrue);
    expect(state.isSelected('b'), isFalse);
  });

  testWidgets('a second row is added by tapping it', (tester) async {
    await pumpHost(tester);
    state.enterSelection('a');

    expect(await buildsFor(tester, () => state.toggleSelect('b')), 1);
    expect(state.selectedCount, 2);
    expect(state.isSelected('a'), isTrue);
  });

  testWidgets('tapping a selected row unselects it', (tester) async {
    await pumpHost(tester);
    state.enterSelection('a');
    state.toggleSelect('b');

    state.toggleSelect('a');
    await tester.pump();

    expect(state.isSelected('a'), isFalse);
    expect(state.selectedCount, 1);
    expect(
      state.selectionMode,
      isTrue,
      reason: 'one row is still selected, so the toolbar stays up',
    );
  });

  /// The identity the rest of the mixin is written against: selecting *is*
  /// having something selected. The toolbars read `selectionMode` alone, and
  /// nothing has to keep a second field in step with the set.
  ///
  /// It cannot fail while the getter is derived, and it is kept for the day
  /// somebody stores the flag again to arm the mode before the first row is
  /// picked - which is the one thing deriving it gave up.
  testWidgets('unticking the last row stops selecting', (tester) async {
    await pumpHost(tester);
    state.enterSelection('a');

    state.toggleSelect('a');
    await tester.pump();

    expect(state.selectedCount, 0);
    expect(state.selectionMode, isFalse);
  });

  /// Entering again from one row - what a long press does on a page that is
  /// already selecting is handled by `toggleSelect`, but the browser's own
  /// long press reaches `enterSelection` either way, and it means "this one".
  testWidgets('entering again selects only the new row', (tester) async {
    await pumpHost(tester);
    state.enterSelection('a');

    state.enterSelection('b');
    await tester.pump();

    expect(state.selectedCount, 1);
    expect(state.isSelected('b'), isTrue);
    expect(state.isSelected('a'), isFalse);
  });

  /// Select-all is over the rows on screen, which under a search box is not
  /// all of them - so it adds rather than replaces, and deselecting takes
  /// those same rows back out and leaves the rest alone.
  testWidgets('select all keeps a selection made before the filter', (
    tester,
  ) async {
    await pumpHost(tester);
    state.enterSelection('hidden-by-the-search');

    state.setAllSelected(const ['a', 'b'], selected: true);
    await tester.pump();
    expect(state.selectedCount, 3);

    state.setAllSelected(const ['a', 'b'], selected: false);
    await tester.pump();

    expect(state.selectedCount, 1);
    expect(state.isSelected('hidden-by-the-search'), isTrue);
    expect(
      state.selectionMode,
      isTrue,
      reason: 'the row the search hid is still selected',
    );
  });

  testWidgets('deselecting the last of them stops selecting', (tester) async {
    await pumpHost(tester);
    state.enterSelection('a');
    state.setAllSelected(const ['b'], selected: true);

    state.setAllSelected(const ['a', 'b'], selected: false);
    await tester.pump();

    expect(state.selectedCount, 0);
    expect(state.selectionMode, isFalse);
  });

  testWidgets('all of them selected, and none of an empty list', (
    tester,
  ) async {
    await pumpHost(tester);
    state.enterSelection('a');

    expect(state.allSelected(const ['a']), isTrue);
    expect(state.allSelected(const ['a', 'b']), isFalse);
    // An empty table is not "all selected", or its toolbar offers to deselect
    // nothing - and the browser's app bar labels its own button off this.
    expect(state.allSelected(const []), isFalse);
  });

  testWidgets('the exit clears both, and says nothing when it has nothing', (
    tester,
  ) async {
    await pumpHost(tester);
    state.enterSelection('a');

    expect(await buildsFor(tester, state.exitSelection), 1);
    expect(state.selectionMode, isFalse);
    expect(state.selectedCount, 0);

    // The early return. `_navigateTo` in the file browser exits on every
    // folder it opens, selecting or not, and a `setState` per listing is a
    // rebuild of the whole table for nothing.
    expect(await buildsFor(tester, state.exitSelection), 0);
  });

  /// QUNLEASHED-P, at the level the guard is written at.
  ///
  /// The page-level case drives a real bulk restore and is what proves the
  /// exit is still handed to async code at all; this one is what fails the
  /// moment the guard itself goes, on any page, with no device or storage in
  /// sight. Under `flutter test` the framework's "setState() called after
  /// dispose()" assertion is what would fire; a release build has no assertion
  /// left there and throws a fatal `TypeError` out of the null check on
  /// `_element` instead.
  testWidgets('the exit after the page is gone does nothing at all', (
    tester,
  ) async {
    await pumpHost(tester);
    state.enterSelection('a');
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    expect(find.byType(_Host), findsNothing, reason: "the case's own premise");

    state.exitSelection();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

// Mutations run against `components/selection.dart`, each one checked against
// the single case named rather than against the file: dropping the `clear()`
// in `enterSelection` fails "entering again selects only the new row";
// `removeAll` widened to a `clear()` fails "select all keeps a selection made
// before the filter"; dropping `ids.isNotEmpty` from `allSelected` fails the
// empty-list case; narrowing `allSelected` to its first id fails
// `file_manager_select_all_test.dart`'s select-all case; removing
// `if (!mounted) return` fails the last case here; removing the early return
// below it fails the build count in the one above; and `enterSelection`
// assigning instead of going through `setState` fails the first case, which
// is what the build counter is for - without it the mutation is invisible,
// because the next pump paints the right thing anyway.
//
// **Two mutations have nowhere left to go**, and that is the point of
// `selectionMode` being derived rather than stored: the four copies this
// replaced each cleared a flag in three places, and dropping any one of those
// lines was a page that selected rows with no toolbar to clear them. There is
// no line to drop now - the two "stops selecting" cases below still pass, but
// what they assert has become an identity rather than a rule somebody has to
// keep.
