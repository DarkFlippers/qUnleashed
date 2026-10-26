// The file browser's select-all, which no test had been through.
//
// #375 moved all four archive selections onto `ListSelection`, and the browser
// is the page whose copy differed most: it was the only one with a toggle-all
// of its own shape, the only one that cleared before adding, and the only one
// whose exit already had the "nothing to clear" early return. All four of
// those are now one mixin, and nothing in the suite had ever tapped this
// button - so this file is the round trip through the real page: a long press,
// select all, deselect all.
//
// **What it does not cover is a pending row.** Reaching that state needs an
// upload suspended mid-write, which needs `tester.runAsync` for the local file
// read, and that in turn lets `super_drag_and_drop`'s initialisation run and
// throw `MissingPluginException` out of the drop region this page is wrapped
// in - twice, asynchronously, one of them after the case has finished. The
// footer lists what that leaves unheld.
import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/browser/page.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/services/localization/l10n.dart';

import 'archive_fakes.dart';
import 'firmware_fixture.dart';

/// A device holding a folder and a file, so "all of them" is more than one
/// row.
///
/// The long presses below are all on the folder, and that is forced rather
/// than arbitrary: a *file* row is wrapped in `FileDragSource`, whose
/// `DraggableWidget` takes the long press for a drag, while `_dragSource`
/// returns a directory's row unwrapped. `archive_bulk_outlives_page_test.dart`
/// lands on the same side of it by accident - a deleted key is not `inLocal`,
/// so `ArchiveKeyDragSource` hands its child straight back - and
/// `archive_selection_filter_test.dart`, whose rows *are* draggable, has to go
/// through the mixin instead.
class _TwoRows with FlipperRpcFake, ArchiveRpcFake {
  @override
  List<Main> framesFor(Main request) => request.hasStorageListRequest()
      ? [
          Main(
            storageListResponse: ListResponse()
              ..file.addAll([dir('badusb'), tag('notes.txt')]),
          ),
        ]
      : const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late DeviceController device;
  late _TwoRows storage;

  setUp(() {
    (device, _) = mountedDevice();
    storage = _TwoRows();
  });

  Future<void> pumpBrowser(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithDevice(FileManagerPage(client: storage), device),
    );
    await settle(tester);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('badusb'), findsOneWidget);
  }

  testWidgets('a long press selects that row and nothing else', (tester) async {
    await pumpBrowser(tester);

    await tester.longPress(find.text('badusb'));
    await settle(tester);

    expect(find.text(l10nGlobal.selectedCount(1)), findsOneWidget);
    // Offering to select all, because one of the two rows is not selected.
    expect(find.byIcon(Icons.select_all_rounded), findsOneWidget);

    await closeDevice(tester, device);
  });

  testWidgets('select all takes the rest, then offers to undo itself', (
    tester,
  ) async {
    await pumpBrowser(tester);
    await tester.longPress(find.text('badusb'));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await settle(tester);

    expect(find.text(l10nGlobal.selectedCount(2)), findsOneWidget);
    expect(
      find.byIcon(Icons.deselect_rounded),
      findsOneWidget,
      reason: 'with everything selected the button is the one that undoes it',
    );

    await closeDevice(tester, device);
  });

  testWidgets('and deselecting all of them leaves selection mode', (
    tester,
  ) async {
    await pumpBrowser(tester);
    await tester.longPress(find.text('badusb'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.deselect_rounded));
    await settle(tester);

    // A positive signal, not two absences: the FAB is suppressed for as long
    // as the page is selecting, so finding it means browsing. Without it a
    // defect that left one row selected would render "1 selected" and pass
    // both of the expects below.
    expect(
      find.byType(FloatingActionButton),
      findsOneWidget,
      reason: 'the page should be browsing again',
    );
    expect(
      find.text(l10nGlobal.selectedCount(2)),
      findsNothing,
      reason: 'the selection toolbar should be gone',
    );
    expect(
      find.text(l10nGlobal.selectedCount(1)),
      findsNothing,
      reason: 'and not holding a subset either',
    );
    // The listing is still what it was: deselecting is not a navigation.
    expect(find.text('notes.txt'), findsOneWidget);

    await closeDevice(tester, device);
  });
}

// Mutations run. `allSelected` narrowed to `isSelected(ids.first)` fails the
// second case. Dropping the `clear()` from `enterSelection` is held by
// `list_selection_test.dart` and not here, because both rows start unselected.
//
// **Four survive, and every one of them is about a pending row**, which is the
// limitation above rather than four gaps: dropping `!e.pending` from
// `_selectableNames`, dropping it from `_selectedEntries`, dropping
// `items.isNotEmpty` from `_allFap` (whose whole subject is the empty list a
// dropped pending row leaves behind), and putting the old `entries.every(...)`
// back in `build`. With no upload in flight all four are behaviour-identical
// to what is here. `_selectAll`'s off direction
// changed from `exitSelection()` to a `setAllSelected(..., selected: false)`
// survives too and is not a defect either - the difference is a name that has
// left the listing, which is what the page's comment says rather than claiming
// a test holds it.
