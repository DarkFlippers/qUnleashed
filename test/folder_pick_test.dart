// What a refused folder pick does, on the platforms where the plugin hid it.
//
// `file_picker`'s `getDirectoryPath` catches every `PlatformException` and
// answers null for all of them, on Android and iOS both. So from Dart a
// refusal and a cancellation were the same value, and five surfaces (the
// archive's bulk save, Flibler's folder, Pixel Draw's export, and the file
// browser's download and upload) closed their dialog and said nothing. #353.
//
// `pickFolder` reaches past that Dart layer to the plugin's own method channel,
// which is where these cases live: the channel is the seam, so a mock handler
// is the refusal. Both mobile platforms run the same group, because
// `dartPluginClass: FilePickerIO` covers both and a switch that stops naming
// one of them puts that platform straight back behind the swallow.
//
// Three of the cases are about the shape of the call rather than its answer -
// the method and its arguments, the fall-back, and the desktop path leaving the
// channel alone - because the channel name and `dir` are copied from the
// plugin's 8.x source and nothing in a compile checks them. The two halves of
// that also fail differently, which is why both are here: a renamed *channel*
// degrades to the plugin's own call and says so, while a renamed *method* on
// the same channel latches the delegate, and only the pin on `dir` would catch
// it before a release does.
//
// The desktop half is the opposite arrangement: the channel must *not* be
// touched, because Linux and Windows let a failure out already and macOS
// answers this channel under a different method, so taking that branch there
// would turn every pick into a fall-back.
//
// Mutations run, with the results. Dropping the `LogService.caught` fails "and
// keeps the cause" and the desktop refusal; dropping the notification fails
// "and says so" and the desktop refusal; a `rethrow` in the catch fails all
// four cases where the pick failed, through the zone, because the tap that
// reaches it is a `VoidCallback` with nothing listening to the future. Taking
// the channel branch on every platform fails "a desktop pick is the plugin's
// own"; spelling the method anything but `dir`, and forwarding the desktop
// arguments to the channel, each fail "the call is the one the plugin makes";
// dropping the line the fall-back leaves fails "a channel that is gone falls
// back"; dropping the `_picking` guard fails "a second pick"; dropping the
// `context.mounted` check fails "a refusal that arrives after the page is
// gone"; narrowing the innermost catch to an `on` clause fails "a sentence
// that cannot be shown"; answering every failure with `commonPickFailed` fails
// "a platform with no picker says so"; and a toast at
// `QNotificationType.good` fails "and says so". Twenty-two in all against this
// file and its three neighbours, twenty-one killed - the innermost catch
// survived the first round, which is what the last case here was written for.
//
// The survivor is **removing the `kIsWeb` guard**, which nothing here can
// hold: `kIsWeb` is a compile-time `false` under the VM, so the branch it
// guards cannot be entered from a test. `folder_pick.dart` says why the line
// stays.
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/folder_pick.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/theme/theme.dart';

import 'kept_lines.dart';
import 'picker_fakes.dart';

/// The refusal the Android delegate reports for a tree URI it cannot resolve.
///
/// `FilePickerDelegate.java:153` - `finishWithError("unknown_path", ...)` - and
/// the plugin's Dart layer is what turns it into a null.
final _refused = PlatformException(
  code: 'unknown_path',
  message: 'Failed to retrieve directory path.',
);

void main() {
  late List<MethodCall> channelCalls;

  /// What [pick] pretends to run on, set by each group.
  late TargetPlatform platform;

  setUp(() {
    recordKeptLines();
    channelCalls = <MethodCall>[];
  });

  /// Answers the plugin's channel, recording every call for the cases that
  /// assert the shape of it.
  ///
  /// `answerFolderPick` has what the three answers mean and why leaving it
  /// uninstalled is not a fourth.
  void handleChannel({String? answer, Object? failure, Completer<void>? gate}) {
    answerFolderPick(
      path: answer,
      failure: failure,
      gate: gate,
      calls: channelCalls,
    );
  }

  /// The app around a [child], with the theme the notification card needs.
  ///
  /// The theme is built once: the card reads `appColors` off it and throws on
  /// a bare `ThemeData`, and `buildAppTheme` runs an HSL loop per call that
  /// every case here would pay again for the same answer.
  final theme = buildAppTheme(Brightness.dark, const Color(0xFFCC241D));
  Widget app(Widget child) => MaterialApp(theme: theme, home: child);

  /// Runs [body] as if on [platform].
  ///
  /// The override is applied here and cleared in a `finally`, rather than in a
  /// `setUp` and a teardown: `flutter_test` asserts every foundation debug
  /// variable is unset when the *body* ends, and a teardown registered with
  /// `addTearDown` runs after that check. The `finally` is so a failing case
  /// does not leak its platform into the next group and turn one red case into
  /// a cascade that reads as a platform bug.
  Future<void> onPlatform(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// A button that picks a folder when tapped.
  ///
  /// A `VoidCallback` on purpose: a rejection out of [pickFolder] would have
  /// no listener here and would reach the zone, which `testWidgets` fails the
  /// test for - so every case in this file is also the "never rejects"
  /// assertion.
  Widget picker(void Function(BuildContext) onTap) => Builder(
    builder: (context) =>
        TextButton(onPressed: () => onTap(context), child: const Text('pick')),
  );

  /// Taps a button that calls [pickFolder], and answers what it answered.
  ///
  /// [done] guards the vacuous reading, where the button was never tapped and
  /// null means "not called".
  Future<({String? path, bool done})> pick(
    WidgetTester tester, {
    String what = '[Archive] the folder pick',
    String dialogTitle = 'Choose a folder',
    String? initialDirectory,
  }) async {
    String? path;
    var done = false;
    await onPlatform(() async {
      await tester.pumpWidget(
        app(
          picker((context) async {
            path = await pickFolder(
              context,
              what: what,
              dialogTitle: dialogTitle,
              initialDirectory: initialDirectory,
            );
            done = true;
          }),
        ),
      );
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();
    });
    return (path: path, done: done);
  }

  for (final mobile in const [TargetPlatform.android, TargetPlatform.iOS]) {
    group('on ${mobile.name}, where the plugin swallowed the refusal', () {
      setUp(() => platform = mobile);

      testWidgets('the chosen folder comes back, and nothing is said', (
        tester,
      ) async {
        handleChannel(answer: '/storage/emulated/0/Download');

        final result = await pick(tester);

        expect(result.done, isTrue);
        expect(result.path, '/storage/emulated/0/Download');
        expect(keptLines, isEmpty);
        expect(find.text(l10nGlobal.commonPickFailed), findsNothing);
      });

      testWidgets('a cancelled pick is still silent', (tester) async {
        // The common case by far, and the reason a refusal cannot simply be
        // reported on every null: a toast per cancel is worse than silence.
        handleChannel();

        final result = await pick(tester);

        expect(result.done, isTrue);
        expect(result.path, isNull);
        expect(keptLines, isEmpty);
        expect(find.text(l10nGlobal.commonPickFailed), findsNothing);
      });

      testWidgets('a refusal answers null rather than rejecting', (
        tester,
      ) async {
        handleChannel(failure: _refused);

        final result = await pick(tester);

        // The contract the five call sites rest on: they read null as
        // "cancelled" and return, and none of them has a `try`.
        expect(result.done, isTrue);
        expect(result.path, isNull);
      });

      testWidgets('and says so, which is the whole complaint', (tester) async {
        handleChannel(failure: _refused);

        await pick(tester);

        expect(find.text(l10nGlobal.commonPickFailed), findsOneWidget);
        // The card's type, not just its sentence: `QNotificationType.good`
        // shows the same words in the shape of a success, and matching only
        // the text cannot tell the two apart.
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      });

      testWidgets('and keeps the cause, under the caller it was given', (
        tester,
      ) async {
        handleChannel(failure: _refused);

        await pick(tester, what: '[Flibler] the folder pick');

        // `contains` and not equality: the body carries `describe(e, st)`, so
        // the stack is in it. What is asserted is what a reader of a report
        // needs - which surface asked, and the plugin's own code, which is
        // the whole of what tells a refused tree URI from a missing picker.
        expect(keptLines, hasLength(1));
        expect(keptLines.single, contains('[Flibler] the folder pick failed'));
        expect(keptLines.single, contains('unknown_path'));
        // Kept, not alerted. ADR 0013 §5: nobody can be paged for a provider
        // that will not resolve a tree URI, and at `warn` every refused pick
        // would wake somebody.
        expect(keptLevels, [KeptLevel.caught]);
      });

      testWidgets('the call is the one the plugin makes', (tester) async {
        handleChannel(answer: '/sdcard');

        await pick(tester, dialogTitle: 'Choose', initialDirectory: '/sdcard');

        // Pinned because nothing else can be: `dir` and the empty argument
        // map are copied from `FilePickerIO.getDirectoryPath`, and a compile
        // cannot tell whether they still match the plugin. The two arguments
        // are deliberately *not* forwarded - the plugin drops both on mobile,
        // both being desktop-only, so sending them would invent a contract.
        expect(channelCalls, hasLength(1));
        expect(channelCalls.single.method, 'dir');
        expect(channelCalls.single.arguments, <String, dynamic>{});
      });

      testWidgets('and it is the call the installed plugin makes', (
        tester,
      ) async {
        // The pin that matters, and the one the case above cannot be: that
        // one asserts the *shim* sends `dir` with an empty map, which stays
        // green if a major bump renames the method and the shim is updated to
        // match - the renamed-method case `folder_pick.dart` warns about,
        // where the delegate latches and every pick answers null. This drives
        // the plugin's own implementation over a channel of the same name and
        // asserts it makes the same call, so the two are pinned to each other
        // rather than to a transcription.
        //
        // `FilePickerIO` is exported from the package root. If a federated
        // split moves it, this stops compiling - a loud failure on exactly
        // the event that matters.
        //
        // The channel is rebuilt here with the plugin's *host* codec:
        // `file_picker_io.dart` picks `JSONMethodCodec` from `dart:io`'s
        // `Platform` at library load, not from `defaultTargetPlatform`, so
        // under `flutter test` on a desktop machine that is what its call is
        // encoded with. What this case pins - the method and its arguments -
        // is the same either way.
        final calls = <MethodCall>[];
        const hostChannel = MethodChannel(
          'miguelruivo.flutter.plugins.filepicker',
          JSONMethodCodec(),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(hostChannel, (call) async {
              calls.add(call);
              return '/sdcard';
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(hostChannel, null),
        );

        await onPlatform(() => FilePickerIO().getDirectoryPath());

        expect(calls, hasLength(1));
        expect(calls.single.method, 'dir');
        expect(calls.single.arguments, <String, dynamic>{});
      });

      testWidgets('a second pick while one is open answers null', (
        tester,
      ) async {
        // A double tap, which the platform answers badly: `already_active` on
        // Android, and on iOS a `multiple_request` that *also* drops the
        // first call's result handle. Surfacing either would report a tap as
        // a failed pick, so the shim refuses to start the second one.
        final gate = Completer<void>();
        handleChannel(answer: '/first', gate: gate);
        final answers = <String?>[];
        await onPlatform(() async {
          await tester.pumpWidget(
            app(
              picker((context) async {
                final first = pickFolder(
                  context,
                  what: '[Archive] the folder pick',
                  dialogTitle: 'Choose a folder',
                );
                // The second tap, while the first dialog is still up.
                answers.add(
                  await pickFolder(
                    context,
                    what: '[Archive] the folder pick',
                    dialogTitle: 'Choose a folder',
                  ),
                );
                answers.add(await first);
              }),
            ),
          );
          await tester.tap(find.text('pick'));
          await tester.pump();
          gate.complete();
          await tester.pumpAndSettle();
        });

        // The second answer first, then the first pick's own. The second
        // never reached the platform, which is the point: one call.
        expect(answers, [null, '/first']);
        expect(channelCalls, hasLength(1));
        // Nothing said, because nothing failed: the dialog the user is
        // looking at is still going to answer.
        expect(keptLines, isEmpty);
        expect(find.text(l10nGlobal.commonPickFailed), findsNothing);
      });

      testWidgets('a refusal that arrives after the page is gone', (
        tester,
      ) async {
        // The ordinary shape of a long pick: the user leaves the page while
        // the system dialog is up, and the refusal lands on a dead context.
        // `showNotification` reads the root `Overlay` off it, so without the
        // `mounted` check this throws *inside the catch* and rejects out of a
        // function five callers trust not to - QUNLEASHED-K's mechanism.
        final gate = Completer<void>();
        handleChannel(failure: _refused, gate: gate);
        String? path;
        var done = false;
        await onPlatform(() async {
          await tester.pumpWidget(
            app(
              picker((context) async {
                path = await pickFolder(
                  context,
                  what: '[Archive] the folder pick',
                  dialogTitle: 'Choose a folder',
                );
                done = true;
              }),
            ),
          );
          await tester.tap(find.text('pick'));
          await tester.pump();
          await tester.pumpWidget(app(const SizedBox.shrink()));
          gate.complete();
          await tester.pumpAndSettle();
        });

        expect(done, isTrue, reason: 'it still has to answer its caller');
        expect(path, isNull);
        // The record survives a page that does not: the line is written
        // before the sentence is attempted.
        expect(keptLines, hasLength(1));
        expect(keptLines.single, contains('the folder pick failed'));
        expect(find.text(l10nGlobal.commonPickFailed), findsNothing);
      });

      testWidgets('a channel that is gone falls back, and records that', (
        tester,
      ) async {
        // What a renamed channel looks like from Dart, thrown from the
        // handler because an unregistered channel would hang instead (see
        // `handleChannel`). The fix going quiet rather than the app losing
        // its folder picker is the trade, and the line is the only thing
        // that would say which of the two happened.
        handleChannel(
          failure: MissingPluginException(
            'No implementation found for method dir',
          ),
        );
        final plugin = StubFilePicker(folder: '/fallback');
        FilePicker.platform = plugin;

        final result = await pick(tester);

        expect(result.path, '/fallback');
        expect(plugin.calls, 1);
        expect(keptLines, hasLength(1));
        expect(keptLines.single, contains('fell back to the plugin'));
        expect(
          keptLines.single,
          contains('miguelruivo.flutter.plugins.filepicker'),
        );
        expect(keptLevels, [KeptLevel.caught]);
        // The pick itself worked, so the user is told nothing.
        expect(find.text(l10nGlobal.commonPickFailed), findsNothing);
      });

      testWidgets('and reports it when the fall-back fails too', (
        tester,
      ) async {
        // Both halves gone: no handler on the channel and a plugin that
        // cannot pick either. Two lines, in order, and one sentence - and
        // `keptLines.single` elsewhere in this file is why it is worth
        // pinning that this is the shape that produces two.
        handleChannel(failure: MissingPluginException('no dir'));
        FilePicker.platform = StubFilePicker(failure: _refused);

        final result = await pick(tester);

        expect(result.done, isTrue);
        expect(result.path, isNull);
        expect(keptLines, hasLength(2));
        expect(keptLines.first, contains('fell back to the plugin'));
        expect(keptLines.last, contains('the folder pick failed'));
        expect(find.text(l10nGlobal.commonPickFailed), findsOneWidget);
      });
    });
  }

  group('on a desktop platform, where it never hid anything', () {
    setUp(() => platform = TargetPlatform.windows);

    testWidgets('a desktop pick is the plugin\'s own, title and all', (
      tester,
    ) async {
      handleChannel(answer: '/not-this');
      final plugin = StubFilePicker(folder: r'C:\Downloads');
      FilePicker.platform = plugin;

      final result = await pick(
        tester,
        dialogTitle: 'Choose a folder',
        initialDirectory: r'C:\Projects',
      );

      expect(result.path, r'C:\Downloads');
      // The channel is the mobile workaround and nothing else. Linux and
      // Windows are Dart implementations - zenity, a COM call - that answer
      // no channel at all, and macOS answers *this* channel under a
      // `getDirectoryPath` method rather than `dir`, so taking that branch
      // here would turn every desktop pick into a fall-back.
      expect(channelCalls, isEmpty);
      expect(plugin.title, 'Choose a folder');
      expect(plugin.initial, r'C:\Projects');
      expect(keptLines, isEmpty);
    });

    testWidgets('a desktop refusal is reported the same way', (tester) async {
      // What Linux throws with no `zenity` on the path: a bare `Exception`
      // from `utils.dart`. It reached the call sites before this and each
      // reported it; the shim is where that lives now.
      final plugin = StubFilePicker(failure: Exception('zenity not found'));
      FilePicker.platform = plugin;

      final result = await pick(tester, what: '[Paint] the export folder pick');

      expect(result.done, isTrue);
      expect(result.path, isNull);
      expect(find.text(l10nGlobal.commonPickFailed), findsOneWidget);
      expect(keptLines, hasLength(1));
      expect(
        keptLines.single,
        contains('[Paint] the export folder pick failed'),
      );
      expect(keptLines.single, contains('zenity'));
    });

    testWidgets('a sentence that cannot be shown does not reject', (
      tester,
    ) async {
      // A live context with nothing to show a card on: `QNotification.show`
      // reads the root `Overlay` off it and throws when there is none, and
      // that throw happens *inside* the catch block. Five callers have no
      // `try` between them and `pickFolder`'s promise to answer rather than
      // reject, and four of them are reached from a `VoidCallback` - so this
      // is the one place where a throw from the reporting would be
      // QUNLEASHED-K again, by way of the fix for it.
      //
      // Reachable in production the same way the unmounted case is, through a
      // route torn down around a dialog that is still up; cheaper to arrange
      // here by leaving the app out of the tree entirely.
      FilePicker.platform = StubFilePicker(failure: Exception('no zenity'));
      String? path;
      var done = false;
      await onPlatform(() async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: picker((context) async {
              path = await pickFolder(
                context,
                what: '[Archive] the folder pick',
                dialogTitle: 'Choose a folder',
              );
              done = true;
            }),
          ),
        );
        await tester.tap(find.text('pick'));
        await tester.pumpAndSettle();
      });

      expect(done, isTrue, reason: 'it still has to answer its caller');
      expect(path, isNull);
      // Both lines: the failure, then that the user was not told about it.
      expect(keptLines, hasLength(2));
      expect(keptLines.first, contains('the folder pick failed'));
      expect(keptLines.last, contains('could not be shown'));
      expect(keptLevels, [KeptLevel.caught, KeptLevel.caught]);
    });

    testWidgets('a platform with no picker says so instead', (tester) async {
      // The one failure `fmFolderPickUnsupported` describes correctly, and
      // the reason the string is still in use: a `MissingPluginException`
      // from the plugin's own call is this platform having no picker at all.
      // Everything else gets the generic sentence, which is what the two file
      // browser sites used to show for every throw.
      FilePicker.platform = StubFilePicker(
        failure: MissingPluginException('no implementation'),
      );

      final result = await pick(tester);

      expect(result.path, isNull);
      expect(find.text(l10nGlobal.fmFolderPickUnsupported), findsOneWidget);
      expect(find.text(l10nGlobal.commonPickFailed), findsNothing);
      expect(keptLines, hasLength(1));
    });
  });
}
