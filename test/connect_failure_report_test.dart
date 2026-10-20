// What a failed connect attempt turns into — ADR 0013 §2's classifier row.
//
// Through a real hub with its transport replaced, for the reason
// `sentry_capture.dart` gives: a metric, a breadcrumb and an issue are three
// different channels in sentry 9, so a fake in front of `Telemetry` would
// assert that this file's own arithmetic is right rather than that anything
// reaches Sentry. The hooks in `captureSignals` are where the SDK itself hands
// each one over.
//
// What this covers is the decision, not the plumbing: a kind the classifier
// knows is a counter nobody is paged for, and an unknown string over BLE is an
// issue - one per string, which is what makes that list a to-do list for the
// classifier. Which call site reports, with which transport and attempt, is
// `link_autoconnect_test.dart`'s half; this file drives the hook directly.
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/connection/connect_report.dart';
import 'package:qunleashed/services/telemetry/scrub.dart';
import 'package:qunleashed/services/telemetry/settings.dart';
import 'package:qunleashed/services/telemetry/telemetry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kept_lines.dart';
import 'quiet_log.dart';
import 'sentry_capture.dart';
import 'telemetry_sinks.dart';

/// A hub that keeps what it is given, with the production hooks installed.
///
/// `Telemetry.start` is what fills `connectFailureSink`, and going through it
/// rather than assigning the sink by hand is what keeps this file honest: the
/// assignment in `_wireSinks` is the one that ships.
///
/// The SDK's own init is a no-op here - the hub is already up, and
/// `SentryFlutter.init` would replace it with one nothing can read. Quiet
/// because `start()` reports the missing `path_provider` plugin at `caught`,
/// which is a stack per case in a talking build.
Future<CapturedSignals> _wiredHub() async {
  final seen = await captureSignals();
  final telemetry = Telemetry(
    settings: DiagnosticsSettings(),
    dsn: 'https://key@o1.ingest.de.sentry.io/2',
    init: (configure) async {},
    shutdown: () async {},
  );
  await quietlyAsync(telemetry.start);
  // The precondition every case rests on, asserted rather than assumed.
  // `start()` never throws by design and the line above swallows its console,
  // so a start that began returning early - a flipped default, a plan that
  // rejected the fake DSN - would leave every case here green and empty, which
  // is this repo's "passed for a different reason" shape.
  expect(connectFailureSink, isNotNull);
  return seen;
}

/// A thrown object that classifies, with [text] as its whole content.
class _ConnectError implements Exception {
  _ConnectError(this.text);

  final String text;

  @override
  String toString() => text;
}

/// The message `universal_ble` handed over for QUNLEASHED-X and QUNLEASHED-W.
///
/// Structurally as Sentry received it, and that is the point of building it
/// here rather than writing a trace that suits the regex: the plugin
/// concatenates `Log.getStackTraceString` whole and nests the result inside
/// `Message:` and then again inside `Details:`. So there are *two* frame
/// blocks and neither sits at the end of the string: the first is followed by
/// a newline and `, Details:`, the second by the newline the string ends on.
/// A pattern that only handled a trace at end-of-string, or only one per
/// message, would pass a hand-written fixture and leave these two events as
/// two issues.
///
/// The frame list is trimmed from eleven to four. That is the only liberty
/// taken, and it is taken for readability.
///
/// [noSource] and [handlerLine] are where the two devices differed. R8 spells
/// a frame with no source file differently between the two builds, and the
/// framework line numbers come from each ROM - which is the whole reason one
/// bug was filed twice.
String _npeMessage({required String noSource, required int handlerLine}) {
  final frames = <String>[
    'a2.F0.c($noSource:127)',
    'io.flutter.plugin.platform.k.a($noSource:24)',
    'android.os.Handler.handleCallback(Handler.java:$handlerLine)',
    'android.app.ActivityThread.main(ActivityThread.java:8068)',
  ].map((frame) => '\n\tat $frame').join();
  const nested =
      'UniversalBleException: Code: UniversalBleErrorCode.unknownError, '
      'Message: java.lang.NullPointerException, Details: Cause: null, '
      'Stacktrace: java.lang.NullPointerException';
  return 'UniversalBleException: Code: UniversalBleErrorCode.unknownError, '
      'Message: $nested$frames\n, Details: $nested$frames\n';
}

/// An error that cannot be described, which is a shape the app has met.
class _Hostile implements Exception {
  @override
  String toString() => throw StateError('no');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(resetTelemetrySinks);

  /// The fingerprint each of [messages] is filed under, in order.
  ///
  /// Five cases below ask one question - does this pair of strings group
  /// together - and differ only in the pair, so the pair is all they should
  /// have to say.
  Future<List<String>> fingerprintsFor(List<String> messages) async {
    final seen = await _wiredHub();
    for (final message in messages) {
      // Anchored rather than assumed. Every case here is about how an
      // *unclassified* string is filed, so a message the classifier has since
      // learned raises no issue at all - and what that looks like is
      // `settleAndClose` failing on its five-second deadline naming a count,
      // with nothing saying why. That is exactly how the GATT 133 needle
      // announced itself here, and `status 22` and `status 62` below are the
      // next most likely additions to the same list.
      expect(
        classifyConnectError(_ConnectError(message)),
        FlipperConnectErrorKind.unknown,
        reason:
            'the classifier now knows "$message"; this case needs one it '
            'does not',
      );
      reportConnectFailure(
        _ConnectError(message),
        StackTrace.empty,
        attempt: ConnectAttempt.manual,
        isBle: true,
      );
    }
    await settleAndClose(
      seen,
      until: () => seen.events.length >= messages.length,
    );
    return [for (final event in seen.events) event.fingerprint!.join(' ')];
  }

  group('a kind the classifier knows', () {
    test('is counted, with the dimensions §2 asks for', () async {
      final seen = await _wiredHub();

      reportConnectFailure(
        _ConnectError('connect timed out'),
        StackTrace.empty,
        attempt: ConnectAttempt.auto,
        isBle: true,
      );
      await settleAndClose(seen, until: () => seen.metrics.isNotEmpty);

      expect(seen.metric.name, 'device.connect.failed');
      expect(seen.metric.value, 1);
      expect(seen.metric.type, 'counter');
      expect(
        seen.attributes,
        allOf(
          containsPair('kind', 'deviceUnreachable'),
          containsPair('transport', 'ble'),
          containsPair('attempt', 'auto'),
        ),
      );
    });

    test(
      'is not an issue: nobody is paged for a Flipper out of range',
      () async {
        final seen = await _wiredHub();

        reportConnectFailure(
          _ConnectError('bluetooth is powered off'),
          StackTrace.empty,
          attempt: ConnectAttempt.scan,
          isBle: true,
        );
        await settleAndClose(seen, until: () => seen.metrics.isNotEmpty);

        expect(seen.events, isEmpty);
        expect(
          seen.attributes,
          allOf(
            containsPair('kind', 'bluetoothUnavailable'),
            // The third value of the vocabulary, which no other case reaches.
            containsPair('attempt', 'scan'),
          ),
        );
      },
    );

    test('leaves a breadcrumb of its own category', () async {
      // Not `flipperlib`, which is §4's timeline: an event carrying both has
      // to say which of the two said this. The transport is read off the same
      // line, which is where `usb` is pinned for a known kind.
      final seen = await _wiredHub();

      reportConnectFailure(
        _ConnectError('too many paired devices'),
        StackTrace.empty,
        attempt: ConnectAttempt.manual,
        isBle: false,
      );
      await settleAndClose(
        seen,
        until: () => seen.crumbs.any((c) => c.category == 'connection'),
      );

      final crumb = seen.crumbs.singleWhere((c) => c.category == 'connection');
      expect(crumb.message, 'connect failed: tooManyDevices on usb (manual)');
      expect(crumb.level, SentryLevel.warning);
    });
  });

  group('an unknown string over BLE', () {
    test('is an issue and not a count', () async {
      final seen = await _wiredHub();

      reportConnectFailure(
        _ConnectError('GATT writes are embargoed on Tuesdays'),
        StackTrace.empty,
        attempt: ConnectAttempt.manual,
        isBle: true,
      );
      await settleAndClose(seen, until: () => seen.events.isNotEmpty);

      expect(seen.metrics, isEmpty);
      final event = seen.events.single;
      expect(
        event.contexts['connect'],
        allOf(
          containsPair('message', 'GATT writes are embargoed on Tuesdays'),
          containsPair('kind', 'unknown'),
          containsPair('transport', 'ble'),
          containsPair('attempt', 'manual'),
        ),
      );
      // The string is in the fingerprint, which is the whole of §2's request:
      // Sentry's default groups on the stack, i.e. on which catch saw it.
      expect(
        event.fingerprint,
        contains('GATT writes are embargoed on Tuesdays'),
      );
      // And no breadcrumb, deliberately: the issue carries the string itself,
      // so a crumb saying `unknown` adds nothing to its own event. Pinned
      // because both this and its inverse would otherwise pass.
      expect(seen.crumbs.where((c) => c.category == 'connection'), isEmpty);
    });

    test('is one issue however many Flippers it arrives from', () async {
      // Without the signature the list in §2 is a list of devices, and the
      // string - the thing the classifier has to learn - is buried in an issue
      // per address.
      final prints = await fingerprintsFor([
        'link aa:bb:cc:dd:ee:ff went sideways',
        'link 11:22:33:44:55:66 went sideways',
      ]);

      expect(prints.first, prints.last);
      expect(prints.first, contains('link <id> went sideways'));
    });

    test('and an iOS peripheral identifier is masked whole', () async {
      // The arm that fires on iOS and macOS, where CoreBluetooth hands out a
      // UUID instead of a MAC - so on two of the six targets it is the only
      // one that can match.
      final prints = await fingerprintsFor([
        'peripheral aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee refused',
        'peripheral 11111111-2222-3333-4444-555555555555 refused',
      ]);

      expect(prints.first, prints.last);
      expect(prints.first, contains('peripheral <id> refused'));
    });

    test('while a status code is the cause, and keeps its own issue', () async {
      // 22 and 62, where this case used to read 133 and 22. 133 is now a
      // needle in `classifyConnectError` and never reaches an unknown report
      // again, so asking for its fingerprint here waited for an event that is
      // no longer raised - which is how that change announced itself. The
      // pair only has to be two short numeric codes that nothing classifies;
      // what is being asserted is the signature, not the classifier.
      final prints = await fingerprintsFor([
        'PlatformException(gatt, status 22)',
        'PlatformException(gatt, status 62)',
      ]);

      expect(prints.first, isNot(prints.last));
    });

    test('while a Java trace inside it is not part of the string', () async {
      // QUNLEASHED-X and QUNLEASHED-W: one NullPointerException inside
      // `universal_ble`'s Android plugin, filed as two issues because the
      // ROM's own framework line numbers ride along inside the message. The
      // pair below is those two events cut down to the frames that differed -
      // a OnePlus 6 on Android 11 against a Xiaomi on 16.
      final onePlus = _npeMessage(noSource: 'Unknown Source', handlerLine: 938);
      final xiaomi = _npeMessage(noSource: 'SourceFile', handlerLine: 1029);
      // So that a failure below is read as the fingerprint's and not the
      // scrubber's. `Scrub.outbound` runs first and has rules that a frame
      // can trip - its bare-filename allow-list includes `ir`, and a
      // `1.2345` anywhere becomes a coordinate - neither of which these two
      // reach.
      expect(Scrub.outbound(onePlus), onePlus);
      expect(Scrub.outbound(xiaomi), xiaomi);

      final prints = await fingerprintsFor([onePlus, xiaomi]);

      expect(prints.first, prints.last);
      expect(prints.first, contains('NullPointerException <frames>'));
      // Both blocks collapsed, not just the one at the end.
      expect(
        RegExp('<frames>').allMatches(prints.first).length,
        2,
        reason: 'the nested Message: and Details: blocks are both traces',
      );
    });

    test('though prose that merely says "at" is left alone', () async {
      // The other half of what the pattern promises, and the guard against
      // the simplification it invites: widening it to `\s*at\s` would
      // start eating sentences. Nothing else in the suite would notice.
      //
      // One message, because `contains` is the whole catch. A second message
      // asserting the two do not merge would add nothing: merging requires
      // these words to be eaten, which fails the `contains` first.
      final prints = await fingerprintsFor([
        'connect failed at the gatt layer',
      ]);

      expect(prints.single, contains('at the gatt layer'));
    });

    test('though carrying one at all still tells them apart', () async {
      // Why the frames leave a marker instead of collapsing to nothing. The
      // same sentence with and without a trace behind it is two reports, and
      // an empty replacement would have merged them - trading the split this
      // case fixes for a different one.
      final prints = await fingerprintsFor([
        'UniversalBleException: java.lang.NullPointerException',
        'UniversalBleException: java.lang.NullPointerException\n'
            '\tat android.os.Handler.handleCallback(Handler.java:938)',
      ]);

      expect(prints.first, isNot(prints.last));
    });

    test('and so does an HRESULT, which eight characters merged', () async {
      // The boundary the `while a status code is the cause` case cannot
      // reach: `22` and `62` were never
      // long enough for the bare-run rule to touch. These are - eight hex
      // characters, the shape `universal_ble`'s Windows plugin produces - and
      // at the old threshold both became `0x<id>`: one issue, second cause
      // never learned.
      final prints = await fingerprintsFor([
        'WinRT error 0x80070005 while connecting',
        'WinRT error 0x8007048F while connecting',
      ]);

      expect(prints.first, isNot(prints.last));
    });

    test('and what it carries is scrubbed first', () async {
      // `scrubEvent` walks neither a fingerprint nor a context, so this hook
      // is the whole of §6.2 for both fields - and an unclassified platform
      // string is exactly the kind that arrives carrying a path.
      final seen = await _wiredHub();

      reportConnectFailure(
        _ConnectError(r'dial failed reading /ext/nfc/Office badge.nfc'),
        StackTrace.empty,
        attempt: ConnectAttempt.manual,
        isBle: true,
      );
      await settleAndClose(seen, until: () => seen.events.isNotEmpty);

      final event = seen.events.single;
      final context = event.contexts['connect']! as Map<String, dynamic>;
      expect(context['message'], isNot(contains('Office badge')));
      expect(context['message'], Scrub.outbound(context['message'] as String));
      expect(event.fingerprint!.join(' '), isNot(contains('Office badge')));
    });
  });

  group('an unknown string over USB', () {
    // §2's row says `unknown` becomes an issue; `_reportConnectFailure` amends
    // it for USB and this is the amendment. The classifier's needles were
    // written against BLE stacks, so an unmatched USB string has nothing to be
    // learned into - and an issue per occurrence is an issue per replug.
    test('is counted at kind unknown rather than raised', () async {
      final seen = await _wiredHub();

      reportConnectFailure(
        _ConnectError('LIBUSB_ERROR_ACCESS claiming the interface'),
        StackTrace.empty,
        attempt: ConnectAttempt.manual,
        isBle: false,
      );
      await settleAndClose(seen, until: () => seen.metrics.isNotEmpty);

      expect(seen.events, isEmpty);
      expect(
        seen.attributes,
        allOf(
          containsPair('kind', 'unknown'),
          containsPair('transport', 'usb'),
        ),
      );
    });

    test('and still leaves the timeline a breadcrumb', () async {
      final seen = await _wiredHub();

      reportConnectFailure(
        _ConnectError('LIBUSB_ERROR_ACCESS claiming the interface'),
        StackTrace.empty,
        attempt: ConnectAttempt.auto,
        isBle: false,
      );
      await settleAndClose(
        seen,
        until: () => seen.crumbs.any((c) => c.category == 'connection'),
      );

      final crumb = seen.crumbs.singleWhere((c) => c.category == 'connection');
      expect(crumb.message, 'connect failed: unknown on usb (auto)');
    });
  });

  group('while nothing is listening', () {
    test('a build with reporting off reports nothing at all', () async {
      // The sink is the switch: `Telemetry.stop()` clears it, and a build with
      // no DSN never sets it. A call that reached Sentry anyway would be a
      // privacy failure, not a cosmetic one.
      final seen = await captureSignals();

      reportConnectFailure(
        _ConnectError('connect timed out'),
        StackTrace.empty,
        attempt: ConnectAttempt.manual,
        isBle: true,
      );
      // No `until`, and it is the one case in this file without one: there is
      // nothing whose arrival could end the wait, so this gets the quiet
      // window alone.
      await settleAndClose(seen);

      // Anchored on the precondition, because an absence cannot be: with no
      // sink there is no output whose arrival would prove the pipeline ran.
      expect(connectFailureSink, isNull);
      expect(seen.metrics, isEmpty);
      expect(seen.events, isEmpty);
      expect(seen.crumbs.where((c) => c.category == 'connection'), isEmpty);
    });

    test(
      'and an object whose toString() throws costs the caller nothing',
      () async {
        // Every call site is a `catch` with a user waiting on a dialog. The
        // classifier calls `toString()`, which `guarded` documents as real
        // enough to catch.
        await _wiredHub();
        // Recorded after wiring, deliberately: `start()` installs its own kept
        // sink, so a recorder put in before would be the one it replaced.
        recordKeptLines();

        expect(
          () => quietly(
            () => reportConnectFailure(
              _Hostile(),
              StackTrace.empty,
              attempt: ConnectAttempt.manual,
              isBle: true,
            ),
          ),
          returnsNormally,
        );

        // Surviving is half of it. The other half is that the loss is written
        // down - gutting the catch to `catch (_) {}` passes every other
        // assertion here, and `caught_budget_test.dart` is a ceiling, so it
        // would not notice either. `contains` and not `hasLength`, because
        // `LogService` folds a consecutive identical body.
        final lost = keptLines.where((l) => l.contains('was not reported'));
        expect(lost, isNotEmpty);
        // What survived a `toString()` that did not: the path that lost its
        // report, and the type of the thing it was reporting.
        expect(lost.last, contains('manual'));
        expect(lost.last, contains('_Hostile'));
      },
    );
  });
}
