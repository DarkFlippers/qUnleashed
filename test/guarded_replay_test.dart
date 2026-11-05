// What one `guarded()` failure becomes, and the one thing it must not be.
//
// ADR 0013 §6 turns on a fact about the SDK: `ReplayEventProcessor` keys on an
// event with a non-empty `exceptions` list. It flushes the replay buffer on
// both platforms, and on iOS it also converts the session to a recorded one,
// so the rest of the run keeps uploading. `_reportGuarded` is wired against
// every `guarded()` call site in the app, so while it sent an exception event,
// every handled and recovered-from failure uploaded a replay - against §8's
// `sessionSampleRate: 0`, and against what `diagnosticsReplaySubtitle` tells
// the user. #332 silenced the loudest call site; #333 is the mechanism.
//
// Nothing in CI could see it, which is why this file is behavioural rather
// than a count: the symptom was replay quota in the Sentry console.
// `capture_exception_budget_test.dart` holds the static half, and the two
// cover different things - the count cannot see a `SentryEvent(throwable:)`
// that the budget still reads as one site, and no count can see the shape of
// what the sink produces.
//
// Through a real hub with its transport replaced, for the reason
// `sentry_capture.dart` gives - a fake in front of `Telemetry` would assert
// that this file's own arithmetic is right rather than that anything reaches
// Sentry in the shape the processors read.
//
// What the assertions have to cover, because the fix moves an event between
// two shapes rather than adding one: no `exceptions` list (the replay), the
// failing frames still there and *said to be* the failing ones (what
// `captureMessage` would have cost), and the grouping, level, context and
// scrub unchanged (what a reader of the issue list would notice).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/guarded.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/telemetry/scrub.dart';
import 'package:qunleashed/services/telemetry/scrub_event.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kept_lines.dart';
import 'quiet_log.dart';
import 'sentry_capture.dart';
import 'telemetry_sinks.dart';

/// An error that cannot be described, which is a shape the app has met.
class _Hostile implements Exception {
  @override
  String toString() => throw StateError('no');
}

const String _label = '[Archive] syncing the category';

/// Throws [error] from a frame with a name of its own.
///
/// Which is load-bearing, not decoration: `attachStacktrace` is on by default,
/// so an event with *no* stack handed to it still arrives carrying frames -
/// the ones where it was reported. Asserting that frames exist therefore
/// cannot tell the failure's stack from the reporter's, and a `captureMessage`
/// would pass it. This name can only appear in the former.
Future<void> throwFromANamedFrame(Object error) async => throw error;

/// Fails the way most of flipperlib fails: a rejection with no stack.
///
/// `guarded._record` documents this as the common shape - a bare
/// `completeError(error)` yields `StackTrace.empty` - and it is the case where
/// the frames in the event are *not* the failure's, because the SDK
/// substitutes the reporting site's own.
Future<void> rejectWithoutAStack(Object error) {
  final completer = Completer<void>();
  // Explicitly empty, not merely omitted: a bare `completeError` hands the
  // async machinery a stack of its own on this runtime, so omitting it tests
  // the opposite of what it looks like.
  completer.completeError(error, StackTrace.empty);
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(resetTelemetrySinks);

  /// Drives one real failure through `guarded` and returns what Sentry got.
  ///
  /// Through `guarded` itself and not by calling the sink: the wiring from a
  /// dropped future to an event is the thing under test, and `guarded` is also
  /// what supplies the verb.
  Future<SentryEvent> reported(
    Object error, {
    String what = _label,
    Future<void> Function(Object error) by = throwFromANamedFrame,
  }) async {
    final seen = await wiredHub();
    await quietlyAsync(() => guarded(what, () => by(error)));
    await settleAndClose(seen, until: () => seen.events.isNotEmpty);
    return seen.events.single;
  }

  /// The frames of every thread on [event], flattened.
  List<String?> framesOf(SentryEvent event) => [
    for (final thread in event.threads ?? const <SentryThread>[])
      ...?thread.stacktrace?.frames.map((frame) => frame.function),
  ];

  Map<String, dynamic> guardedContextOf(SentryEvent event) =>
      event.contexts['guarded'] as Map<String, dynamic>;

  group('a handled failure', () {
    test('carries no exceptions list, so no replay is uploaded', () async {
      final event = await reported(TimeoutException('too slow'));

      // The assertion the whole change exists for. `ReplayEventProcessor`
      // reads exactly this, and reads it before `beforeSend`, so nothing
      // downstream of here can take the upload back.
      expect(
        event.exceptions ?? const [],
        isEmpty,
        reason: 'an exceptions list is what flushes the replay buffer',
      );
    });

    test('keeps the failing stack, carried as a thread', () async {
      // What `captureMessage` would have cost, and the reason the fix is
      // `captureEvent` with a `stackTrace`: with no exception to hang them on
      // the SDK parses the frames into a thread, and `SentryEvent.stacktrace`
      // falls back to that thread - which is the field the debug-image
      // processor reads, so an obfuscated release still symbolicates.
      final event = await reported(TimeoutException('too slow'));

      // Named frame and not `isNotEmpty`: see [throwFromANamedFrame]. A
      // message event with no stack handed over still arrives with frames, so
      // the only assertion that distinguishes the two is whose stack it is.
      expect(
        framesOf(event),
        contains('throwFromANamedFrame'),
        reason: 'the stack of the failure, not of the line that reported it',
      );
      expect(guardedContextOf(event)['stack'], 'caught');
    });

    test('says so when the frames are the reporter own', () async {
      // The case `guarded._record` calls the common one: a bare
      // `completeError` yields `StackTrace.empty`, `attachStacktrace`
      // substitutes the reporting site's stack, and a thread carries no
      // `snapshot` flag to mark the substitution the way the exception path
      // did. So the event has to say it, or triage chases `telemetry.dart`.
      final event = await reported(
        TimeoutException('too slow'),
        by: rejectWithoutAStack,
      );

      expect(
        framesOf(event),
        isNot(contains('rejectWithoutAStack')),
        reason: 'the failure carried no stack, so these frames are not its',
      );
      expect(guardedContextOf(event)['stack'], 'reporter');
    });

    test(
      'keeps its grouping and level, and the header fields with it',
      () async {
        final event = await reported(TimeoutException('too slow'));

        // Read off the object rather than off the message, which is what lets
        // the type survive the exception leaving the envelope. Without the
        // explicit fingerprint every one of these shares `guarded`'s own
        // `catchError` stack, so one issue would hold every dropped future in
        // the app.
        expect(event.fingerprint, [_label, 'TimeoutException']);
        expect(event.level, SentryLevel.error);
        final context = guardedContextOf(event);
        expect(context['what'], _label);
        expect(context['verb'], 'failed');
        expect(
          context['type'],
          'TimeoutException',
          reason: 'the two fields the issue header used to carry for free',
        );
        expect(context['error'], contains('too slow'));
      },
    );

    test('is titled with the sentence the log already wrote', () async {
      // `guarded._record` writes `'$what $verb: $error'` to `LogService`, and
      // the message is the same sentence - so the issue title and the log line
      // a user can open read alike, modulo the scrub. It is also where the
      // exception's value went when it left the header.
      final event = await reported(TimeoutException('too slow'));

      expect(event.message?.formatted, startsWith('$_label failed:'));
      expect(event.message?.formatted, contains('too slow'));
    });
  });

  group('what reaches the title', () {
    setUp(() => Scrub.debugUseHomes([r'C:\Users\Myte']));
    tearDown(() => Scrub.debugUseHomes(null));

    test('has the account name taken out of it, once', () async {
      // The message is deliberately *not* scrubbed in `_reportGuarded`:
      // `beforeSend` scrubs a message, and this hub replaces `beforeSend` with
      // its recorder, so the production layer is applied here by hand. Doing
      // both in production double-applied the query rule, whose replacement is
      // not a fixed point - `?<query><query>` reached a title that way.
      final event = await reported(
        StateError(
          r"dir = 'C:\Users\Myte\cache', "
          'GET https://catalog.example/v1/app?token=abc failed',
        ),
        what: r'[Archive] reading C:\Users\Myte\cache',
      );

      final title = scrubEvent(event).message?.formatted;
      expect(title, isNotNull);
      expect(title, isNot(contains('Myte')));
      expect(title, contains('~'));
      expect(title, isNot(contains('token=abc')));
      // The measurable half of "once". `Scrub`'s query rule replaces the query
      // with a marker that its own tail class excludes, so a second pass over
      // the same string appends another one: a message scrubbed here as well
      // as in `beforeSend` arrived as `?<query><query>`.
      expect(
        '<query>'.allMatches(title!).length,
        1,
        reason: 'scrubbed once, by beforeSend, and not again before it',
      );
      // And the premise, pinned: a second pass is not a no-op. That is the
      // whole reason the message is left to `beforeSend` instead of being
      // scrubbed where it is built, so if `Scrub` ever becomes a fixed point
      // this fails and whoever made it so gets to re-read that decision.
      expect(Scrub.outbound(title), isNot(title));

      // And the two fields `scrubEvent` does not walk, which is why
      // `_reportGuarded` scrubs them itself.
      expect(event.fingerprint?.first, isNot(contains('Myte')));
      expect(guardedContextOf(event)['error'], isNot(contains('Myte')));
    });

    test('costs one filed issue when the error cannot be described', () async {
      // `guarded` documents an object whose `toString()` throws as real, and
      // the strings are built inside `_guard` for that reason. The line
      // `guarded._record` wrote is unaffected, so the failure still reaches
      // Sentry Logs; what is lost is this issue.
      final seen = await wiredHub();
      // After the hub, which installs telemetry's own kept sink over this one.
      recordKeptLines();

      await quietlyAsync(
        () => guarded(_label, () => throwFromANamedFrame(_Hostile())),
      );
      // No `until`: nothing is meant to arrive, and the quiet window is what
      // makes the absence worth asserting.
      await settleAndClose(seen);

      expect(seen.events, isEmpty, reason: 'no issue, by design');
      // *Which* guard caught it, which is the part a placement change moves.
      // Built inside `_guard`, the throw is telemetry's own failure and says
      // so at `error`; built outside, it escapes `_reportGuarded` into
      // `guarded`'s catch around the sink call, which logs that a sink threw -
      // one layer too far out to name what was not captured. Asserted by
      // which body arrived and not by how many, because `LogService` folds a
      // consecutive identical one and a count cannot tell once from twice.
      final notCaptured = keptLines.where(
        (l) => l.contains('was not captured'),
      );
      expect(notCaptured, isNotEmpty);
      expect(keptLevels[keptLines.indexOf(notCaptured.first)], KeptLevel.error);
      expect(
        keptLines.where((l) => l.contains('the guarded sink threw')),
        isEmpty,
        reason: 'reporting must not throw into the sink that called it',
      );
    });
  });
}
