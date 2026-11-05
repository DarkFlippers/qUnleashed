import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/pages/archive/overview/category/category_page.dart';
import 'package:qunleashed/pages/archive/overview/category/favorites_page.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/services/archive/sort_settings.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'archive_fakes.dart';
import 'kept_lines.dart';

/// The sort reaching the lists, which neither the comparator's tests nor the
/// toolbar's can say anything about.
///
/// Between them sits the wiring that makes #122 a feature rather than three
/// correct parts: the page reads the shared store, a pick is reported back to
/// it, and a pick made on one table moves the others the desktop rail keeps
/// mounted. Three mutations survived the whole suite before this file -
/// `animation: _repaint` back to `animation: _ctrl`, `offered:` down to a
/// `const []`, and the direction dropped on the way into `sortArchiveKeys` -
/// and each of them is this feature quietly doing nothing.
///
/// Favourite apps carry it on their own: they are read off disk by
/// `initialize()` and never touched by the device walk, so the fake client
/// only has to answer an empty listing.
///
/// The mount is `archive_fakes.dart`'s, which is where the reason the disk
/// setup has to run inside [WidgetTester.runAsync] is written down (#376).
class _QuietFlipper with FlipperRpcFake, ArchiveRpcFake {
  @override
  List<Main> framesFor(Main request) {
    if (!request.hasStorageListRequest()) return const [];
    return [Main(storageListResponse: ListResponse())];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  useTempArchiveRoot('archive_sort_page');

  late _QuietFlipper client;
  late ArchiveSortSettings settings;

  setUp(() {
    clearKeptLines();
    SharedPreferences.setMockInitialValues(const {});
    client = _QuietFlipper();
  });

  /// Brings up a controller with two folders of starred apps and pumps [page]
  /// on it.
  ///
  /// The names disagree with the folders on purpose: by name alone the order
  /// is alpha, beta, zeta, so nothing below that reads folder-first can pass
  /// on a name sort.
  Future<void> pumpPage(
    WidgetTester tester,
    Widget Function(ArchiveController ctrl, ArchiveSortSettings settings) page,
  ) async {
    final mounted = await mountArchivePage(
      tester,
      client: client,
      seed: (storage) => storage.writeFapFavorites(archiveTestDevice, const [
        (path: '/ext/apps/Tools/zeta.fap', name: 'zeta'),
        (path: '/ext/apps/Tools/alpha.fap', name: 'alpha'),
        (path: '/ext/apps/GPIO/beta.fap', name: 'beta'),
      ]),
      page: page,
    );
    settings = mounted.sortSettings;
  }

  Future<void> pumpFavorites(WidgetTester tester) => pumpPage(
    tester,
    (ctrl, settings) => FavoritesPage(controller: ctrl, sortSettings: settings),
  );

  /// The app names in the order the table lists them down the screen.
  List<String> rows(WidgetTester tester) =>
      [
        for (final name in const ['alpha', 'beta', 'zeta'])
          if (tester.any(find.text(name))) name,
      ]..sort(
        (a, b) => tester
            .getTopLeft(find.text(a))
            .dy
            .compareTo(tester.getTopLeft(find.text(b)).dy),
      );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.sort_rounded));
    await settle(tester);
  }

  testWidgets('opens in the sort that was stored', (tester) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'archive.sort': 'folder:asc',
    });

    await pumpFavorites(tester);

    // GPIO before Tools, each folder's apps by name inside it.
    expect(rows(tester), ['beta', 'alpha', 'zeta']);
  });

  testWidgets('a pick from the sheet reorders the list and is stored', (
    tester,
  ) async {
    await pumpFavorites(tester);
    expect(rows(tester), ['alpha', 'beta', 'zeta'], reason: 'by name first');

    await openSheet(tester);
    await tester.tap(find.text(l10n.sortByFolder));
    await settle(tester);

    expect(settings.key, 'folder');
    expect(rows(tester), ['beta', 'alpha', 'zeta']);
  });

  testWidgets('a sort picked on another table reaches this one', (
    tester,
  ) async {
    // Why the store is owned by `AppShell` and merged into each page's
    // `AnimatedBuilder`: the rail keeps several tables mounted and a sort
    // picked on one has to move the rest. Nothing rebuilds this page here
    // except the store's own notification.
    await pumpFavorites(tester);
    expect(rows(tester), ['alpha', 'beta', 'zeta']);

    await settings.setSort('folder', asc: true);
    await settle(tester);

    expect(rows(tester), ['beta', 'alpha', 'zeta']);
  });

  testWidgets('descending turns the folders around, not the names', (
    tester,
  ) async {
    await pumpFavorites(tester);

    await settings.setSort('folder', asc: false);
    await settle(tester);

    // Tools before GPIO, but alpha still before zeta inside Tools.
    expect(rows(tester), ['alpha', 'zeta', 'beta']);
  });

  testWidgets('a category page offers its own keys and reports a pick', (
    tester,
  ) async {
    // The per-category `offered` set, which the store's own tests can only
    // stand in for with a hand-written list. NFC offers `uid`; the deleted
    // and favourites tables do not.
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'archive.sort': 'uid:asc',
    });

    await pumpPage(
      tester,
      (ctrl, settings) => CategoryPage(
        controller: ctrl,
        sortSettings: settings,
        category: ArchiveCategory.nfc,
      ),
    );
    await openSheet(tester);

    expect(find.text('UID'), findsOneWidget, reason: 'NFC offers it');

    await tester.tap(find.text(l10n.sortByName));
    await settle(tester);

    expect(settings.key, 'name');
    expect(settings.asc, isTrue, reason: 'a new key starts ascending');
  });
}
