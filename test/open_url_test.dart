import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/open_url.dart';

import 'kept_lines.dart';

/// Opening a link, and what it says when nothing opens.
///
/// There is no failure state on screen for this: the user taps a link and the
/// app carries on as though nothing was tapped. The in-app view falls back to
/// the external browser and the external browser falls back to nothing, so the
/// last of those catches is the end of the line and used to keep no record of
/// it. ADR 0008.
const _channel = MethodChannel('plugins.flutter.io/url_launcher');
const _url = 'https://example.invalid/help';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  late int logBase;

  /// Answers the launcher channel. [fails] is a platform that cannot open a
  /// browser at all - no handler, no default app, a locked-down device.
  void launcher({required bool fails}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (fails) {
            throw PlatformException(code: 'no browser');
          }
          return true;
        });
  }

  setUp(() {
    clearKeptLines();
    logBase = keptLines.length;
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });
  });

  Iterable<String> lines(String fragment) =>
      keptLines.skip(logBase).where((l) => l.contains(fragment));

  /// Taps a link from a real tree, because `openUrl` takes a context.
  ///
  /// The platform is put back before the body ends rather than in a teardown:
  /// the test framework checks the foundation debug variables between the two
  /// and fails the case if one is still set.
  Future<void> tap(
    WidgetTester tester,
    TargetPlatform platform, {
    String url = _url,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      late BuildContext ctx;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      );
      await openUrl(ctx, url);
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  group('a link that will not open', () {
    // Android and iOS try the in-app view first and fall through to the
    // external browser. Both are gone here, which is the case that leaves the
    // screen looking like the tap never happened.
    testWidgets('is reported where the in-app view is tried first', (
      tester,
    ) async {
      launcher(fails: true);

      await tap(tester, TargetPlatform.android);

      expect(lines(_url), hasLength(1));
    });

    // Desktop goes straight to the external browser, so the same failure
    // arrives through a different path.
    testWidgets('is reported where there is no in-app view', (tester) async {
      launcher(fails: true);

      await tap(tester, TargetPlatform.windows);

      expect(lines(_url), hasLength(1));
    });

    // The fallback is the point: reporting the in-app attempt as well would
    // put two lines up for one tap, on every platform that has one.
    testWidgets('is reported once, not once per attempt', (tester) async {
      launcher(fails: true);

      await tap(tester, TargetPlatform.android);

      expect(lines('[OpenUrl]'), hasLength(1));
    });
  });

  testWidgets('a link that opens says nothing', (tester) async {
    launcher(fails: false);

    await tap(tester, TargetPlatform.android);

    expect(lines('[OpenUrl]'), isEmpty);
  });

  // Nothing is attempted and nothing is reported - there is no failure here,
  // only a caller with nothing to open.
  testWidgets('an empty url is not a failure', (tester) async {
    launcher(fails: true);

    await tap(tester, TargetPlatform.android, url: '');

    expect(lines('[OpenUrl]'), isEmpty);
  });
}
