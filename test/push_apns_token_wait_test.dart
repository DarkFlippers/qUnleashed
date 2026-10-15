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
      // Exactly four, not "at least": a second read per iteration would be a
      // doubled method channel call for the life of every launch.
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
      // executed by anything, and a `Duration(milliseconds: 20)` typo on the
      // poll constant would leave every other test in this file green.
      //
      // It is the poll this pins and not the timeout - a mistyped timeout
      // still sleeps once and still arrives on the second read. Nothing here
      // bounds the 20 seconds, because a test that did would take 20 seconds.
      final arrived = await PushService.awaitApnsToken(() async {
        reads++;
        return reads < 2 ? null : 'apns-token';
      });

      expect(arrived, isTrue);
      expect(reads, 2);
      expect(
        elapsed.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 150)),
      );
    });
  });
}
