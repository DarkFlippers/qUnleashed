// The archive's rename prompt, which two pages shared by copying it.
//
// The overview and its category page each held the same hand-rolled
// `showDialog<String>`, trimming the answer and checking nothing else, so a
// name with a `/` went to the device and came back as "Could not rename".
// Both call one `promptRenameKey` now, and what it has to get right is
// narrow: do not rename to the name the key already has, and do not rename at
// all when the user dismissed it. #277
import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/archive/models/key.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/pages/archive/overview/rename_key.dart';
import 'package:qunleashed/services/archive/storage.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';

/// Records what it was asked to rename, and nothing else.
///
/// A subclass rather than a fake client: what is under test is the prompt's
/// decision to call `renameKey` at all, not what the controller does with it.
class _SpyController extends ArchiveController {
  _SpyController() : super(client: _IdleFlipper(), storage: ArchiveStorage());

  final renames = <String>[];

  /// What the device said, for the half of the prompt that reports it. The
  /// spy answered null for this at first, so the whole `reportArchiveFailure`
  /// call could be deleted with every test still green - which is the failure
  /// #110 is about, one layer up.
  String? failure;

  @override
  String? get lastFailure => failure;

  @override
  Future<void> renameKey(ArchiveKey key, String newName) async {
    renames.add(newName);
  }
}

/// A client that is simply not connected, which is all the controller's
/// constructor asks about.
class _IdleFlipper implements FlipperClient {
  @override
  bool get isConnected => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final key = ArchiveKey(
    name: 'gate',
    category: ArchiveCategory.subghz,
    state: ArchiveKeyState.synced,
    extension: 'sub',
    remotePath: '/ext/subghz/gate.sub',
  );

  late _SpyController controller;

  setUp(() {
    controller = _SpyController();
    addTearDown(controller.dispose);
  });

  Future<void> openPrompt(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: buildAppTheme(Brightness.dark, const Color(0xFFFF8A00)),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                promptRenameKey(context, controller: controller, key: key),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renames to the name that was typed', (tester) async {
    await openPrompt(tester);

    await tester.enterText(find.byType(TextField), 'front gate');
    await tester.tap(find.widgetWithText(TextButton, 'Rename').last);
    await tester.pumpAndSettle();

    expect(controller.renames, ['front gate']);
  });

  // The prompt opens on the current name, so confirming without typing is the
  // easiest thing a user can do by accident - and it would be an RPC rename of
  // a file onto itself.
  testWidgets('does not rename when the name is unchanged', (tester) async {
    await openPrompt(tester);

    // The field's starting content, asserted: without this the case passes
    // just as well when the prompt opens *empty*, because then the confirm
    // button is disabled and nothing is renamed for an unrelated reason.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'gate',
    );

    await tester.tap(find.widgetWithText(TextButton, 'Rename').last);
    await tester.pumpAndSettle();

    expect(controller.renames, isEmpty);
  });

  testWidgets('says what the device said when the rename failed', (
    tester,
  ) async {
    controller.failure = 'ERROR_STORAGE_DENIED';
    await openPrompt(tester);

    await tester.enterText(find.byType(TextField), 'front gate');
    await tester.tap(find.widgetWithText(TextButton, 'Rename').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('ERROR_STORAGE_DENIED'), findsOneWidget);
  });

  // The budget the prompt passes, which is the volume's minus the extension
  // the controller appends. Nothing else observes the arithmetic, and a name
  // approved here at 255 would reach `storageRename` at 259.
  testWidgets('leaves room for the extension the controller adds', (
    tester,
  ) async {
    await openPrompt(tester);
    final confirm = find.widgetWithText(TextButton, 'Rename').last;

    // 255 - len('sub') - 1 = 251 is the longest base name that fits.
    await tester.enterText(find.byType(TextField), 'x' * 251);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextButton>(confirm).onPressed,
      isNotNull,
      reason: 'exactly the budget is allowed',
    );

    await tester.enterText(find.byType(TextField), 'x' * 252);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(confirm).onPressed, isNull);
  });

  testWidgets('does not rename when the prompt is dismissed', (tester) async {
    await openPrompt(tester);

    await tester.enterText(find.byType(TextField), 'front gate');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(controller.renames, isEmpty);
  });

  // The rule the prompt carries, through the shared dialog: a name the device
  // will not take cannot be confirmed at all.
  testWidgets('cannot confirm a name the Flipper will not carry', (
    tester,
  ) async {
    await openPrompt(tester);

    await tester.enterText(find.byType(TextField), 'gate/one');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Rename').last);
    await tester.pumpAndSettle();

    expect(controller.renames, isEmpty);
    expect(find.textContaining(r'\ / : * ? " < > |'), findsOneWidget);
  });
}
