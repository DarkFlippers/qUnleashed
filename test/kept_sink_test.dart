// The second reader for what `LogService` keeps — ADR 0013 §2.
//
// `lib/services/telemetry/` installs one of these to turn kept lines into
// Sentry Logs. What this file holds is the contract `LogService` offers it,
// which has three parts worth tests: which levels arrive and as what, that a
// repeated line arrives **once**, and that a sink which fails costs neither
// the local record nor the process.
import 'package:flipperlib/flipperlib.dart' show FlipperLogLevel, Log;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/telemetry/scrub.dart';

/// Silences the console while a test records something, so the run stays
/// readable. Restored inline; flutter_test rejects addTearDown for this.
void quietly(void Function() body) {
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {};
  try {
    body();
  } finally {
    debugPrint = previous;
  }
}

class _Sink {
  final List<KeptLevel> levels = [];
  final List<String> bodies = [];

  void call(KeptLevel level, String body) {
    levels.add(level);
    bodies.add(body);
  }
}

void main() {
  late _Sink sink;

  setUp(() {
    LogService.clearHistory();
    sink = _Sink();
    LogService.keptSink = sink.call;
  });

  tearDown(() {
    LogService.keptSink = null;
    LogService.clearHistory();
  });

  group('which levels reach it', () {
    test('error arrives as error', () {
      quietly(() => LogService.error('[CLI] write failed'));
      expect(sink.levels, [KeptLevel.error]);
      expect(sink.bodies.single, '[error] [CLI] write failed');
    });

    test('warn arrives as warning', () {
      quietly(() => LogService.warn('[BLE] link is slow'));
      expect(sink.levels, [KeptLevel.warning]);
    });

    test('caught arrives as caught, not as a warning', () {
      // §5: the distinction is the audience. A remote reader needs to be able
      // to search these without the alerting `warn` is for, and the level is
      // the only thing carrying that.
      quietly(() => LogService.caught('[Archive] read refused'));
      expect(sink.levels, [KeptLevel.caught]);
      expect(sink.bodies.single, startsWith('[caught] '));
    });

    test('info reaches nothing, because nothing keeps it', () {
      // `info` is `keep: false` and const-folds out of a release build, so
      // there is no line to forward. This is the half of §4 that says the
      // app's own `info` feeds nothing.
      quietly(() => LogService.info('[Map] location stream'));
      expect(sink.levels, isEmpty);
    });
  });

  group('flipperlib lines', () {
    setUp(LogService.attachFlipperlibSink);
    tearDown(() {
      Log.sink = null;
      Log.level = FlipperLogLevel.info;
    });

    test('an error from the library arrives as error', () {
      quietly(() => Log.error('[Transport] fault: port closed'));
      expect(sink.levels, [KeptLevel.error]);
    });

    test('a warning from the library arrives as warning', () {
      quietly(() => Log.warn('[BLE] link carries only payload=20 of 411'));
      expect(sink.levels, [KeptLevel.warning]);
    });

    test('an info from the library reaches nothing', () {
      // The library's level pin is `warning`, and the sink reads the same
      // constant - setting those apart is what made warnings unreachable once
      // already. This is also what §4 trades away until phase 2 raises the
      // pin: the library's `info` is a breadcrumb, never a kept line.
      quietly(() {
        Log.level = FlipperLogLevel.info;
        Log.info('reconnecting');
      });
      expect(sink.levels, isEmpty);
    });
  });

  group('a repeated line', () {
    test('arrives once, however many times it is logged', () {
      // One timed-out multi-frame RPC produces an `rx unmatched frame` per
      // leftover frame, and a directory listing is hundreds of frames.
      // `_remember` folds those into one history entry; a sink told about each
      // of them would send hundreds to a reader with no coalescing at all.
      quietly(() {
        for (var i = 0; i < 5; i++) {
          LogService.error('[RPC] rx unmatched frame');
        }
      });
      expect(sink.bodies, hasLength(1));
      // And the history agrees, so the two cannot drift: the fold is the same
      // decision in both places.
      expect(LogService.history.single, contains('(5×)'));
    });

    test('a different line after a run of repeats arrives', () {
      quietly(() {
        LogService.error('same');
        LogService.error('same');
        LogService.error('different');
      });
      expect(sink.bodies, ['[error] same', '[error] different']);
    });

    test('the same line again after something else arrives again', () {
      // The fold is against the *last kept* body, not against everything ever
      // kept. A sink that deduplicated on its own would get this wrong.
      quietly(() {
        LogService.error('a');
        LogService.error('b');
        LogService.error('a');
      });
      expect(sink.bodies, ['[error] a', '[error] b', '[error] a']);
    });
  });

  group('the body it is handed', () {
    test('has absolute paths already out of it', () {
      Scrub.debugUseHomes([r'C:\Users\Myte']);
      addTearDown(() => Scrub.debugUseHomes(null));
      quietly(() => LogService.error(r'could not open C:\Users\Myte\x.ir'));
      expect(sink.bodies.single, r'[error] could not open ~\x.ir');
    });

    test('carries no timestamp, because the reader stamps its own', () {
      quietly(() => LogService.error('plain'));
      expect(sink.bodies.single, '[error] plain');
      // The history entry does carry one, which is the difference.
      expect(LogService.history.single, startsWith('['));
      expect(LogService.history.single, contains('[error] plain'));
    });
  });

  group('a sink that fails', () {
    test('does not cost the line it failed on', () {
      LogService.keptSink = (_, _) => throw StateError('sink is broken');
      quietly(() => LogService.error('[CLI] write failed'));

      // Two entries and in this order. Matching the first one by substring
      // does not work: the report quotes the body it failed on, so a filter
      // for the original line finds both and `hasLength(1)` fails for a
      // reason that has nothing to do with the behaviour.
      expect(LogService.history, hasLength(2));
      expect(
        LogService.history.first,
        endsWith('[error] [CLI] write failed'),
        reason: 'history is written before the sink runs',
      );
      expect(
        LogService.history.last,
        contains('kept-log sink threw'),
        reason: 'and the broken sink is itself reported',
      );
    });

    test('does not recurse, because the report would re-enter it', () {
      // Reporting a broken sink goes through LogService.error, which re-enters
      // _emit. Without the reentrancy guard this is unbounded: the report
      // calls the sink, the sink throws, that is reported, and so on until the
      // stack goes. The test that catches it is the one that would not
      // terminate at all without the fix.
      var calls = 0;
      LogService.keptSink = (_, _) {
        calls += 1;
        throw StateError('always broken');
      };
      quietly(() => LogService.error('[CLI] write failed'));
      expect(calls, 1);
    });

    test('is tried again on the next line, so the guard does not latch', () {
      var calls = 0;
      LogService.keptSink = (_, _) {
        calls += 1;
        if (calls == 1) throw StateError('once');
      };
      quietly(() {
        LogService.error('first');
        LogService.error('second');
      });
      expect(calls, 2);
    });
  });

  test('no sink installed changes nothing', () {
    LogService.keptSink = null;
    quietly(() => LogService.error('[CLI] write failed'));
    expect(LogService.history, hasLength(1));
  });
}
