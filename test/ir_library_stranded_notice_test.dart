import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/infrared/controller.dart';
import 'package:qunleashed/pages/tools/infrared/local_repo.dart';
import 'package:qunleashed/pages/tools/infrared/settings_dialog.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';

final String sep = Platform.pathSeparator;

Widget wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: Scaffold(body: child),
);

void main() {
  late Directory base;
  late Directory root;

  setUp(() {
    base = Directory.systemTemp.createTempSync('ir_stranded_test');
    root = Directory('${base.path}${sep}irlib');
    IrLibLocalRepo.debugUseRoot(root);
    addTearDown(() => IrLibLocalRepo.debugUseRoot(null));
  });

  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  /// The notice's own wording, minus the path it names.
  ///
  /// Derived rather than pasted, so the check follows the copy in app_en.arb
  /// instead of pinning a second copy of it here - and so "no notice" is a
  /// claim about the notice itself rather than about the path it would have
  /// named.
  Finder noticeFinder() {
    const marker = '<<PATH>>';
    final wording = l10nGlobal.irLibraryStranded(marker).split(marker).first;
    return find.textContaining(wording, findRichText: true);
  }

  /// Leaves the library where an interrupted swap put it, with the restore
  /// blocked the way a stray file at the library path would block it.
  Directory strandTheLibrary() {
    final aside = Directory('${root.path}.superseded.1000')
      ..createSync(recursive: true);
    Directory('${aside.path}${sep}TVs').createSync(recursive: true);
    File('${aside.path}${sep}TVs${sep}Old.ir').writeAsStringSync('old remote');
    File(root.path).writeAsStringSync('in the way');
    return aside;
  }

  // The whole point of #85. Recovery keeps the tree because it is the only
  // copy of the library there is, and in a release build the log line saying
  // so is compiled out — LogService.enabled is const-folded to false. This
  // dialog is where the user decides whether to spend the download again, so
  // it is the one place saying so changes what they do.
  testWidgets('the IRDB dialog says where a stranded library is', (
    tester,
  ) async {
    final aside = strandTheLibrary();
    // Through runAsync: testWidgets drives a fake clock, and real filesystem
    // work never completes under it.
    await tester.runAsync(IrLibLocalRepo.recoverStranded);

    await tester.pumpWidget(
      wrap(IrLibSettingsDialog(controller: IrLibController())),
    );
    await tester.pump();

    expect(noticeFinder(), findsOneWidget);
    expect(
      find.textContaining(aside.path, findRichText: true),
      findsOneWidget,
      reason: 'naming the path is the actionable part',
    );
  });

  testWidgets('and says nothing when there is nothing to say', (tester) async {
    Directory('${root.path}${sep}TVs').createSync(recursive: true);
    File('${root.path}${sep}TVs${sep}Sony.ir').writeAsStringSync('sony');
    await tester.runAsync(IrLibLocalRepo.recoverStranded);

    await tester.pumpWidget(
      wrap(IrLibSettingsDialog(controller: IrLibController())),
    );
    await tester.pump();

    expect(IrLibLocalRepo.strandedLibrary, isNull);
    expect(noticeFinder(), findsNothing);
  });

  test('the controller reports the path the recovery recorded', () async {
    final aside = strandTheLibrary();
    await IrLibLocalRepo.recoverStranded();

    expect(IrLibController().strandedLibraryPath, aside.path);
  });
}
