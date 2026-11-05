// The catch that keeps a topic failure off the replay, and the line it leaves.
//
// `PushService.applyTopics` is a seam for the same reason `awaitApnsToken` is:
// `_applyOnce` reaches `FirebaseMessaging.instance` and is gated behind
// `isSupported`, which reads `dart:io`'s `Platform`. That is false on every
// test host and has no override, so nothing above this function can be driven
// from a test whatever is faked below it.
//
// What is worth pinning is not the loop's arithmetic but what it suppresses.
// A rejection here reached `guarded('[Bootstrap] ambient service "push
// notifications"', ...)` on the launch path and the zone on the Settings
// path, and either way became a `Sentry.captureException` - an event with an
// `exceptions` list, which is what makes the iOS SDK flush the replay buffer
// and keep uploading for the rest of the session. ADR 0013 §8, Sentry
// QUNLEASHED-2.
//
// Asserted on the body rather than the count, per CLAUDE.md: `LogService`
// folds a *consecutive* identical body, so `hasLength(1)` cannot tell "said
// once" from "said twice" - and each case below uses a distinct `code` so the
// fold cannot swallow the second test's line either.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/notifications/push_service.dart';

import 'kept_lines.dart';

/// The two calls `applyTopics` makes, recorded, and optionally throwing.
///
/// One class rather than a record of closures over a second class: the knobs
/// and the recording belong to the same fake, and `subscribe`/`unsubscribe`
/// are handed over as tear-offs. [visited] is one list in call order, which
/// is what the partial-apply case is actually about - two lists concatenated
/// by direction read as order only while every call happens to be an
/// unsubscribe.
class _Topics {
  _Topics({this.failOn, this.code = 'unavailable', this.message});

  /// The topic whose call throws, or null for a run that goes through.
  final String? failOn;
  final String code;
  final String? message;

  final List<String> subscribed = <String>[];
  final List<String> unsubscribed = <String>[];
  final List<String> visited = <String>[];

  Future<void> subscribe(String topic) => _act(subscribed, topic);
  Future<void> unsubscribe(String topic) => _act(unsubscribed, topic);

  Future<void> _act(List<String> log, String topic) async {
    if (topic == failOn) {
      throw FirebaseException(
        plugin: 'messaging',
        code: code,
        message: message,
      );
    }
    log.add(topic);
    visited.add(topic);
  }
}

void main() {
  setUp(recordKeptLines);

  test(
    'applies every topic and says nothing when they all go through',
    () async {
      final topics = _Topics();

      await PushService.applyTopics(
        {PushTopics.appRelease, PushTopics.unlRelease},
        topics.subscribe,
        topics.unsubscribe,
      );

      expect(topics.subscribed, [PushTopics.appRelease, PushTopics.unlRelease]);
      expect(topics.visited, hasLength(PushTopics.all.length));
      // The quiet path is quiet: a line here would be commentary at a level
      // that is kept in every build.
      expect(keptLines, isEmpty);
    },
  );

  test(
    'a failed topic call does not reject, so no exception event is made',
    () async {
      final topics = _Topics(failOn: PushTopics.unlRelease);

      // The whole regression. Before the catch this threw, `start()` rejected,
      // and `guarded` turned it into a `captureException`.
      await expectLater(
        PushService.applyTopics(const {}, topics.subscribe, topics.unsubscribe),
        completes,
      );
    },
  );

  test('the line names where it stopped and how much got through', () async {
    // `ofwRelease` is fourth in `PushTopics.all`, so three changes precede it.
    final topics = _Topics(
      failOn: PushTopics.ofwRelease,
      message: 'The Internet connection appears to be offline.',
    );

    await PushService.applyTopics(
      const {},
      topics.subscribe,
      topics.unsubscribe,
    );

    // Not "topics left unchanged", which is what this said first and is false
    // for every case but a failure on the first topic: three went through.
    expect(keptLines, hasLength(1));
    expect(
      keptLines.single,
      allOf(
        contains('3 of ${PushTopics.all.length}'),
        contains(PushTopics.ofwRelease),
        contains('unavailable'),
        // `convertPlatformException` defaults `code` to `unknown` when the
        // native error carries nothing it maps, so the message is the half
        // that can still explain the failure.
        contains('The Internet connection appears to be offline.'),
      ),
    );
  });

  test('the failure is kept at warning, not at caught', () async {
    // The level does not decide whether a replay is uploaded - all three
    // `KeptLevel`s become Sentry Logs, and a log carries no `exceptions`. It
    // decides who looks: `_apnsReady` has already taken out every cause
    // QUNLEASHED-2 named, so what reaches here is unexplained.
    final topics = _Topics(
      failOn: PushTopics.appRelease,
      code: 'internal-error',
    );

    await PushService.applyTopics(
      const {},
      topics.subscribe,
      topics.unsubscribe,
    );

    expect(keptLevels, [KeptLevel.warning]);
  });

  test('the topics after the failure are left for the next launch', () async {
    final topics = _Topics(failOn: PushTopics.appDev);

    await PushService.applyTopics(
      const {},
      topics.subscribe,
      topics.unsubscribe,
    );

    // `appRelease` only, and in call order: the loop stops where it threw,
    // which is what the recorded line has to say and what the next launch has
    // to repair.
    expect(topics.visited, [PushTopics.appRelease]);
  });
}
