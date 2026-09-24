// A fire-and-forget failure has no second surface: no caller to return to, no
// UI path. So these are all about the one place it can land, and about the
// contract the four queues chain on - that the future comes back settled and
// never rejecting.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/guarded.dart';
import 'package:qunleashed/services/logging.dart';

/// A rejection shaped like the ones flipperlib produces.
///
/// It completes through a bare `completeError(error)` in almost every case, and
/// in the root zone the app runs in that yields `StackTrace.empty`.
///
/// The empty stack is passed explicitly because flutter_test does not run in
/// the root zone: its zone intercepts a rejection that arrives without a stack
/// and attaches the current one. A bare `Future.error` here would therefore
/// test the opposite of the shipped case - measured, not assumed.
Future<void> boom() => Future<void>.error(StateError('boom'), StackTrace.empty);

void main() {
  late DebugPrintCallback realPrint;

  setUp(() {
    LogService.clearHistory();
    // Silenced rather than captured: every test here records at error level,
    // which prints a full stack in the talking build. Restored in tearDown
    // because debugPrint is a debug variable and leaving it swapped leaks into
    // the next file - and because debugPrintThrottled leaves a pending Timer,
    // which a plain test() has no binding to drain.
    realPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
  });

  tearDown(() {
    debugPrint = realPrint;
    LogService.clearHistory();
  });

  test('a rejection is kept at error level, and does not reject the caller', () async {
    var chained = false;
    await guarded('[Test] work', boom).then((_) => chained = true);

    // Not decoration: the queues chain on this future, and `then` on a
    // rejected future skips its callback and propagates - so a helper that let
    // the rejection through would strand everything queued behind one failed
    // link.
    expect(chained, isTrue);

    // The level, not just the fact of a record. warn is kept too, so asserting
    // only on history cannot tell error from warn - and the prefix is the only
    // thing in the entry that can.
    expect(LogService.history.single, contains('[error]'));
    expect(
      LogService.history.single,
      contains('[Test] work failed: Bad state: boom'),
    );
  });

  test(
    'the returned future waits for the task, not just for its first turn',
    () async {
      // The property every call site actually depends on. Without it the
      // foreground service's start and the stop queued behind it run at once,
      // and the network responder prunes a chain that is still running.
      final gate = Completer<void>();
      var done = false;
      final result = guarded('[Test] slow', () async {
        await gate.future;
        throw StateError('boom');
      });
      unawaited(result.whenComplete(() => done = true));

      for (var turn = 0; turn < 5; turn++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(done, isFalse, reason: 'completed before the task settled');
      expect(LogService.history, isEmpty);

      gate.complete();
      await result;

      expect(done, isTrue);
      expect(LogService.history.single, contains('[Test] slow failed'));
    },
  );

  test(
    'a synchronous throw is kept too, not left to escape the call',
    () async {
      // The case that shaped the helper. FlipperClient.writeCliBytes is not
      // async, so a session that is already gone throws before there is a
      // future to attach a handler to. Without the Future.sync inside guarded,
      // this throw leaves the guarded() call itself, before anything can be
      // awaited.
      Future<void> gone() => throw StateError('thrown before any future');

      await expectLater(guarded('[Test] sync', gone), completes);
      expect(LogService.history.single, contains('thrown before any future'));
    },
  );

  test('the stack goes in when the failure carries one', () async {
    await guarded('[Test] stack', () async => throw StateError('boom'));

    // For a future nobody awaited the stack is the only thing that says where
    // it came from, and history keeps one entry per message rather than per
    // line, so it stays a single event.
    final kept = LogService.history.single;
    expect(kept, contains('guarded_test.dart'));
    expect(kept.split('\n').length, greaterThan(1));
  });

  test('a failure carrying no stack does not end in a blank line', () async {
    // Not the exotic case: this is what a bare completeError produces, which
    // is how most of flipperlib rejects. Appending the stack unconditionally
    // ended every such entry with a trailing newline and nothing after it.
    await guarded('[Test] nostack', boom);

    expect(LogService.history.single, endsWith('Bad state: boom'));
  });

  test('a task that succeeds keeps nothing and reports nothing', () async {
    var notified = false;
    await guarded(
      '[Test] fine',
      () async {},
      onFailure: (_) => notified = true,
    );

    expect(LogService.history, isEmpty);
    expect(notified, isFalse);
  });

  test('onFailure is told the error, after the log already has it', () async {
    Object? seen;
    var keptWhenCalled = 0;
    await guarded(
      '[Test] notify',
      boom,
      onFailure: (error) {
        seen = error;
        keptWhenCalled = LogService.history.length;
      },
    );

    expect(seen, isA<StateError>());
    // Recorded first, so a site whose UI has gone away cannot cost the only
    // record of what happened.
    expect(keptWhenCalled, 1);
  });

  test('a failing onFailure is kept too, and still does not reject', () async {
    await expectLater(
      guarded(
        '[Test] notify',
        boom,
        onFailure: (_) => throw StateError('the UI went away'),
      ),
      completes,
    );

    expect(LogService.history, hasLength(2));
    expect(
      LogService.history.first,
      contains('[Test] notify failed: Bad state: boom'),
    );
    expect(
      LogService.history.last,
      contains('[Test] notify failure handler threw'),
    );
  });

  test('an error whose toString() throws is recorded, and does not reject', () async {
    // Building the message is the one part of the handler that touches the
    // error, and it runs before anything guards it. A throw there would reject
    // the future the queues are promised cannot reject - poisoning the chain,
    // and losing the message that would have explained it.
    await expectLater(
      guarded('[Test] nasty', () => Future<void>.error(_ExplodingOnToString())),
      completes,
    );

    expect(
      LogService.history.single,
      contains('[Test] nasty failed: an error whose toString() threw'),
    );
  });

  test(
    'the same failure repeated coalesces rather than filling the buffer',
    () async {
      for (var attempt = 0; attempt < 3; attempt++) {
        await guarded('[Test] repeat', boom);
      }

      // history holds 500 entries and is the only record of the failure that
      // explains an episode. A wedged queue failing identically every tick must
      // not evict it - which needs guarded's message to be stable across
      // repeats, so putting an attempt counter or a timestamp in `what` would
      // quietly undo _remember's coalescing.
      expect(LogService.history, hasLength(1));
      expect(LogService.history.single, contains('(3×)'));
    },
  );
}

/// An exception whose own toString() fails, which is the case that would
/// otherwise take the recording down with it.
class _ExplodingOnToString {
  @override
  String toString() => throw StateError('even saying what I am fails');
}
