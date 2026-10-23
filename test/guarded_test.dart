// A fire-and-forget failure has no second surface: no caller to return to, no
// UI path. So these are all about the one place it can land, and about the
// contract the four queues chain on - that the future comes back settled and
// never rejecting.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/guarded.dart';

import 'kept_lines.dart';

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
  setUp(recordKeptLines);

  late DebugPrintCallback realPrint;

  setUp(() {
    clearKeptLines();
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
    clearKeptLines();
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
    expect(keptLines.single, contains('[error]'));
    expect(keptLines.single, contains('[Test] work failed: Bad state: boom'));
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
      expect(keptLines, isEmpty);

      gate.complete();
      await result;

      expect(done, isTrue);
      expect(keptLines.single, contains('[Test] slow failed'));
    },
  );

  test(
    'a synchronous throw is kept too, not left to escape the call',
    () async {
      // The case that shaped the helper. FlipperClient.writeCliBytes is not
      // async, so a session that is already gone throws before there is a
      // future to attach a handler to. [guarded] is `async` now, so it can
      // never throw out of the call itself - what this pins is that `task()`
      // runs inside the `try`, so the throw is recorded and swallowed rather
      // than rejecting the future the queues chain on.
      Future<void> gone() => throw StateError('thrown before any future');

      await expectLater(guarded('[Test] sync', gone), completes);
      expect(keptLines.single, contains('thrown before any future'));
    },
  );

  test('the stack goes in when the failure carries one', () async {
    await guarded('[Test] stack', () async => throw StateError('boom'));

    // For a future nobody awaited the stack is the only thing that says where
    // it came from, and history keeps one entry per message rather than per
    // line, so it stays a single event.
    final kept = keptLines.single;
    expect(kept, contains('guarded_test.dart'));
    expect(kept.split('\n').length, greaterThan(1));
  });

  test('a failure carrying no stack does not end in a blank line', () async {
    // Not the exotic case: this is what a bare completeError produces, which
    // is how most of flipperlib rejects. Appending the stack unconditionally
    // ended every such entry with a trailing newline and nothing after it.
    await guarded('[Test] nostack', boom);

    expect(keptLines.single, endsWith('Bad state: boom'));
  });

  test('a task that succeeds keeps nothing and reports nothing', () async {
    var notified = false;
    await guarded(
      '[Test] fine',
      () async {},
      onFailure: (_) => notified = true,
    );

    expect(keptLines, isEmpty);
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
        keptWhenCalled = keptLines.length;
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

    expect(keptLines, hasLength(2));
    expect(keptLines.first, contains('[Test] notify failed: Bad state: boom'));
    expect(keptLines.last, contains('[Test] notify failure handler threw'));
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
      keptLines.single,
      contains(
        '[Test] nasty failed: a _ExplodingOnToString whose toString() threw',
      ),
    );
  });

  test('the same failure repeated is sent once', () async {
    for (var attempt = 0; attempt < 3; attempt++) {
      await guarded('[Test] repeat', boom);
    }

    // A queue wedged against a device that has gone fails identically every
    // tick, for as long as it is wedged. The reader at the other end has no
    // coalescing of its own, so the fold is the only thing between one dead
    // device and an unbounded stream of identical events - which needs
    // guarded's message to be stable across repeats, so putting an attempt
    // counter or a timestamp in `what` would quietly undo it.
    //
    // The buffer rendered the repeats as a `(3×)` suffix and this asserted
    // on that too. Nothing renders them now: they are dropped where the fold
    // sees them and how many there were is not recoverable.
    expect(keptLines, hasLength(1));
    expect(keptLines.single, isNot(contains('×')));
  });

  // The shape QUNLEASHED-A arrived in, and the one every other case here
  // missed: a task that returns something.
  //
  // `task` is declared `Future<void> Function()` and `void` is a top type, so
  // a `Future<GpsReadiness> Function()` satisfies it statically - which is how
  // `bootstrap.dart` hands `GeolocatorGpsProvider.ensureReady` to this on
  // desktop. The old body was `Future.sync(task).catchError(...)`, and
  // `Future.sync` returns the caller's own future untouched when
  // `result is Future<T>`, so `catchError` met a future whose real type
  // argument was the task's and a handler that returns nothing. It logged,
  // then rejected with `ArgumentError`.
  //
  // Every case above hands back a `Future<void>`, so none of them could see
  // it.
  //
  // One of the three below is the regression test, and it is worth saying
  // which: only `still does not reject the caller` fails against the old
  // body, with the production message. The other two pass against it and are
  // controls, not evidence - the succeeding task never reaches `catchError`,
  // and `Future.sync` *caught* a synchronous throw and built a fresh
  // `Future<void>` from it, so the caller's `Future<int>` never existed and
  // there was no mismatched type argument to trip over. They are kept because
  // they pin the two properties a later rewrite could lose.
  group('a task that returns a value', () {
    Future<int> boomInt() =>
        Future<int>.error(StateError('boom'), StackTrace.empty);

    // Declared `Future<dynamic> Function()` on purpose: type it
    // `Future<void> Function()` and the map erases every argument back to the
    // shape the bug needed, so the matrix would pin nothing.
    final rejecting = <String, Future<dynamic> Function()>{
      'Future<void>': () => Future<void>.error(StateError('boom')),
      'Future<int>': () => Future<int>.error(StateError('boom')),
      'Future<bool>': () => Future<bool>.error(StateError('boom')),
      'Future<String>': () => Future<String>.error(StateError('boom')),
      // The two that never tripped it, kept so the asymmetry is written down
      // rather than rediscovered: the handler returned `null`, which
      // satisfies `FutureOr<int?>` and not `FutureOr<int>`.
      'Future<int?>': () => Future<int?>.error(StateError('boom')),
      'Future<Object?>': () => Future<Object?>.error(StateError('boom')),
    };
    for (final entry in rejecting.entries) {
      test('${entry.key} does not reject the caller', () async {
        var chained = false;
        await guarded(
          '[Test] ${entry.key}',
          entry.value,
        ).then((_) => chained = true);

        expect(
          chained,
          isTrue,
          reason: 'the queues chain on this, whatever the task returned',
        );
        expect(keptLines.single, contains('[error]'));
        expect(keptLines.single, contains('failed: Bad state: boom'));
      });
    }

    // The shape that actually shipped. `bootstrap._start` declared
    // `Future<void> Function()`, so the type argument was erased one frame
    // above `guarded` and `T` inferred `void` while the object underneath was
    // a `Future<GpsReadiness>`. The generic signature alone would not have
    // caught this; the `try`/`await` does.
    test('including one erased to Future<void> by a wrapper', () async {
      final Future<void> Function() erased = boomInt;
      var chained = false;

      await guarded('[Test] erased', erased).then((_) => chained = true);

      expect(chained, isTrue);
      expect(keptLines.single, contains('[Test] erased failed'));
    });

    // The old bug fired *after* `onFailure` had already run, so a refactor
    // that moved that call for non-void tasks would go unnoticed otherwise.
    test('and still tells onFailure first', () async {
      final seen = <Object>[];

      await guarded('[Test] work', boomInt, onFailure: seen.add);

      expect(seen.single, isA<StateError>());
      expect(keptLines.single, contains('[Test] work failed'));
    });

    test('and one that succeeds still keeps nothing', () async {
      var chained = false;
      await guarded('[Test] work', () async => 7).then((_) => chained = true);

      expect(chained, isTrue);
      expect(keptLines, isEmpty);
    });

    // The property `Future.sync` used to provide, kept across the rewrite: a
    // callee that is not `async` and throws before there is a future at all
    // still lands with the rejections rather than escaping to the caller,
    // because `task()` runs inside the `try`. A control rather than a
    // regression test - the old body passed this too.
    test('and a synchronous throw is caught in the same place', () async {
      var chained = false;
      Future<int> throwsBeforeAnyFuture() => throw StateError('boom');

      await guarded(
        '[Test] work',
        throwsBeforeAnyFuture,
      ).then((_) => chained = true);

      expect(chained, isTrue);
      expect(keptLines.single, contains('[Test] work failed: Bad state: boom'));
    });
  });

  group('the second reader', () {
    tearDown(() => guardedFailureSink = null);

    test('is optional: with none installed nothing changes', () async {
      guardedFailureSink = null;
      await guarded('[Test] no sink', boom);
      expect(keptLines, hasLength(1));
    });

    test('is handed the error object, not the formatted line', () async {
      // A crash reporter groups on the exception. Handing it the string would
      // make every failure in the app one issue with a different title.
      final sink = _RecordingSink();
      guardedFailureSink = sink.call;

      await guarded('[Test] sunk', boom);

      expect(sink.calls, ['[Test] sunk failed']);
      expect(sink.errors.single, isA<StateError>());
    });

    test('hears about a failure handler that threw, separately', () async {
      final sink = _RecordingSink();
      guardedFailureSink = sink.call;

      await guarded(
        '[Test] sunk',
        boom,
        onFailure: (_) => throw StateError('and the handler too'),
      );

      expect(sink.calls, [
        '[Test] sunk failed',
        '[Test] sunk failure handler threw',
      ]);
    });

    test('a sink that throws costs neither the log nor the contract', () async {
      // The whole reason the call is in a `try` of its own. A reporter that
      // breaks must not strand the queue chaining on this future, and must not
      // take the local record - the surface somebody can actually open - with
      // it.
      guardedFailureSink = (_, _, _, _) => throw StateError('sink is broken');

      await expectLater(guarded('[Test] sunk', boom), completes);

      expect(
        keptLines.where((e) => e.contains('[Test] sunk failed')),
        hasLength(1),
        reason: 'the log line is written before the sink runs',
      );
      expect(
        keptLines.where((e) => e.contains('the guarded sink threw')),
        hasLength(1),
        reason: 'and the broken sink is itself reported',
      );
    });
  });
}

/// The second reader, recorded instead of sent.
///
/// `Telemetry` installs one of these when reporting is on. What matters here
/// is the contract [guarded] offers it, which is the same never-rejects
/// contract the queues depend on - so these cover what happens when the sink
/// is absent, when it is present, and when it is the thing that breaks.
class _RecordingSink {
  final List<String> calls = [];
  final List<Object> errors = [];

  void call(String what, String verb, Object error, StackTrace stack) {
    calls.add('$what $verb');
    errors.add(error);
  }
}

/// An exception whose own toString() fails, which is the case that would
/// otherwise take the recording down with it.
class _ExplodingOnToString {
  @override
  String toString() => throw StateError('even saying what I am fails');
}
