// Which lines `LogService` keeps, and from where — #89 and ADR 0013 §5.
//
// This was `logging_history_test.dart`, over a 500-entry buffer in memory.
// ADR 0013 §1's amendment removed the buffer: a kept line is forwarded to
// `keptSink` and nothing holds it, so what is left to test is which calls
// become kept lines at all - the three levels, the flipperlib bridge, and the
// four failure paths nobody wrote a handler for.
//
// `kept_sink_test.dart` is the other half, over the contract the sink is
// offered. This file installs the recorder from `kept_lines.dart` and reads
// what came through it.
import 'dart:ui';

import 'package:flipperlib/flipperlib.dart' show FlipperLogLevel, Log;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/logging.dart';

import 'kept_lines.dart';

import 'quiet_log.dart';

void main() {
  setUp(recordKeptLines);

  // The whole point of #89. LogService.enabled is a const that follows the
  // build type, and every guard derived from it folds — so in a shipped build
  // the error branch was shaken out and every error site, most of them in
  // catch blocks, reported nowhere at all.
  //
  // Both halves are asserted together on purpose: printing still follows the
  // build, and keeping no longer does. In the default run errorOn is true and
  // this reads as "printed and kept"; under --dart-define=QLOG=false it reads
  // as "kept though nothing printed", which is the case that was broken. CI
  // runs this file both ways.
  // A rejection carries a stack only when its error is an Error, so the
  // two branches are the PlatformException case and the TypeError case -
  // and the check has to be on content, because a zone can hand over an
  // empty trace that is not the StackTrace.empty const. `flutter test` runs
  // inside one that hands over a chained trace, which is why the identity
  // form would be right here and wrong in the app.
  group('describe', () {
    test('an error with no stack is just the error', () {
      expect(LogService.describe('boom', StackTrace.empty), 'boom');
    });

    test('an error with a stack carries it', () {
      expect(
        LogService.describe('boom', StackTrace.fromString('#0 frame')),
        'boom\n#0 frame',
      );
    });

    test('an empty stack that is not the const is still no stack', () {
      expect(LogService.describe('boom', StackTrace.fromString('')), 'boom');
    });
  });

  test('an error is kept whether or not the build prints anything', () {
    final lines = printed(() => LogService.error('a transport fault'));

    expect(keptLines.single, contains('a transport fault'));
    expect(
      lines.isEmpty,
      !LogService.errorOn,
      reason: 'printing follows the build; keeping does not',
    );
  });

  test('a warning is kept too', () {
    printed(() => LogService.warn('the port went quiet'));

    expect(keptLines.single, contains('the port went quiet'));
  });

  // The level ADR 0013 adds, and the whole of what makes it worth adding:
  // it is kept in a build that prints nothing, which is every release build,
  // where the info it replaces at a call site would not have been there at
  // all. A test that only checked the prefix would pass on `info` too.
  test('a caught failure is kept in a build that prints nothing', () {
    final lines = printed(() => LogService.caught('[Known] save failed'));

    expect(keptLines.single, contains('[caught] [Known] save failed'));
    expect(
      lines.isEmpty,
      !LogService.infoOn,
      reason: 'printing follows the build, at info; keeping does not',
    );
  });

  // The prefix is load-bearing rather than decoration: ADR 0013 reads it to
  // send these as a Sentry log at info rather than warning, so they are
  // searchable without firing the alerting warn is for. A reader of the log
  // screen needs the same distinction for the same reason.
  test('a caught failure is not dressed as a warning', () {
    printed(() => LogService.caught('the rename did not take'));

    expect(keptLines.single, isNot(contains('[warning]')));
    expect(keptLines.single, isNot(contains('[error]')));
  });

  // Anything below a warning runs often enough to churn the buffer, which
  // would cost the failure the context the buffer exists to hold.
  test('the chatty levels are not kept', () {
    printed(() {
      LogService.info('opened the archive');
      LogService.debug('frame');
      LogService.trace('byte');
    });

    expect(keptLines, isEmpty);
  });

  // One send, not one per frame. Thirteen of the app's error sites pass
  // '$e\n$st' and a Dart stack trace runs to thirty frames or so, so a reader
  // told about each line would get thirty Sentry logs for one failure, with
  // the message that explains it indistinguishable from the trace under it.
  test('a message with a stack trace is one kept line, not one per frame', () {
    final lines = printed(
      () => LogService.error('failed: boom\nframe one\nframe two'),
    );

    expect(keptLines, hasLength(1));
    expect(keptLines.single, contains('frame two'));
    expect(
      RegExp(r'\[\d\d:\d\d:\d\d\]').allMatches(keptLines.single),
      isEmpty,
      reason: 'the reader stamps its own; the stamp belongs to the console',
    );

    // Where the console goes the other way, deliberately: somebody scrolling a
    // terminal wants the time on the line in front of them, so every frame
    // carries it there. `log_timestamp_test.dart` is where that is pinned.
    expect(lines, hasLength(LogService.printing ? 3 : 0));
  });

  // One timed-out multi-frame RPC logs an unmatched frame per leftover frame,
  // and a directory listing is hundreds of frames. The reader at the other end
  // has no coalescing of its own, so unchecked that single fault is 400 sends,
  // and the quota it burns is gone before the next fault arrives.
  test('a message repeating itself is sent once', () {
    printed(() {
      LogService.error('the timeout that explains everything');
      for (var i = 0; i < 400; i++) {
        LogService.error('[RPC] rx unmatched frame cmdId=7');
      }
    });

    expect(keptLines, hasLength(2));
    expect(keptLines.first, contains('the timeout'));
    expect(keptLines.last, contains('rx unmatched frame'));
    // The buffer rendered the repeats as a `400×` suffix, because somebody was
    // going to read the list and the count was the useful part. Nothing renders
    // it now - the fold drops the repeats outright and how many there were is
    // not recoverable, which is the price of the buffer going.
    expect(keptLines.last, isNot(contains('×')));
  });

  test('a different message between two runs breaks the fold', () {
    printed(() {
      LogService.error('same');
      LogService.error('same');
      LogService.error('different');
      LogService.error('same');
    });

    // Four logs, three sends. The fold is consecutive-only, and the other
    // reading - remembering every body ever sent - would drop the *second*
    // occurrence of a failure entirely, which is the one that says it is not a
    // one-off.
    expect(keptLines, ['[error] same', '[error] different', '[error] same']);
  });

  // Two tests stood here and are gone with the thing they were about: that a
  // full buffer dropped its oldest entry, and that the buffer could not be
  // written through. ADR 0013 §1 removed the buffer, so there is no capacity
  // to overflow and no view to protect. What replaced them is the forwarding
  // these assert on either side - a line reaches the sink, and a repeat does
  // not.

  group('flipperlib', () {
    setUp(LogService.attachFlipperlibSink);
    tearDown(() {
      Log.sink = null;
      Log.level = FlipperLogLevel.info;
    });

    // The sink was only ever attached in a talking build, so in release none
    // of flipperlib's 83 error sites - transport faults, session failures -
    // reached anything at all. Log.error checks only that a sink exists.
    test('an error from the library is kept', () {
      printed(() => Log.error('[Transport] fault: port closed'));

      expect(keptLines.single, contains('port closed'));
    });

    // Why warnings are kept at all is on [attachFlipperlibSink] and not
    // repeated here. What matters for reading this file: like the error case
    // above, it is the quiet run that bites. Under `flutter test` with no
    // dart-define, `printing` is true and the level comes from QLOG, so this
    // passed before the fix too — only the `QLOG=false` CI job exercises the
    // branch that was pinning warnings out of existence.
    test('a warning from the library is kept', () {
      printed(() => Log.warn('[BLE] link carries only payload=20 of 411'));

      expect(keptLines.single, contains('payload=20'));
    });

    test('the chatty levels from the library are not', () {
      printed(() {
        Log.info('connected');
        Log.debug('frame');
        Log.trace('byte');
      });

      expect(keptLines, isEmpty);
    });
  });

  group('what nothing else catches', () {
    // The failures with the least surface of all: every handler the app added
    // for #21, #84, #85 and #80 covers something someone thought to catch.
    // These are the ones nobody did, and they reached nothing at all.
    late FlutterExceptionHandler? previousFlutter;
    late ErrorCallback? previousPlatform;

    setUp(() {
      previousFlutter = FlutterError.onError;
      previousPlatform = PlatformDispatcher.instance.onError;
      // dumpErrorToConsole prints the full banner for the first error in the
      // isolate and "Another exception was thrown: ..." for every one after
      // it, and this file runs on plain test() with no binding to reset that
      // between cases. So the test below asserting on the banner passed only
      // while it happened to dump first, which the declared order gave it and
      // a randomized one does not. #139.
      FlutterError.resetErrorCount();
      LogService.installUncaughtHandlers();
    });
    // Both, not just the first. Restoring only FlutterError left a wrapper on
    // the platform handler per test, two deep by the end of the group and
    // never unwound into the rest of the run.
    tearDown(() {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousPlatform;
    });

    test('a framework error is kept', () {
      final lines = printed(
        () => FlutterError.reportError(
          FlutterErrorDetails(
            exception: StateError('a build blew up'),
            stack: StackTrace.current,
          ),
        ),
      );

      expect(keptLines.single, contains('a build blew up'));
      expect(
        lines.where((l) => l.contains('[error] [flutter]')),
        isEmpty,
        reason: 'not a flat copy of it - console: false',
      );
      expect(
        lines.where((l) => l.contains('EXCEPTION CAUGHT BY FLUTTER')),
        isNotEmpty,
        reason: 'the chained handler still prints it, better formatted',
      );
    });

    // flutter_test installs its own handler to fail a test on an unexpected
    // error, and a debug build presents the red console dump through the same
    // hook. Recording must not cost either.
    test('the handler already installed still runs', () {
      var presented = 0;
      FlutterError.onError = (_) => presented += 1;
      LogService.installUncaughtHandlers();

      printed(
        () => FlutterError.reportError(
          FlutterErrorDetails(exception: StateError('boom')),
        ),
      );

      expect(presented, 1);
      expect(keptLines.single, contains('boom'));
    });
    // reportError has no try/catch of its own and exceptionAsString() calls
    // toString() on whatever it was given. Recording before the chained
    // handler would let one bad toString() cost the red screen and the failed
    // test - the two things this is written not to cost.
    test('a failure while recording does not cost the handler below', () {
      var presented = 0;
      FlutterError.onError = (_) => presented += 1;
      LogService.installUncaughtHandlers();

      printed(
        () => FlutterError.reportError(
          FlutterErrorDetails(exception: _ExplodingOnToString()),
        ),
      );

      expect(presented, 1, reason: 'the dump still happened');
      expect(keptLines, isEmpty, reason: 'and nothing half-formed was kept');
    });

    test('a framework error carries where it was thrown', () {
      printed(
        () => FlutterError.reportError(
          FlutterErrorDetails(
            exception: StateError('overflowed'),
            context: ErrorDescription('building MyWidget'),
          ),
        ),
      );

      expect(keptLines.single, contains('building MyWidget'));
    });

    // Silent is the framework's own word for "expected here, do not dump it",
    // and dumpErrorToConsole honours it in release.
    test('an error the framework marks silent is not kept', () {
      printed(
        () => FlutterError.reportError(
          FlutterErrorDetails(exception: StateError('expected'), silent: true),
        ),
      );

      expect(keptLines, isEmpty);
    });

    test('a missing stack does not leave the word null in the entry', () {
      printed(
        () => FlutterError.reportError(
          FlutterErrorDetails(exception: StateError('no stack here')),
        ),
      );

      expect(keptLines.single, isNot(endsWith('null')));
    });

    // The other half, which had no coverage at all: a rejected future nobody
    // awaited reaches PlatformDispatcher rather than FlutterError.
    test('an error nobody awaited is kept, and stays unhandled', () {
      var chained = 0;
      PlatformDispatcher.instance.onError = (e, st) {
        chained += 1;
        return false;
      };
      LogService.installUncaughtHandlers();

      late bool handled;
      printed(() {
        handled = PlatformDispatcher.instance.onError!(
          StateError('nobody awaited this'),
          StackTrace.current,
        );
      });

      expect(keptLines.single, contains('nobody awaited this'));
      expect(chained, 1, reason: 'whatever was there still runs');
      expect(handled, isFalse, reason: 'still unhandled, nothing suppressed');
    });

    // A second install wraps the wrappers, so one framework error runs the
    // recording twice. The fold is what makes that survivable - without it the
    // reader shows the app failing twice, and a duplicate failure is read as a
    // worse bug than the one that happened.
    //
    // **What this does and does not constrain**, because the honest version is
    // narrower than the name. Deleting the second install below leaves it
    // green, so it is not evidence that the double-install path works: one
    // recording gives one line and two give one line, which is the whole
    // point. The old buffer's `(2×)` suffix was the only thing that ever told
    // them apart, and it went with the buffer.
    //
    // Nothing replaces it. The fold sits in `_emit` *upstream* of every
    // observer there is - the sink never hears the second line, and the
    // uncaught path passes `console: false`, so the console does not either
    // (the test above pins that). "Recorded twice" is now unobservable by
    // construction.
    //
    // It does still fail if the fold goes: then the double install sends two.
    // That is what it is for, and the second assertion is there so a fold that
    // swallowed *everything* after the first line could not pass it.
    test('installing twice does not make one failure look like two', () {
      LogService.installUncaughtHandlers();

      printed(
        () => FlutterError.reportError(
          FlutterErrorDetails(exception: StateError('once')),
        ),
      );

      expect(keptLines, hasLength(1));

      printed(
        () => FlutterError.reportError(
          FlutterErrorDetails(exception: StateError('twice')),
        ),
      );

      expect(
        keptLines,
        hasLength(2),
        reason: 'the fold drops a repeat, not everything after the first',
      );
    });
  });

  // CI runs this file twice, and the second run is the only one that can see
  // the property the whole issue is about. If the define ever stops reaching
  // the build - a rename, a Flutter change, an edit to ci.yml - that job would
  // silently become a copy of the first and still pass. This is what stops it.
  test('the build under test is the one the run asked for', () {
    const expectsQuiet = bool.fromEnvironment('QLOG_EXPECT_QUIET');

    expect(LogService.printing, !expectsQuiet);
  });
}

/// Stands in for an exception whose own toString() fails, which is the case
/// that would otherwise take the chained handler down with it.
class _ExplodingOnToString {
  @override
  String toString() => throw StateError('even saying what I am fails');
}
