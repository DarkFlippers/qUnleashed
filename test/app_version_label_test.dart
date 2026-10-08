// Covers the one surface that shows a build its identity: ADR 0014 §3.
//
// The widget was rewritten rather than extended - the release-tag regex went,
// the build number and commit moved into the format's suffix slot, and the
// label gained tap-to-copy - and nothing covered any of it. The format is the
// product here: a line that drops the commit costs exactly what the change was
// for, and no test elsewhere would fail.
//
// Each case passes its own `BuildStamp` rather than mocking the platform
// channel. `package_info_plus` caches its answer in a static of its own, so a
// per-test channel mock exercises the plugin's cache and not this widget - the
// first draft of this file did that, and two cases read the previous one's
// version.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/overview/widgets/app_version.dart';
import 'package:qunleashed/services/build_identity.dart';
import 'package:qunleashed/theme/theme.dart';

Widget wrap(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: buildAppTheme(brightness, const Color(0xFFCC241D)),
      home: Scaffold(body: Center(child: child)),
    );

BuildStamp stamp({
  String version = '0.15.0',
  String build = '108080',
  BuildChannel channel = BuildChannel.dev,
  String commit = 'abc1234def',
}) => BuildStamp(
  version: version,
  build: build,
  channel: channel,
  commit: commit,
  flipperlibCommit: '',
  dartufbtCommit: '',
);

String labelText(WidgetTester tester) =>
    tester.widget<Text>(find.byType(Text)).data!;

void main() {
  testWidgets('names the version, the build number and the commit', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(AppVersionLabel(stamp: stamp())));
    await tester.pumpAndSettle();

    final text = labelText(tester);
    expect(
      text,
      contains('0.15.0-dev'),
      reason: 'the channel suffix 0014 §2 keeps wherever a person reads it',
    );
    expect(text, contains('108080'));
    expect(text, contains('abc1234'));
    expect(
      text,
      isNot(contains('abc1234def')),
      reason: 'the commit is abbreviated to seven, as git quotes it',
    );
  });

  // A release says nothing about its channel: a bare version already means
  // released, and `-release` is noise on the one build most people run.
  testWidgets('a release carries no suffix', (tester) async {
    await tester.pumpWidget(
      wrap(AppVersionLabel(stamp: stamp(channel: BuildChannel.release))),
    );
    await tester.pumpAndSettle();

    final text = labelText(tester);
    expect(text, contains('0.15.0'));
    expect(text, isNot(contains('-release')));
    expect(text, isNot(contains('-dev')));
  });

  // The empty-detail branch: neither a number nor a commit. It must not render
  // a dangling ' ()', which is what joining an empty list into the format's
  // suffix slot would produce.
  testWidgets('leaves out a detail it does not have', (tester) async {
    await tester.pumpWidget(
      wrap(
        AppVersionLabel(
          stamp: stamp(channel: BuildChannel.local, build: '', commit: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final text = labelText(tester);
    expect(text, contains('0.15.0-local'));
    expect(
      text,
      isNot(contains('(')),
      reason: 'an empty detail must not leave brackets behind',
    );
  });

  // PackageInfo refusing is the branch `caught` was added for. The label still
  // appears and says `unknown`, rather than vanishing - a blank space reads as
  // a layout bug - and the channel did not fail, so it is still named.
  testWidgets('says unknown rather than disappearing', (tester) async {
    await tester.pumpWidget(
      wrap(
        AppVersionLabel(
          stamp: stamp(version: '', build: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(labelText(tester), contains('unknown-dev'));
  });

  // The point of showing a SHA at all: nobody retypes one off a phone.
  testWidgets('copies the whole line when tapped', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(wrap(AppVersionLabel(stamp: stamp())));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Text));
    await tester.pump();

    expect(copied, contains('0.15.0-dev'));
    expect(copied, contains('108080'));
    expect(copied, contains('abc1234'));
  });

  // The future is created in the State, not in `build`. A fresh one per build
  // resets the FutureBuilder to `waiting` and the line disappears for a frame,
  // which `test/build_io_budget_test.dart` cannot see here - its scan is per
  // file, so a call into another library is invisible to it. A theme change is
  // what rebuilds this subtree in the app, through `context.appColors`.
  testWidgets('survives a rebuild without blanking', (tester) async {
    await tester.pumpWidget(wrap(AppVersionLabel(stamp: stamp())));
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsOneWidget);

    await tester.pumpWidget(
      wrap(AppVersionLabel(stamp: stamp()), brightness: Brightness.light),
    );
    await tester.pump();

    expect(
      find.byType(Text),
      findsOneWidget,
      reason: 'a rebuild must not restart the read and blank the line',
    );
    expect(labelText(tester), contains('0.15.0-dev'));
  });
}
