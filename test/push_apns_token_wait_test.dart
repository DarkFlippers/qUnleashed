// The wait that QUNLEASHED-2 was missing.
//
// `subscribeToTopic` throws `apns-token-not-set` on iOS and macOS until APNS
// has registered the device, and that happens after `requestPermission`
// returns - so the apply at launch raced it and lost, taking the rest of
// `PushService.start()` with it. The loop under test is the seam that makes
// the race a wait; `_applySubscriptions` is its only caller, behind an
// `isIOS || isMacOS` the real `getAPNSToken` makes necessary.
//
// Real timers at a 1 ms cadence rather than `fakeAsync`: the loop reads the
// wall clock for its deadline, so a fake one would prove the wrong thing.
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
      // A second read would mean it slept first, and `poll` is a day.
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
      expect(reads, 4);
    });

    test(
      'gives up once the timeout is past, rather than waiting forever',
      () async {
        var reads = 0;
        final arrived = await PushService.awaitApnsToken(
          () async {
            reads++;
            return null;
          },
          timeout: const Duration(milliseconds: 20),
          poll: const Duration(milliseconds: 1),
        );

        expect(arrived, isFalse);
        // It polled rather than reading once and declaring defeat: a loop that
        // checked the deadline before the first sleep would pass `isFalse` on
        // one read, which is the shape this is here to rule out.
        expect(reads, greaterThan(1));
      },
    );
  });
}
