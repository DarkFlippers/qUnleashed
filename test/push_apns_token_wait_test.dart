// The wait that Sentry QUNLEASHED-2 was missing.
//
// A topic call throws without an APNS token, and the token arrives after
// `requestPermission` returns - so the apply at launch raced it and lost,
// taking the rest of `PushService.start()` with it. `awaitApnsToken`'s own
// doc carries that contract; the loop under test is the seam that makes the
// race a wait. Its only caller in `lib/` is `_apnsReady`, behind the platform
// checks the real `getAPNSToken` makes necessary.
//
// Real timers rather than `fakeAsync`: `fakeAsync` intercepts
// `Future.delayed` but not a `Stopwatch`, so elapsing fake time would advance
// the sleeps while the loop's own clock stood still and the timeout case
// would never terminate. `package:clock` is the change that would make fake
// time work here, and it is not made - so the elapsed-time assertions below
// are lower bounds, which real timers can only overshoot.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/notifications/push_service.dart';

void main() {
  group('PushService.awaitApnsToken', () {
    test('returns at once when the token is already there', () async {
      var reads = 0;
      final arrived = await PushService.awaitApnsToken(
        () async {
          reads++;
          return 'apns-token';
        },
        timeout: const Duration(seconds: 5),
        poll: const Duration(days: 1),
      );

      expect(arrived, isTrue);
      // `poll` is a day, so a loop that slept before reading would hang here
      // rather than fail: the suite timeout is what this catches, and `reads`
      // pins that the token was read exactly once on the way past.
      expect(reads, 1);
    });

    test('keeps looking until the token turns up', () async {
      var reads = 0;
      final arrived = await PushService.awaitApnsToken(
        () async {
          reads++;
          return reads < 4 ? null : 'apns-token';
        },
        timeout: const Duration(seconds: 5),
        poll: const Duration(milliseconds: 1),
      );

      expect(arrived, isTrue);
      // Exactly four: it neither gave up over the three nulls nor read past
      // the token. Note this cannot catch a loop that reads twice per
      // iteration - that one reaches the token on read 4 as well. The sleep
      // count is what catches it, and the defaults case below does that.
      expect(reads, 4);
    });

    test(
      'gives up once the timeout is past, rather than waiting forever',
      () async {
        var reads = 0;
        final elapsed = Stopwatch()..start();
        final arrived = await PushService.awaitApnsToken(
          () async {
            reads++;
            return null;
          },
          timeout: const Duration(milliseconds: 200),
          poll: const Duration(milliseconds: 1),
        );

        expect(arrived, isFalse);
        // The bound is the point of the loop, so assert the bound and not the
        // read count. An implementation that counted attempts instead of time
        // would pass every other test here and silently turn 20 seconds into
        // however long a hundred polls happen to take - which on a device slow
        // enough to need the wait is the bug coming back.
        //
        // 200ms rather than the 20ms this started at: Windows timer granularity
        // rounds a 1ms sleep up to ~10ms, so the old budget left one loop
        // iteration of margin and one OS preemption would have failed it.
        expect(
          elapsed.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 200)),
        );
        expect(reads, greaterThan(1));
      },
    );

    test('the shipped poll interval is the one that runs', () async {
      var reads = 0;
      final elapsed = Stopwatch()..start();
      // No named arguments: the production defaults are otherwise never
      // executed by anything, and a mistyped first gap would leave every
      // other test in this file green.
      //
      // It is the gap this pins and not the timeout - a mistyped timeout
      // still sleeps once and still arrives on the second read. Nothing here
      // bounds the 20 seconds, because a test that did would take 20 seconds.
      //
      // The bound is the full 50ms rather than a margin under it: a sleep
      // cannot finish early, only late, so there is nothing to leave room
      // for. It also fails a loop that reads twice before sleeping, which is
      // the mutant the read count two tests up cannot see.
      final arrived = await PushService.awaitApnsToken(() async {
        reads++;
        return reads < 2 ? null : 'apns-token';
      });

      expect(arrived, isTrue);
      expect(reads, 2);
      expect(
        elapsed.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 50)),
      );
    });

    test('the gap doubles rather than staying where it started', () async {
      var reads = 0;
      final elapsed = Stopwatch()..start();
      final arrived = await PushService.awaitApnsToken(
        () async {
          reads++;
          return reads < 4 ? null : 'apns-token';
        },
        timeout: const Duration(seconds: 5),
        poll: const Duration(milliseconds: 20),
        pollCap: const Duration(milliseconds: 200),
      );

      expect(arrived, isTrue);
      expect(reads, 4);
      // 20 + 40 + 80. A loop that kept the first gap would be at 60ms, so the
      // bound is what separates backing off from not - and it is a floor, so
      // a slow machine overshooting it cannot turn this red.
      expect(
        elapsed.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 140)),
      );
    });

    test('the gap stops doubling at the cap', () async {
      var reads = 0;
      final elapsed = Stopwatch()..start();
      await PushService.awaitApnsToken(
        () async {
          reads++;
          return null;
        },
        timeout: const Duration(milliseconds: 250),
        poll: const Duration(milliseconds: 20),
        pollCap: const Duration(milliseconds: 40),
      );

      // Without a cap the gaps would be 20, 40, 80, 160 - four sleeps to pass
      // 250ms. Capped at 40 they are 20, 40, 40, 40, 40, 40, so the read count
      // is what tells the two apart.
      expect(reads, greaterThanOrEqualTo(6));
      expect(
        elapsed.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 250)),
      );
    });
  });

  group('PushService.topicsSupported', () {
    // The platform decision reads `defaultTargetPlatform` rather than
    // `dart:io` precisely so this test can exist: on the host `Platform`
    // answers Windows and nothing below would be reachable.
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('is the two platforms FCM topics work on', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(PushService.topicsSupported, isTrue, reason: '$platform');
      }
    });

    test('and not macOS, which has no aps-environment entitlement', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(PushService.topicsSupported, isFalse, reason: '$platform');
      }
    });
  });
}
