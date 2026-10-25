import 'package:flutter/widgets.dart';

/// Multi-select over a list of ids, for a page that drives it with `setState`.
///
/// Four archive pages wrote the same `Set<String>`, the same three methods
/// and a select-all each spelled its own way - the category list, the deleted
/// and favourites lists, and the file browser (#375). The copies are what made
/// QUNLEASHED-P expensive rather than the defect itself, which [exitSelection]
/// tells in full: the next bulk action added to any of those pages started
/// from a copy that may or may not have carried the guard.
///
/// A mixin on [State] rather than a controller passed in. ADR 0001 keeps
/// `setState` and a mixin does not change that; ADR 0002 would prefer a
/// controller, and it is about *dependencies* - something the page talks to,
/// which a test wants to hand it a different one of. This is view state that
/// lives and dies with the `State` it sits on, nothing outside the page reads
/// it, and a `ChangeNotifier` would buy an `AnimatedBuilder` and a `dispose`
/// at each of the four pages to hold the same two fields.
///
/// Ids are strings and the page says what one is: the archive pages pass
/// `ArchiveKey.id`, the browser an entry's name, and neither has to be known
/// here. Holding the items themselves instead would pin a stale copy of every
/// selected row across a refresh, which is the opposite of what the pages do
/// with a selection - all four read theirs back out of the *current* list.
///
/// `test/selection_guard_test.dart` is what keeps a fifth page that *shows* a
/// selection from writing its own; a page whose rows learn about one some
/// other way is the blind spot that file names.
mixin ListSelection<T extends StatefulWidget> on State<T> {
  /// The selected ids, and the whole of this mixin's state.
  ///
  /// Private, and no view of it is exposed: every question the pages ask is
  /// answered below.
  final Set<String> _selected = <String>{};

  /// Whether the page is selecting rather than browsing.
  ///
  /// Derived, not stored, which is what makes "selecting exactly when
  /// something is selected" an identity rather than a rule the caller keeps.
  /// The four copies this replaced each held a `bool` beside the set and
  /// cleared it in three places.
  ///
  /// The cost is that a toolbar cannot arm the mode before the first row is
  /// picked. No page does: all four enter by long press.
  bool get selectionMode => _selected.isNotEmpty;

  /// How many ids are selected, for the "N selected" titles.
  int get selectedCount => _selected.length;

  bool isSelected(String id) => _selected.contains(id);

  /// Whether every one of [ids] is selected, and there is at least one.
  ///
  /// The select-all toggles read this, and the empty case is theirs: a list
  /// with nothing in it is not "all selected", or the toolbar offers to
  /// deselect nothing.
  ///
  /// Nothing selected is answered before [ids] is touched at all, which is
  /// what keeps this free on the builds where no selection is up - every page
  /// calls it once per build, and the browser's list is the whole folder.
  bool allSelected(Iterable<String> ids) =>
      _selected.isNotEmpty && ids.isNotEmpty && ids.every(_selected.contains);

  /// Starts selecting, with [id] as the only thing selected.
  ///
  /// Clears first, which is the browser's spelling of it: its long press calls
  /// this whether a selection is up or not, and then it means "this one row".
  /// On the other three the clear is a no-op, because their long press reaches
  /// here only while browsing - `selectionMode ? toggleSelect : enterSelection`
  /// at every one of those call sites.
  void enterSelection(String id) {
    setState(() {
      _selected
        ..clear()
        ..add(id);
    });
  }

  void toggleSelect(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  /// Adds or removes [ids], leaving anything else selected alone.
  ///
  /// Add rather than replace, because the lists are filtered: "select all"
  /// under a search box means the rows on screen, and a selection made before
  /// the box was typed in is still the user's. Removing the last of them
  /// leaves selection mode, the same way unticking the last row does.
  void setAllSelected(Iterable<String> ids, {required bool selected}) {
    setState(() {
      if (selected) {
        _selected.addAll(ids);
      } else {
        _selected.removeAll(ids);
      }
    });
  }

  /// Stops selecting, and is safe to call once the page has gone.
  ///
  /// QUNLEASHED-P. Every bulk action on these pages hands this to async code -
  /// a `VoidCallback` on a sheet entry, or its own continuation after an await
  /// - so the page can be gone by the time it runs, and then the `setState`
  /// below reaches a disposed `State`. In a release build there is no
  /// lifecycle assertion left there and the null check on `_element` is what
  /// throws, as a fatal uncaught `TypeError`.
  ///
  /// Guarded here rather than at each call site because the call sites are the
  /// part that gets forgotten: of the six that reach it, four had a `mounted`
  /// check one statement away, around the toast beside the exit, and the one
  /// the call-site fix missed - `browser/page.dart`'s `_deleteSelected` - has
  /// its own check two lines *below* the exit, which is why it read as
  /// covered. Nothing is lost by returning early: the selection this clears
  /// dies with the `State`.
  ///
  /// `test/list_selection_test.dart` is what fails the moment this guard goes;
  /// `test/archive_bulk_outlives_page_test.dart` is what proves a real bulk
  /// action still reaches it with the page gone.
  void exitSelection() {
    if (!mounted) return;
    if (_selected.isEmpty) return;
    setState(_selected.clear);
  }
}
