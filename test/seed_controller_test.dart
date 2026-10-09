// The parts of the seed recovery flow that do not need a device or an engine.
//
// The subset retry is the reason this file exists. The engine tolerates a
// counter step up to SeedCapture.maxCounterGap, so one dropped frame now solves
// on the first sweep - but a longer run of missed presses still does not, while
// the presses either side of it are within the tolerance among themselves.
// Without the retry a user holding such a capture is told no seed exists, which
// is the one answer that must not be given wrongly.
//
// What it cannot see: whether the engine agrees. The windows are offered to it
// in order; whether a given window solves is the native probe's business.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_controller.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_models.dart';

void main() {
  group('windows', () {
    test('offers the whole capture first', () {
      // One sweep, and the strongest hops_used of any window.
      expect(SeedController.windows([1, 2, 3, 4]).first, [1, 2, 3, 4]);
    });

    test('then the freshest end, then the oldest', () {
      // Suffix before prefix is not cosmetic: the counter and the rebuilt
      // frame come from the window's last hop, so a prefix that solved first
      // would write a remote several presses behind the receiver.
      expect(SeedController.windows([1, 2, 3, 4, 5]), [
        [1, 2, 3, 4, 5],
        [3, 4, 5],
        [1, 2, 3],
      ]);
    });

    test('covers every single-gap capture the engine will accept', () {
      // The property, rather than a list: for each length and each place a
      // press could have been missed, some offered window has to lie wholly
      // inside one of the two gap-free runs. The first version of this ladder
      // failed this from n=12 upwards while looking thorough.
      for (var n = SeedCapture.minHops; n <= SeedCapture.maxHops; n++) {
        final hops = List.generate(n, (i) => i);
        final offered = SeedController.windows(hops);
        for (var gap = 1; gap < n; gap++) {
          final runs = [hops.sublist(0, gap), hops.sublist(gap)];
          // A gap that leaves neither side long enough for the engine is
          // unsolvable however it is sliced - n=2 with the one press missed.
          if (runs.every((run) => run.length < SeedCapture.minHops)) continue;
          final covered = offered.any(
            (window) => runs.any(
              (run) =>
                  window.length >= SeedCapture.minHops &&
                  run.length >= window.length &&
                  _isSubRun(run, window),
            ),
          );
          expect(
            covered,
            isTrue,
            reason:
                'n=$n with a press missed at $gap is not covered by '
                '$offered',
          );
        }
      }
    });

    test('never offers more than the engine accepts', () {
      final windows = SeedController.windows(List.generate(20, (i) => i));
      expect(windows.first, hasLength(SeedCapture.maxHops));
      for (final window in windows) {
        expect(window.length, lessThanOrEqualTo(SeedCapture.maxHops));
        expect(window.length, greaterThanOrEqualTo(SeedCapture.minHops));
      }
    });

    test('an over-long capture is cut from the stale end', () {
      // The last hops are the freshest, and the counter the .sub carries comes
      // from the last one in the window.
      final hops = List.generate(20, (i) => i);
      expect(SeedController.windows(hops).first.last, hops.last);
    });

    test('a capture at the minimum offers exactly itself', () {
      expect(SeedController.windows([1, 2]), [
        [1, 2],
      ]);
    });

    test('three sweeps for any real capture, five for the shortest', () {
      // Three is the whole point: the first version of this ladder offered
      // twelve, and twelve sweeps of a 2^32 space is the user watching a bar
      // for minutes to be told nothing matched.
      for (var n = SeedCapture.minHops; n <= SeedCapture.maxHops; n++) {
        final count = SeedController.windows(List.generate(n, (i) => i)).length;
        expect(
          count,
          lessThanOrEqualTo(n >= 2 * seedHopsConfident - 1 ? 3 : 5),
          reason: 'n=$n offered $count',
        );
      }
    });
  });
}

/// Whether [window] appears in [run] as a contiguous stretch.
bool _isSubRun(List<int> run, List<int> window) {
  for (var start = 0; start + window.length <= run.length; start++) {
    var same = true;
    for (var i = 0; i < window.length; i++) {
      if (run[start + i] != window[i]) {
        same = false;
        break;
      }
    }
    if (same) return true;
  }
  return false;
}
