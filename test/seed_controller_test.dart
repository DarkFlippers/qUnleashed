// The parts of the seed recovery flow that do not need a device or an engine.
//
// The subset retry is the reason this file exists. A capture with one missed
// press cannot solve *entire* - the acceptance test needs every decrypted
// counter to be one from the last - while the presses either side of the gap
// are still consecutive among themselves. Without the retry a user with a
// nine-hop capture and one dropped frame is told no seed exists, which is the
// one answer that must not be given wrongly.
//
// What it cannot see: whether the engine agrees. The windows are offered to it
// in order; whether a given window solves is the native probe's business.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_controller.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_models.dart';

void main() {
  group('windowsFor', () {
    test('offers the whole capture first', () {
      // Longest first, because more hops mean a stronger answer: three put a
      // false positive near 1e-7 where two leave it conceivable.
      final windows = SeedController.windowsFor([1, 2, 3, 4]);
      expect(windows.first, [1, 2, 3, 4]);
    });

    test('then every contiguous run one shorter, in order', () {
      final windows = SeedController.windowsFor([1, 2, 3, 4]);
      expect(windows.take(4), [
        [1, 2, 3, 4],
        [1, 2, 3],
        [2, 3, 4],
        [1, 2],
      ]);
    });

    test('never offers a non-contiguous set', () {
      // Hops that were not sent back to back cannot have consecutive counters,
      // however many of them there are - so a gapped window is wasted sweeps.
      final hops = [10, 20, 30, 40, 50];
      for (final window in SeedController.windowsFor(hops)) {
        final start = hops.indexOf(window.first);
        expect(
          hops.sublist(start, start + window.length),
          window,
          reason: '$window is not a run of the capture',
        );
      }
    });

    test('drops a missed press at either end or in the middle', () {
      // The three shapes a single dropped frame can take. Each leaves one
      // contiguous run of three that the retry has to reach.
      final windows = SeedController.windowsFor([1, 2, 3, 4]);
      expect(windows, contains(equals([1, 2, 3]))); // last press missed
      expect(windows, contains(equals([2, 3, 4]))); // first press missed
      expect(windows, contains(equals([2, 3]))); // a press missed either side
    });

    test('never goes below what the engine accepts', () {
      for (final window in SeedController.windowsFor([1, 2, 3, 4, 5])) {
        expect(window.length, greaterThanOrEqualTo(SeedCapture.minHops));
      }
    });

    test('a capture at the minimum offers exactly itself', () {
      expect(SeedController.windowsFor([1, 2]), [
        [1, 2],
      ]);
    });

    test('a long capture is bounded, because each window is a full sweep', () {
      // Ten hops have 45 contiguous runs of two or more. Trying them all would
      // be 45 sweeps of the whole seed space with the user waiting.
      final windows = SeedController.windowsFor(List.generate(10, (i) => i));
      expect(windows.length, lessThan(20));
      expect(windows.first, hasLength(10));
    });
  });
}
