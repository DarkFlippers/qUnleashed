import 'package:flipperlib/flipperlib.dart' show FlipperLogLevel, Log;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/logging.dart';

/// What `debugPrint` received while [body] ran.
///
/// Restored inline rather than through addTearDown, which flutter_test rejects
/// as changing a debug variable.
List<String> printed(void Function() body) {
  final lines = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  try {
    body();
  } finally {
    debugPrint = previous;
  }
  return lines;
}

void main() {
  setUp(LogService.clearHistory);
  tearDown(LogService.clearHistory);

  // The whole point of #89. LogService.enabled is a const that follows the
  // build type, and every guard derived from it folds — so in a shipped build
  // the error branch was shaken out and 19 call sites, 11 of them in catch
  // blocks, reported nowhere at all.
  //
  // Both halves are asserted together on purpose: printing still follows the
  // build, and keeping no longer does. In the default run errorOn is true and
  // this reads as "printed and kept"; under --dart-define=QLOG=false it reads
  // as "kept though nothing printed", which is the case that was broken. CI
  // runs this file both ways.
  test('an error is kept whether or not the build prints anything', () {
    final lines = printed(() => LogService.error('a transport fault'));

    expect(LogService.history.single, contains('a transport fault'));
    expect(
      lines.isEmpty,
      !LogService.errorOn,
      reason: 'printing follows the build; keeping does not',
    );
  });

  test('a warning is kept too', () {
    printed(() => LogService.warn('the port went quiet'));

    expect(LogService.history.single, contains('the port went quiet'));
  });

  // Anything below a warning runs often enough to churn the buffer, which
  // would cost the failure the context the buffer exists to hold.
  test('the chatty levels are not kept', () {
    printed(() {
      LogService.info('opened the archive');
      LogService.log('and again');
      LogService.debug('frame');
      LogService.trace('byte');
    });

    expect(LogService.history, isEmpty);
  });

  // One entry, not one per frame. Thirteen of the app's error sites pass
  // '$e\n$st' and a Dart stack trace runs to thirty frames or so, so splitting
  // by line would leave room for about sixteen failures - and one deep trace
  // could evict everything that led up to it.
  test('a message with a stack trace is one entry, stamped once', () {
    printed(() => LogService.error('failed: boom\nframe one\nframe two'));

    expect(LogService.history, hasLength(1));
    expect(LogService.history.single, contains('frame two'));
    expect(
      RegExp(r'\[\d\d:\d\d:\d\d\]').allMatches(LogService.history.single),
      hasLength(1),
      reason: 'the time belongs to the failure, not to every frame of it',
    );
  });

  // One timed-out multi-frame RPC logs an unmatched frame per leftover frame,
  // and a directory listing is hundreds of frames. Unchecked, that single
  // failure evicts the buffer including the timeout that explains it.
  test('a message repeating itself is counted, not accumulated', () {
    printed(() {
      LogService.error('the timeout that explains everything');
      for (var i = 0; i < 400; i++) {
        LogService.error('[RPC] rx unmatched frame cmdId=7');
      }
    });

    expect(LogService.history, hasLength(2));
    expect(LogService.history.first, contains('the timeout'));
    expect(LogService.history.last, contains('400×'));
  });

  test('a different message after a run of repeats starts a new entry', () {
    printed(() {
      LogService.error('same');
      LogService.error('same');
      LogService.error('different');
      LogService.error('same');
    });

    expect(LogService.history, hasLength(3));
    expect(LogService.history[0], contains('2×'));
    expect(LogService.history[1], contains('different'));
    expect(LogService.history[2], isNot(contains('×')));
  });

  test('the oldest messages go when the buffer is full', () {
    printed(() {
      for (var i = 0; i <= LogService.historyLimit; i++) {
        LogService.error('failure $i');
      }
    });

    expect(LogService.history, hasLength(LogService.historyLimit));
    expect(LogService.history.first, contains('failure 1'));
    expect(
      LogService.history.last,
      contains('failure ${LogService.historyLimit}'),
      reason: 'oldest first, so a reader ends at the most recent',
    );
  });

  test('the history cannot be written through', () {
    printed(() => LogService.error('boom'));

    expect(() => LogService.history.add('forged'), throwsUnsupportedError);
  });

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

      expect(LogService.history.single, contains('port closed'));
    });

    test('the chatty levels from the library are not', () {
      printed(() {
        Log.info('connected');
        Log.debug('frame');
        Log.trace('byte');
      });

      expect(LogService.history, isEmpty);
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
