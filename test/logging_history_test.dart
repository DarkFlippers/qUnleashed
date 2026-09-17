import 'dart:ui';

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
  // the error branch was shaken out and every error site, most of them in
  // catch blocks, reported nowhere at all.
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

  group('what nothing else catches', () {
    // The failures with the least surface of all: every handler the app added
    // for #21, #84, #85 and #80 covers something someone thought to catch.
    // These are the ones nobody did, and they reached nothing at all.
    late FlutterExceptionHandler? previousFlutter;
    late ErrorCallback? previousPlatform;

    setUp(() {
      previousFlutter = FlutterError.onError;
      previousPlatform = PlatformDispatcher.instance.onError;
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

      expect(LogService.history.single, contains('a build blew up'));
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
      expect(LogService.history.single, contains('boom'));
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
      expect(
        LogService.history,
        isEmpty,
        reason: 'and nothing half-formed was kept',
      );
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

      expect(LogService.history.single, contains('building MyWidget'));
    });

    // Silent is the framework's own word for "expected here, do not dump it",
    // and dumpErrorToConsole honours it in release.
    test('an error the framework marks silent is not kept', () {
      printed(
        () => FlutterError.reportError(
          FlutterErrorDetails(exception: StateError('expected'), silent: true),
        ),
      );

      expect(LogService.history, isEmpty);
    });

    test('a missing stack does not leave the word null in the entry', () {
      printed(
        () => FlutterError.reportError(
          FlutterErrorDetails(exception: StateError('no stack here')),
        ),
      );

      expect(LogService.history.single, isNot(endsWith('null')));
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

      expect(LogService.history.single, contains('nobody awaited this'));
      expect(chained, 1, reason: 'whatever was there still runs');
      expect(handled, isFalse, reason: 'still unhandled, nothing suppressed');
    });

    // A second install wraps the wrappers, and _remember then coalesces the
    // pair into a count rather than duplicating - so the log would read as the
    // app having failed twice, which is worse than a duplicate.
    test('installing twice does not make one failure look like two', () {
      LogService.installUncaughtHandlers();

      printed(
        () => FlutterError.reportError(
          FlutterErrorDetails(exception: StateError('once')),
        ),
      );

      expect(LogService.history, hasLength(1));
      expect(LogService.history.single, isNot(contains('2×')));
    });
  });

  // The log became something a user copies into a public issue, and every
  // absolute path in it starts with the account name. It is the only category
  // that can be taken out mechanically.
  //
  // Driven through the seam rather than the real environment: the cases worth
  // pinning are all about environments this machine does not have, and a test
  // that reads Platform.environment passes vacuously wherever it is unusual -
  // which is exactly where the bug was.
  group('redaction', () {
    tearDown(() => LogService.debugUseHomes(null));

    test('a home directory is replaced wherever it appears', () {
      LogService.debugUseHomes([r'C:\Users\Myte']);

      printed(
        () => LogService.error(r'could not clear C:\Users\Myte\Docs\x.ir'),
      );

      expect(LogService.history.single, isNot(contains('Myte')));
      expect(LogService.history.single, contains('~'));
    });

    // The case the first version missed. A FileSystemException prints the
    // native path, but a stack frame prints a URI with the separators flipped
    // and the drive behind a scheme - and the entries carrying stacks are the
    // ones most likely to be pasted into an issue.
    test('a Windows home is replaced in a stack frame URI too', () {
      LogService.debugUseHomes([r'C:\Users\Myte']);

      printed(
        () => LogService.error(
          'boom\n#0 main (file:///C:/Users/Myte/app/main.dart:7:20)',
        ),
      );

      expect(LogService.history.single, isNot(contains('Myte')));
    });

    // A HOME of /root is ordinary in a container. Replacing it blind rewrote
    // /rootfs to ~fs and corrupted messages that had no path in them at all.
    test('a home that prefixes an unrelated word is left alone', () {
      LogService.debugUseHomes(['/root']);

      printed(() => LogService.error('mounting /rootfs failed'));

      expect(LogService.history.single, contains('/rootfs'));
    });

    test('and is still replaced when it is a real path', () {
      LogService.debugUseHomes(['/root']);

      printed(() => LogService.error('could not clear /root/x.ir'));

      expect(LogService.history.single, contains('~/x.ir'));
    });

    // On Windows under Git Bash both environment keys hold the same string.
    // Behaviour cannot show the duplicate — replacing the same thing twice
    // gives the same answer — so the count is the only way to see it.
    test('the same home twice is not scanned for twice', () {
      LogService.debugUseHomes([r'C:\Users\Myte']);
      final once = LogService.debugHomePatternCount;

      LogService.debugUseHomes([r'C:\Users\Myte', r'C:\Users\Myte']);

      expect(LogService.debugHomePatternCount, once);
    });

    test('a home too short to be one is ignored', () {
      LogService.debugUseHomes(['/x']);

      printed(() => LogService.error('reading /x/y'));

      expect(LogService.history.single, contains('/x/y'));
    });

    test('a message with no path in it is left alone', () {
      printed(() => LogService.error('[RPC] rx unmatched frame cmdId=7'));

      expect(
        LogService.history.single,
        contains('[RPC] rx unmatched frame cmdId=7'),
      );
    });

    // Only what can be copied is redacted. Everything below a warning is not
    // kept, so paying a scan for it buys nothing - and a developer's console
    // should print the path they are debugging.
    test('what is only printed keeps its path', () {
      LogService.debugUseHomes(['/root']);

      final lines = printed(() => LogService.info('reading /root/x.ir'));

      expect(
        LogService.history,
        isEmpty,
        reason: 'nothing to copy, so no cost',
      );
      // Printed unredacted in a build that prints, and not printed at all in
      // one that does not — so the check follows the build rather than
      // pinning whichever one CI happens to be running.
      expect(lines.join().contains('/root/x.ir'), LogService.printing);
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
