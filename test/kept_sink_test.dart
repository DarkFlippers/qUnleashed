// The second reader for what `LogService` keeps — ADR 0013 §2.
//
// `lib/services/telemetry/` installs one of these to turn kept lines into
// Sentry Logs. What this file holds is the contract `LogService` offers it,
// which has three parts worth tests: which levels arrive and as what, that a
// repeated line arrives **once**, and that a sink which fails neither takes
// the process down nor goes unreported - there is no local record left for it
// to fall back on.
import 'package:flipperlib/flipperlib.dart' show FlipperLogLevel, Log;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/telemetry/scrub.dart';

import 'quiet_log.dart';

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
    sink = _Sink();
    LogService.keptSink = sink.call;
  });

  tearDown(() => LogService.keptSink = null);

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
      // leftover frame, and a directory listing is hundreds of frames. The
      // reader at the other end has no coalescing of its own, so the fold is
      // the only thing standing between one failure and hundreds of sends.
      //
      // The old buffer rendered the repeats as a `(5×)` suffix and this used
      // to assert that too; with no buffer there is only the count of sends,
      // which is the half that mattered.
      quietly(() {
        for (var i = 0; i < 5; i++) {
          LogService.error('[RPC] rx unmatched frame');
        }
      });
      expect(sink.bodies, hasLength(1));
      expect(sink.bodies.single, '[error] [RPC] rx unmatched frame');
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
    test('is not scrubbed, and the console is not either', () {
      // The decision's other half, and the one nothing asserted. `_emit`
      // prints and announces the same `msg`, so a scrub inside `_emit`
      // breaks the test below - but a scrub applied to the *console
      // branch only* would pass it, and quietly cost a developer the
      // path they are debugging. That is this file's stated reason for
      // not scrubbing here, so it gets an assertion of its own.
      Scrub.debugUseHomes([r'C:\Users\Myte']);
      addTearDown(() => Scrub.debugUseHomes(null));

      final lines = printed(
        () => LogService.error(r'could not open C:\Users\Myte\x.ir'),
      );

      expect(sink.bodies.single, contains(r'C:\Users\Myte\x.ir'));
      expect(
        lines.where((l) => l.contains(r'C:\Users\Myte\x.ir')),
        hasLength(LogService.printing ? 1 : 0),
        reason: 'the console gets the real path, not `~`',
      );
    });

    test('is raw, because the sink is what scrubs', () {
      // This used to arrive with the account name already out of it, because
      // `_emit` redacted what it kept. Nothing is kept now, so there is no
      // reason for this file to scrub on the way past - and one reason not to:
      // the console is a developer's own machine and wants the real path.
      //
      // `Telemetry._reportKept` runs `Scrub.outbound` before it sends, which
      // `telemetry_lifecycle_test.dart` and `scrub_test.dart` cover between
      // them.
      Scrub.debugUseHomes([r'C:\Users\Myte']);
      addTearDown(() => Scrub.debugUseHomes(null));
      quietly(() => LogService.error(r'could not open C:\Users\Myte\x.ir'));
      expect(sink.bodies.single, r'[error] could not open C:\Users\Myte\x.ir');
    });

    test('carries no timestamp, because the reader stamps its own', () {
      quietly(() => LogService.error('plain'));
      expect(sink.bodies.single, '[error] plain');
      // The level prefix is part of the body and the stamp is not. The stamp
      // now exists only on the console, which `log_timestamp_test.dart`
      // asserts - this used to compare against a history entry that carried
      // one.
      expect(sink.bodies.single, startsWith('[error] '));
      expect(RegExp(r'^\[\d\d:').hasMatch(sink.bodies.single), isFalse);
    });
  });

  group('a sink that fails', () {
    test('is reported to the console, because nothing else is left', () {
      // This used to assert the history still held the line while the sink
      // failed. There is no history: a throw here loses the line outright,
      // which is why the failure has to reach *somewhere*.
      //
      // And it cannot reach it through `LogService.error`, which is what this
      // catch used to call: that re-enters `_emit`, which calls `_announce`,
      // where `_announcing` is still true - so the report was dropped and a
      // broken sink was invisible. It goes straight to `debugPrint` now, which
      // survives a release build.
      LogService.keptSink = (_, _) => throw StateError('sink is broken');

      final lines = printed(() => LogService.error('[CLI] write failed'));

      expect(
        lines.where((l) => l.contains('the kept-log sink threw')),
        hasLength(1),
      );
      expect(
        lines.firstWhere((l) => l.contains('the kept-log sink threw')),
        contains('[CLI] write failed'),
        reason: 'the report names the line it lost',
      );
    });

    test('is not re-entered by the report, however it is reported', () {
      // Two mechanisms hold this and only one of them is visible here. The
      // report goes to `debugPrint` rather than through `error`, so a throwing
      // sink cannot come back round even with `_announcing` deleted; the test
      // below, where the sink *logs* instead of throwing, is the one that
      // fails without the guard.
      //
      // Kept anyway, because a future report that went back through `error`
      // would be caught by this and by nothing else - and because a sink is
      // far likelier to throw than to log.
      var calls = 0;
      LogService.keptSink = (_, _) {
        calls += 1;
        throw StateError('always broken');
      };
      quietly(() => LogService.error('[CLI] write failed'));
      expect(calls, 1);
    });

    test('that logs instead of throwing does not recurse either', () {
      // The shape `_announcing` actually exists for, and the shipped one:
      // `Telemetry._reportKept` logs its own failures. Without the guard the
      // sink's line re-enters `_emit`, which calls the sink again - verified
      // by deleting the guard, which takes this to 2.
      //
      // Two, not a hang, and the reason is worth knowing: the fold stops it,
      // because this sink logs the *same* body every time and the second one
      // is folded away. A real sink whose message carries the error text would
      // not be stopped there, so the fold is not a substitute for the guard -
      // it is only what keeps the mutation cheap to run.
      var calls = 0;
      LogService.keptSink = (_, _) {
        calls += 1;
        LogService.error('[Telemetry] a kept log line was not sent');
      };
      quietly(() => LogService.error('[CLI] write failed'));
      expect(calls, 1);
    });

    test('that fails asynchronously does not loop either', () async {
      // The shape the **shipped** sink has, and the one `_announcing` does not
      // cover. `Telemetry._reportKept` hands its work to `_guard` and returns,
      // so the failure arrives a microtask later - by which time `_announcing`
      // is back to false. The report is itself a kept line, so it calls the
      // sink again, which fails again.
      //
      // The synchronous test above passes on a mechanism no real sink
      // exercises, which is CLAUDE.md's "trusting that a test fails for the
      // reason its name says". This one drives the real shape, and
      // deliberately does not rely on `_remember` coalescing to stop it: the
      // interleaved line moves `_lastKept`, which is exactly what breaks that
      // brake in production, where BLE warnings arrive throughout.
      var calls = 0;
      LogService.keptSink = (_, _) {
        calls += 1;
        Future<void>.error(StateError('send refused')).catchError((Object _) {
          LogService.error('[Telemetry] a kept log line was not sent: boom');
        });
      };

      quietly(() => LogService.error('[CLI] write failed'));
      await pumpEventQueue();
      quietly(() => LogService.warn('[BLE] something else entirely'));
      await pumpEventQueue();

      expect(
        calls,
        lessThan(10),
        reason: 'a self-sustaining chain would run until the test timed out',
      );
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

  test('no sink installed is not an error', () {
    // Every local build and every build with reporting off. There is nothing
    // left to observe once the sink is gone - which is the point of the
    // assertion: logging must not throw just because nobody is listening.
    LogService.keptSink = null;
    expect(
      () => quietly(() => LogService.error('[CLI] write failed')),
      returnsNormally,
    );
  });

  // ADR 0013 §4: flipperlib is the only source of breadcrumbs, because its
  // `Log.level` is a runtime check where the app's own `info` is a const that
  // folds out of a release build.
  group('breadcrumbs', () {
    late List<String> crumbs;
    late List<FlipperLogLevel> crumbLevels;

    setUp(() {
      crumbs = [];
      crumbLevels = [];
      LogService.breadcrumbSink = (severity, body) {
        crumbLevels.add(severity);
        crumbs.add(body);
      };
      LogService.attachFlipperlibSink();
    });

    tearDown(() {
      LogService.breadcrumbSink = null;
      Log.sink = null;
      Log.level = FlipperLogLevel.info;
    });

    test('the library\'s info arrives, and is still not kept', () {
      // The whole of what §4 unlocks. `info` was unreachable at the library's
      // gate while the pin was `warning`; it now reaches the hook and is
      // dropped by `_keptLevelFor` exactly as before, so nothing new enters
      // the history.
      quietly(() => Log.info('reconnecting'));

      expect(crumbs, ['reconnecting']);
      expect(crumbLevels, [FlipperLogLevel.info]);
      expect(sink.bodies, isEmpty, reason: 'a breadcrumb is not kept');
      expect(sink.levels, isEmpty, reason: 'and reaches no Sentry log');
    });

    test('a warning is both a breadcrumb and a kept line', () {
      // Not only `info`. The value of a breadcrumb is the sequence, and a
      // timeline with the warnings cut out of it is a worse timeline - the
      // Logs stream is separate, so the event would otherwise need
      // cross-referencing to read.
      quietly(() => Log.warn('[BLE] link carries only payload=20 of 411'));

      expect(crumbs, hasLength(1));
      expect(crumbLevels, [FlipperLogLevel.warning]);
      expect(sink.levels, [KeptLevel.warning]);
    });

    test('the sequence is what arrives, in order', () {
      quietly(() {
        Log.info('link lost');
        Log.info('reconnecting');
        Log.info('reconnected');
      });
      expect(crumbs, ['link lost', 'reconnecting', 'reconnected']);
    });

    test('every repeat arrives, unlike a kept line', () {
      // `_remember`'s fold is about a 500-entry buffer somebody reads. A
      // breadcrumb ring is the timeline, and collapsing "reconnecting" five
      // times into one would misstate what happened.
      quietly(() {
        for (var i = 0; i < 3; i++) {
          Log.info('reconnecting');
        }
      });
      expect(crumbs, hasLength(3));
    });

    test('carries absolute paths, because the sink is what scrubs', () {
      // This used to be redacted here, on the grounds that a breadcrumb skips
      // the kept branch and so skipped the redaction with it. Both channels
      // scrub in the sink now - `Telemetry._dropCrumb` runs `Scrub.outbound`
      // before it builds the `Breadcrumb`, and `beforeSend` runs it again over
      // the crumbs attached to an event - which leaves one rule to read
      // instead of two, and leaves the console honest.
      Scrub.debugUseHomes([r'C:\Users\Myte']);
      addTearDown(() => Scrub.debugUseHomes(null));
      quietly(() => Log.info(r'cache at C:\Users\Myte\flipper'));
      expect(crumbs.single, r'cache at C:\Users\Myte\flipper');
    });

    test('a sink that throws costs neither the line nor the process', () {
      var calls = 0;
      LogService.breadcrumbSink = (_, _) {
        calls += 1;
        throw StateError('crumbs are broken');
      };
      LogService.attachFlipperlibSink();

      quietly(() => Log.warn('[BLE] degraded'));

      expect(calls, 1, reason: 'the report must not re-enter the sink');
      expect(
        sink.bodies.any((l) => l.contains('[BLE] degraded')),
        isTrue,
        reason: 'the kept line survives a broken breadcrumb reader',
      );
      expect(
        sink.bodies.any((l) => l.contains('breadcrumb sink threw')),
        isTrue,
      );
    });
  });

  group('the level the library is pinned at', () {
    tearDown(() {
      LogService.breadcrumbSink = null;
      Log.sink = null;
      Log.level = FlipperLogLevel.info;
    });

    // `FlipperLogLevel` runs trace..error and `Log` admits a severity at or
    // above the pin, so a *lower* pin is chattier. Every comparison below is
    // that way round.
    test('is the keep threshold with no breadcrumb reader', () {
      LogService.breadcrumbSink = null;
      LogService.attachFlipperlibSink();
      // Only meaningful in a quiet build; a talking one is pinned by QLOG and
      // that case is asserted below.
      if (!LogService.printing) {
        expect(Log.level, FlipperLogLevel.warning);
      }
    });

    test('rises to info when one is installed, and falls again', () {
      LogService.breadcrumbSink = (_, _) {};
      LogService.attachFlipperlibSink();
      if (!LogService.printing) {
        expect(Log.level, FlipperLogLevel.info);
      }

      LogService.breadcrumbSink = null;
      LogService.attachFlipperlibSink();
      if (!LogService.printing) {
        expect(
          Log.level,
          FlipperLogLevel.warning,
          reason: 'the cost of info exists only while somebody is listening',
        );
      }
    });

    test('a talking build is never lowered by turning reporting off', () {
      // QLOG asked for the chatty levels explicitly, and a breadcrumb reader
      // going away must not take them with it. CI runs this file with QLOG
      // both ways, so one of the two branches is live each time.
      LogService.breadcrumbSink = null;
      LogService.attachFlipperlibSink();
      if (LogService.printing) {
        expect(
          Log.level.index,
          lessThanOrEqualTo(FlipperLogLevel.info.index),
          reason: 'at least as chatty as info, which is a lower index',
        );
      }
    });
  });
}
