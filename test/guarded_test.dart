// The helper exists because a fire-and-forget failure has no second surface:
// no caller to return to, no UI path. So these tests are all about the one
// place it can land. CI runs this file twice for the same reason it runs
// logging_history_test twice - four of the implementations this replaces
// logged at info, and info is compiled out of a build that prints nothing,
// which is the build people run.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/guarded.dart';
import 'package:qunleashed/services/logging.dart';

void main() {
  setUp(LogService.clearHistory);
  tearDown(LogService.clearHistory);

  test(
    'a rejection is kept, and the future it came from does not reject',
    () async {
      var chained = false;
      await guarded(
        '[Test] work',
        () => Future<void>.error(StateError('boom')),
      ).then((_) => chained = true);

      // Not decoration: every call site chains on this future, and `then` on a
      // rejected future skips its callback and propagates - so a helper that
      // let the rejection through would strand everything queued behind one
      // failed link.
      expect(chained, isTrue);
      expect(
        LogService.history.single,
        contains('[Test] work failed: Bad state: boom'),
      );
    },
  );

  test('a synchronous throw is kept too, not left to escape the call', () async {
    // The case that shaped the helper. FlipperClient.writeCliBytes is not
    // async, so a session that is already gone throws before there is a
    // future to attach a handler to. Without the Future.sync inside guarded,
    // this throw leaves the guarded() call itself, before anything can be
    // awaited.
    Future<void> gone() => throw StateError('thrown before any future');

    await expectLater(guarded('[Test] sync', gone), completes);
    expect(LogService.history.single, contains('thrown before any future'));
  });

  test('the stack goes in with the message', () async {
    await guarded('[Test] stack', () async => throw StateError('boom'));

    // For a future nobody awaited the stack is the only thing that says where
    // it came from, and history keeps one entry per message rather than per
    // line, so it stays a single event.
    final kept = LogService.history.single;
    expect(kept, contains('guarded_test.dart'));
    expect(kept.split('\n').length, greaterThan(1));
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
      () => Future<void>.error(StateError('boom')),
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
        () => Future<void>.error(StateError('boom')),
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

  // As in logging_history_test: the second CI run is the only one that can see
  // the property this is all about, and without this it would silently become
  // a copy of the first if the define ever stopped reaching the build.
  test('the build under test is the one the run asked for', () {
    const expectsQuiet = bool.fromEnvironment('QLOG_EXPECT_QUIET');

    expect(LogService.printing, !expectsQuiet);
  });
}
