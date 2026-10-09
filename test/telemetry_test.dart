// What a build decides before anything leaves it.
//
// The SDK's own init is not driven here - it is a static that brings up a
// native layer, and `Telemetry.start` is five assignments once the decision
// is made. The decision is what this covers: the three reasons nothing is
// sent, the release name 0014 §5 pins, the tags §3 asks for, and the scrubber
// §6 puts in front of every event.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/build_identity.dart';
import 'package:qunleashed/services/telemetry/scrub.dart';
import 'package:qunleashed/services/telemetry/settings.dart';
import 'package:qunleashed/services/telemetry/telemetry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Full SHAs, because that is what the define carries and what a tag has to
/// hold: the seven-character form is for a person reading a line, not for a
/// key Sentry resolves against three repositories.
const String appSha = '1111111111111111111111111111111111111111';
const String libSha = '2222222222222222222222222222222222222222';
const String ufbtSha = '3333333333333333333333333333333333333333';

BuildStamp _stamp({
  String version = '0.15.0',
  String build = '108080',
  BuildChannel channel = BuildChannel.dev,
  String commit = appSha,
  String flipperlibCommit = '',
  String dartufbtCommit = '',
}) => BuildStamp(
  version: version,
  build: build,
  channel: channel,
  commit: commit,
  flipperlibCommit: flipperlibCommit,
  dartufbtCommit: dartufbtCommit,
);

TelemetryPlan _plan({
  String dsn = 'https://key@o1.ingest.de.sentry.io/2',
  bool shareLogs = true,
  BuildStamp? stamp,
}) => TelemetryPlan(dsn: dsn, shareLogs: shareLogs, stamp: stamp ?? _stamp());

void main() {
  group('whether anything is sent', () {
    test('a DSN and the switch on is the only combination that reports', () {
      expect(_plan().enabled, isTrue);
      expect(_plan().why, isNull);
    });

    test('no DSN compiled in says so rather than failing', () {
      final plan = _plan(dsn: '');
      expect(plan.enabled, isFalse);
      expect(plan.why, contains('no DSN'));
    });

    test('the switch off is reported as the switch, not as a missing DSN', () {
      // The two reasons are told apart on purpose: one is a build nobody gave
      // a DSN to, which is every local run, and the other is the user's
      // answer. A single "not reporting" would make a developer go looking
      // for a define they had already passed.
      final plan = _plan(shareLogs: false);
      expect(plan.enabled, isFalse);
      expect(plan.why, contains('Settings'));
    });

    test('no DSN wins over the switch, because it is the cheaper answer', () {
      expect(_plan(dsn: '', shareLogs: false).why, contains('no DSN'));
    });
  });

  // The release name itself is formatted by `BuildStamp.sentryRelease` and
  // pinned in `build_identity_test.dart`, where 0014 §4 keeps the one place
  // that turns a trigger into an identity. What belongs here is that the plan
  // carries the three fields and does not recompute any of them.
  group('what the build calls itself', () {
    test('release, dist and environment come off the stamp', () {
      final plan = _plan();
      expect(plan.release, 'qunleashed@0.15.0-dev+108080');
      expect(plan.dist, '108080');
      expect(plan.environment, 'dev');
    });

    test('the channel reaches the environment, not only the version', () {
      // `environment` is what a Sentry filter is actually built on, and a
      // local build arriving as `production` is the mistake worth pinning.
      expect(
        _plan(stamp: _stamp(channel: BuildChannel.local)).environment,
        'local',
      );
    });
  });

  group('the navigator observer', () {
    test('a build with no DSN carries none at all', () {
      // An app nobody is reporting from should not be watching its own
      // navigation.
      final telemetry = Telemetry(settings: DiagnosticsSettings(), dsn: '');
      expect(telemetry.configured, isFalse);
      expect(telemetry.navigatorObservers, isEmpty);
    });

    test('a configured build carries one', () {
      // This is what the previous version of this file could not assert, and
      // its absence is why the one below passed for the wrong reason: with no
      // DSN the list is `const []`, const lists are canonicalized, and
      // `same()` therefore held even with the `late final` replaced by a
      // plain getter. The mechanism the test named was removable without
      // failing it.
      final telemetry = Telemetry(
        settings: DiagnosticsSettings(),
        dsn: 'https://key@o1.ingest.de.sentry.io/2',
      );
      expect(telemetry.configured, isTrue);
      expect(telemetry.navigatorObservers, hasLength(1));
      expect(
        telemetry.navigatorObservers.single,
        isA<SentryNavigatorObserver>(),
      );
    });

    test('and builds it once, however often the list is read', () {
      // `MaterialApp` is rebuilt on every theme and locale change and reads
      // this each time. A fresh observer per accent colour would start a new
      // trace on each, which is what `late final` prevents - and with a real
      // DSN the list is not const, so `same()` now means something.
      final telemetry = Telemetry(
        settings: DiagnosticsSettings(),
        dsn: 'https://key@o1.ingest.de.sentry.io/2',
      );
      expect(telemetry.navigatorObservers, same(telemetry.navigatorObservers));
    });
  });

  group('where undelivered crashes are kept', () {
    test('the plan carries the path it was given', () {
      final plan = TelemetryPlan(
        dsn: 'https://key@o1.ingest.de.sentry.io/2',
        shareLogs: true,
        stamp: _stamp(),
        nativeDatabasePath: '/support/sentry-native',
      );
      expect(plan.nativeDatabasePath, '/support/sentry-native');
    });

    test('null is a producible state, and means the SDK default', () {
      // The fallback when `getApplicationSupportDirectory` will not answer. A
      // crash report in an awkward place beats no crash report, so this is
      // null rather than a guess at a path.
      expect(_plan().nativeDatabasePath, isNull);
    });
  });

  group('the tags 0014 §3 asks for', () {
    test('three commits when all three are known', () {
      final plan = _plan(
        stamp: _stamp(
          commit: appSha,
          flipperlibCommit: libSha,
          dartufbtCommit: ufbtSha,
        ),
      );
      expect(plan.tags, {
        'commit': appSha,
        'flipperlib': libSha,
        'dartufbt': ufbtSha,
      });
    });

    test('an unknown commit is absent rather than blank', () {
      // A tag present and empty reads, in a filter, as a build that was asked
      // and had nothing to say - which is what a broken define looks like too.
      // The submodule commits are legitimately missing outside CI.
      final plan = _plan(
        stamp: _stamp(commit: '', flipperlibCommit: libSha),
      );
      expect(plan.tags.keys, ['flipperlib']);
    });

    test('a build nothing told says nothing', () {
      final plan = _plan(stamp: _stamp(commit: ''));
      expect(plan.tags, isEmpty);
    });
  });

  group('the switch', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('is on before anything has been read', () {
      // The value a build starts with, which is the one that holds when the
      // store will not open at all.
      expect(DiagnosticsSettings().shareLogs, isTrue);
    });

    test('is on after a read of a store that has never been written', () async {
      final settings = DiagnosticsSettings();
      await settings.load();
      expect(settings.loaded, isTrue);
      expect(settings.shareLogs, isTrue);
    });

    test('reads back what was turned off', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'diagnostics.share_logs': false,
      });
      final settings = DiagnosticsSettings();
      await settings.load();
      expect(settings.shareLogs, isFalse);
    });

    test('a stored value of the wrong type leaves reporting on', () async {
      // PrefsReader's whole reason for existing: one key stored as the wrong
      // type must not decide the setting. The direction matters here - the
      // fallback is on, so a corrupt store does not silently stop reporting.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'diagnostics.share_logs': 'nope',
      });
      final settings = DiagnosticsSettings();
      await settings.load();
      expect(settings.shareLogs, isTrue);
    });

    test('turning it off notifies, and persists', () async {
      final settings = DiagnosticsSettings();
      await settings.load();
      var notified = 0;
      settings.addListener(() => notified += 1);

      await settings.setShareLogs(false);
      expect(notified, 1);
      expect(settings.shareLogs, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('diagnostics.share_logs'), isFalse);
    });

    test('setting it to what it already is notifies nobody', () async {
      // `Telemetry` reconciles from this notification, so a redundant one
      // would close and reopen the SDK on every unrelated rebuild.
      final settings = DiagnosticsSettings();
      await settings.load();
      var notified = 0;
      settings.addListener(() => notified += 1);
      await settings.setShareLogs(true);
      expect(notified, 0);
    });
  });

  group('the scrubber in front of every event', () {
    setUp(() => Scrub.debugUseHomes([r'C:\Users\Myte']));
    tearDown(() => Scrub.debugUseHomes(null));

    test('takes the account name out of an event message', () {
      final event = SentryEvent(
        message: SentryMessage(r'could not open C:\Users\Myte\dict.nfc'),
      );
      expect(
        scrubEvent(event).message?.formatted,
        r'could not open ~\<name>.nfc',
      );
    });

    test('takes it out of every exception value', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'FileSystemException',
            value: r"path = 'C:\Users\Myte\a'",
          ),
          SentryException(
            type: 'FileSystemException',
            value: r"path = 'C:\Users\Myte\b'",
          ),
        ],
      );
      expect(scrubEvent(event).exceptions?.map((e) => e.value), [
        r"path = '~\a'",
        r"path = '~\b'",
      ]);
    });

    test('takes it out of a breadcrumb message and its string data', () {
      final event = SentryEvent(
        breadcrumbs: [
          Breadcrumb(
            message: r'read C:\Users\Myte\log.txt',
            data: <String, dynamic>{
              'path': r'C:\Users\Myte\log.txt',
              'bytes': 12,
            },
          ),
        ],
      );
      final crumb = scrubEvent(event).breadcrumbs!.single;
      expect(crumb.message, r'read ~\log.txt');
      expect(crumb.data?['path'], r'~\log.txt');
      // Left alone rather than stringified: a scrubber that rewrites types is
      // a scrubber that changes what the event means.
      expect(crumb.data?['bytes'], 12);
    });

    test('an event with none of the four carriers survives untouched', () {
      final event = SentryEvent();
      expect(scrubEvent(event), same(event));
      expect(event.message, isNull);
    });

    test('nothing is dropped: the scrubber edits, it does not filter', () {
      // `beforeSend` returning null drops the event. A scrubber that did that
      // on a message it did not recognise would lose exactly the failures
      // nobody has seen before.
      final event = SentryEvent(message: SentryMessage('nothing to redact'));
      expect(scrubEvent(event), same(event));
      expect(event.message?.formatted, 'nothing to redact');
    });
  });
}
