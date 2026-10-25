// Select-all under a search filter, and a bulk action over what it picked.
//
// #375 moved the four selections onto one mixin, and the ids a page hands it
// are the page's own argument: "select all" means the rows on screen, which
// under a search box is not all of them. Nothing in the suite had checked
// that. Widen `filtered.map((k) => k.id)` to `_allKeys` at the toolbar's
// select-all and the user filters a category to one row, taps select all, and
// silently stars or deletes every key in the category - green against the
// whole suite before this file. `list_selection_test.dart` proves the mixin
// honours the ids it is given; this proves the page gives it the right ones.
//
// **The other half of that pair is not reachable from the UI**: the filter
// cannot change while a selection is up, because `CategorySelectionToolbar`
// replaces the search box for as long as the page is selecting. The footer
// says what that costs.
//
// `CategoryPage` carries this for all three overview pages: its copy,
// `deleted_page.dart`'s and `favorites_page.dart`'s are the same four lines
// against the same mixin now, and this is the one of the three whose source
// list (`keysFor`) is not itself a filter.
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/archive/models/key.dart';
import 'package:qunleashed/components/filelist/sync_progress_bar.dart';
import 'package:qunleashed/components/selection.dart';
import 'package:qunleashed/pages/archive/overview/category/category_page.dart';
import 'package:qunleashed/pages/archive/overview/category/favorites_page.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/services/archive/storage.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'archive_fakes.dart';

/// Two NFC files, on the device and on the phone, so both keys read as synced.
///
/// Both halves are needed: a category page lists what is stored locally
/// (`_byCategory` keeps `inLocal` keys only), and a local file the device does
/// not list is reconciled to `deleted` and moves to the deleted page instead.
///
/// Only the NFC listing is answered, so the walk's other categories come back
/// empty rather than finding the same two files in all of them.
class _SyncedPair with ArchiveRpcFake {
  @override
  List<Main> framesFor(Main request) {
    if (!request.hasStorageListRequest()) return const [];
    if (!request.storageListRequest.path.endsWith('/nfc')) {
      return [Main(storageListResponse: ListResponse())];
    }
    return [
      Main(
        storageListResponse: ListResponse()
          ..file.addAll([tag('card.nfc'), tag('carpark.nfc'), tag('door.nfc')]),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  useTempArchiveRoot('archive_selection_filter');

  late _SyncedPair client;
  late ArchiveController ctrl;
  late ListSelection<CategoryPage> selection;

  /// The three NFC files, on the phone as well as the device.
  Future<void> seedKeys(ArchiveStorage storage) async {
    final dir = storage.categoryDir(archiveTestDevice, ArchiveCategory.nfc)
      ..createSync(recursive: true);
    for (final name in const ['card', 'carpark', 'door']) {
      io.File('${dir.path}${io.Platform.pathSeparator}$name.nfc')
          .writeAsStringSync('Filetype: Flipper NFC device\n');
    }
  }

  /// Starred before the page opens: one key and two apps, which is the one
  /// arrangement the favourites page's row dispatch needs and had never been
  /// mounted with (#404). `carpark` rather than `card` or `door`, so the two
  /// category cases below keep their premises about those two.
  Future<void> starSome(ArchiveStorage storage) async {
    await storage.writeFavorites(archiveTestDevice, {
      archiveKeyId(flipperDir: 'nfc', name: 'carpark', extension: 'nfc'),
    });
    await storage.writeFapFavorites(archiveTestDevice, const [
      (path: '/ext/apps/Tools/zeta.fap', name: 'zeta'),
      (path: '/ext/apps/GPIO/beta.fap', name: 'beta'),
    ]);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    client = _SyncedPair();
  });

  /// The NFC category with two keys in it, `card` and `door`.
  Future<void> pumpCategory(WidgetTester tester) async {
    final mounted = await mountArchivePage(
      tester,
      client: client,
      seed: seedKeys,
      page: (controller, sortSettings) => CategoryPage(
        controller: controller,
        sortSettings: sortSettings,
        category: ArchiveCategory.nfc,
      ),
    );
    ctrl = mounted.controller;
    selection =
        tester.state(find.byType(CategoryPage)) as ListSelection<CategoryPage>;

    expect(find.text('card'), findsOneWidget);
    expect(find.text('carpark'), findsOneWidget);
    expect(find.text('door'), findsOneWidget);
    // Not syncing, so no bar above the table. The frame takes one when the
    // page gives it one (`archive_list_frame_test.dart`), and this is what
    // says the page only gives it one while a sync is running.
    expect(find.byType(SyncProgressBar), findsNothing);
  }

  ArchiveKey keyNamed(String name) =>
      ctrl.keysFor(ArchiveCategory.nfc).firstWhere((k) => k.name == name);

  /// Starts selecting with [name] picked.
  ///
  /// Through the mixin rather than with a long press, and that is forced
  /// rather than preferred: every row here has a local copy and is therefore
  /// wrapped in `ArchiveKeyDragSource`, whose `DraggableWidget` takes the long
  /// press for a drag. The gesture is covered where it is reachable -
  /// `file_manager_select_all_test.dart` for the browser's folder rows,
  /// `archive_bulk_outlives_page_test.dart` for a deleted key, neither of
  /// which is draggable - and what this file is about is the arguments the
  /// page passes once a selection exists.
  Future<void> select(WidgetTester tester, String name) async {
    selection.enterSelection(keyNamed(name).id);
    await settle(tester);
    expect(selection.selectedCount, 1);
  }

  /// Opens the selection toolbar's bulk-actions sheet.
  Future<void> openBulkActions(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await settle(tester);
  }

  testWidgets('select all takes the rows the search box left, and no others', (
    tester,
  ) async {
    await pumpCategory(tester);

    // Typed first, because the search box is gone for as long as the page is
    // selecting - which is also the order the user has to work in. `car`
    // leaves two of the three rows, so select-all has something to add and
    // something to leave out.
    await tester.enterText(find.byType(TextField), 'car');
    await settle(tester);
    expect(find.text('carpark'), findsOneWidget);
    expect(find.text('door'), findsNothing, reason: 'the filter is on');

    await select(tester, 'card');
    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await settle(tester);

    // Two, not three: the key the search box hid is not on screen, and a page
    // handing the mixin its unfiltered list instead would take `door` here -
    // then star or delete it from under the user.
    expect(selection.selectedCount, 2);
    expect(selection.isSelected(keyNamed('carpark').id), isTrue);
    expect(selection.isSelected(keyNamed('door').id), isFalse);

    await openBulkActions(tester);
    expect(find.text(l10nGlobal.archiveFilesSelected(2)), findsOneWidget);
  });

  testWidgets('a bulk action lands on the selection and then closes it', (
    tester,
  ) async {
    await pumpCategory(tester);
    expect(keyNamed('card').favorite, isFalse, reason: "the case's premise");

    await select(tester, 'card');
    await openBulkActions(tester);
    await tester.tap(find.text(l10nGlobal.archiveStar));
    await settle(tester);

    expect(keyNamed('card').favorite, isTrue);
    expect(keyNamed('door').favorite, isFalse, reason: 'and on nothing else');
    // `_bulkSetFavorite` exits afterwards, and that exit is the method
    // QUNLEASHED-P was about - here on the live-page path, where it has to
    // clear rather than return early.
    expect(selection.selectionMode, isFalse);
    expect(selection.selectedCount, 0);
  });

  /// The favourites page with **both** kinds of row, which nothing had mounted:
  /// its list is the starred keys followed by the starred apps, dispatched on
  /// one index, and with no starred key the offset into the apps is always
  /// zero. `faps[i]` in place of `faps[i - keys.length]` passed the whole
  /// suite, and is a `RangeError` on every build of a page that has one of
  /// each (#404).
  testWidgets('the favourites list puts starred keys above starred apps', (
    tester,
  ) async {
    final mounted = await mountArchivePage(
      tester,
      client: client,
      seed: (storage) async {
        await seedKeys(storage);
        await starSome(storage);
      },
      page: (controller, sortSettings) =>
          FavoritesPage(controller: controller, sortSettings: sortSettings),
    );
    ctrl = mounted.controller;

    expect(keyNamed('carpark').favorite, isTrue, reason: "the case's premise");
    expect(find.text('carpark'), findsOneWidget);
    expect(find.text('zeta'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    // The key is not one of the apps, and the apps are below it.
    final key = tester.getTopLeft(find.text('carpark')).dy;
    expect(key, lessThan(tester.getTopLeft(find.text('zeta')).dy));
    expect(key, lessThan(tester.getTopLeft(find.text('beta')).dy));
    // And the rows that are not starred stayed behind.
    expect(find.text('card'), findsNothing);
    expect(find.text('door'), findsNothing);
  });
}

// Mutations run: widening the toolbar's `filtered.map((k) => k.id)` to
// `_allKeys.map(...)` fails the first case, which is the one this file was
// written for. Narrowing `_selectedKeys` to `_filtered` **survives**, and that
// is the half the header calls latent: both cases star or count a key the
// filter still shows, and the state where they differ cannot be built through
// the UI, because the search box is gone for as long as a selection is up.
