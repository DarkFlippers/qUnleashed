import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../selection.dart';
import 'toolbar.dart';

/// What the selection toolbar needs, and the fact that a selection is up.
///
/// One record rather than a `bool` beside five values, so "selecting, but with
/// nothing to put in the toolbar" cannot be expressed: a page passes this when
/// it is selecting and null when it is not, and [ArchiveListScaffold] reads the
/// same field for its toolbar and for `canPop`. `CategoryToolbar.sort` is the
/// same shape for the same reason.
///
/// The page keeps the selection itself - this is `ListSelection`'s answers on
/// their way to a widget, not a second home for them.
typedef SelectionControl = ({
  int count,
  bool allSelected,
  VoidCallback onClose,
  VoidCallback onToggleAll,
  VoidCallback onActions,
});

/// Builds the [SelectionControl] for a page that takes its selection from
/// `ListSelection`.
///
/// Four of the record's five members are mechanical - the count, whether
/// everything on screen is selected, the exit, and the toggle - so a page that
/// wrote them out was writing the same ten lines as its neighbours. [ids] is
/// what the page alone knows: the rows on screen, which under a search box is
/// not all of them.
///
/// An extension here rather than a method on the mixin, so the dependency runs
/// widget → state: `components/selection.dart` holds no view-model type and
/// does not know this file exists.
extension ArchiveSelectionControl<T extends StatefulWidget>
    on ListSelection<T> {
  SelectionControl? selectionControl(
    Iterable<String> ids, {
    required VoidCallback onActions,
  }) {
    if (!selectionMode) return null;
    final allPicked = allSelected(ids);
    return (
      count: selectedCount,
      allSelected: allPicked,
      onClose: exitSelection,
      onToggleAll: () => setAllSelected(ids, selected: !allPicked),
      onActions: onActions,
    );
  }
}

/// The frame the three archive overview pages are built in: a `PopScope` that
/// swallows a back gesture while selecting, and an app bar whose bottom slot
/// holds either the browsing toolbar or the selection one.
///
/// #404. The category, deleted and favourites pages had this written out three
/// times - the same five app-bar cosmetics, the same 50-pixel slot, the same
/// `canPop: !selectionMode` pair - and what differed between them was the
/// colour, the title, one extra action and which toolbar went in the slot.
/// After #375 shared the selection *state*, this was the rest of the screen.
///
/// Two more pages are this shape and do not use it yet: `apps/manager`'s list
/// and its install page write out the same cosmetics and the same toolbar slot
/// at 48 instead of 50, and the install page has the same bar above its body.
/// Nothing but the work stands in the way of those two.
///
/// `QPageAppBar` is **not** the same thing, though it sets three of these
/// cosmetics: it takes a `String` title, fixes its own height at 68, pins
/// `titleSpacing` to zero and carries a device-status subtitle. The browser's
/// file list is not one of these either and cannot be: it lists `RemoteEntry`
/// rather than `ArchiveKey`, its title is a search field, it has no bottom
/// slot at all - its selection UI lives in the leading and the actions - and
/// it carries a FAB. `ListSelection` is what the two families share.
class ArchiveListScaffold extends StatelessWidget {
  const ArchiveListScaffold({
    super.key,
    required this.headerColor,
    required this.title,
    required this.toolbar,
    required this.body,
    this.selection,
    this.actions = const <Widget>[],
    this.topBar,
  });

  /// The app bar's background, and the selection toolbar's.
  final Color headerColor;

  final Widget title;

  /// The toolbar shown while browsing - search, filters and the sort button.
  final Widget toolbar;

  /// Non-null exactly while a selection is up, which is also what decides
  /// whether the back gesture is swallowed.
  final SelectionControl? selection;

  /// Trailing app-bar widgets - the sync button and the count badge.
  final List<Widget> actions;

  /// A bar between the app bar and [body], for the sync progress the category
  /// page shows. Absent on the other two.
  final Widget? topBar;

  final Widget body;

  /// The height of the toolbar slot.
  ///
  /// The slot, not the toolbars: both of those are 36 high inside 10 of bottom
  /// padding, so they sit in 46 of this 50, and the apps manager gives the same
  /// toolbar 48. The 50 is what these three pages have always reserved, and it
  /// is here so it is reserved once.
  static const double toolbarHeight = 50;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final picking = selection;
    return PopScope(
      canPop: picking == null,
      // `picking?.onClose()`, so nothing happens when there is no selection to
      // leave. Not only tidiness: `app/shell.dart` mounts several of these
      // pages on one route in the wide layout, and a route's `popDisposition`
      // refuses the pop if *any* registered entry does - so a page with
      // nothing selected sees `didPop: false` whenever a neighbour is
      // selecting.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) picking?.onClose();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: headerColor,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          titleSpacing: categoryTitleSpacing(context),
          title: title,
          actions: actions,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(toolbarHeight),
            child: picking == null
                ? toolbar
                : CategorySelectionToolbar(
                    count: picking.count,
                    allSelected: picking.allSelected,
                    catColor: headerColor,
                    onClose: picking.onClose,
                    onToggleAll: picking.onToggleAll,
                    onActions: picking.onActions,
                  ),
          ),
        ),
        // Two children either way, and the absent bar is a zero-size box
        // rather than nothing. Unkeyed children are matched by position, so a
        // body that was the only child and becomes the second one is a
        // *different* child: the list under it is torn down and rebuilt,
        // losing its scroll offset and any refresh in flight. The category
        // page flips this at both ends of every sync.
        body: Column(
          children: [
            topBar ?? const SizedBox.shrink(),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
