// The parts of the seed recovery flow that do not need a device or an engine.
//
// The subset retry is the reason this file exists. The engine tolerates a
// counter step up to SeedCapture.maxCounterGap, so one dropped frame now solves
// on the first sweep - but a longer run of missed presses still does not, while
// the presses either side of it are within the tolerance among themselves.
// Without the retry a user holding such a capture is told no seed exists, which
// is the one answer that must not be given wrongly.
//
// What it stops short of is the other half: a window below seedHopsConfident
// buys reach the app cannot use, because canSave refuses the answer. Two tests
// hold that line, and not symmetrically - 'synthesises no window the app would
// refuse to save' pins the exclusion, while 'covers every over-wide gap that
// leaves a confident run' pins that the exclusion costs no reach above the
// line. Only the first fails if the rung comes back.
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

    test('covers every over-wide gap that leaves a confident run', () {
      // The property, rather than a list: for each length and each place the
      // counters could break, some offered window has to lie wholly inside one
      // of the two surviving runs. The first version of this ladder failed this
      // from n=12 upwards while looking thorough.
      //
      // "Confident" is the bound, not minHops: a run of two is reachable only
      // by a window the app would then refuse to save, so the ladder stopped
      // offering one (#288).
      //
      // What that skips, exactly: n=3 either side, and n=4 with the break in
      // the middle - the only cases where both runs are under
      // seedHopsConfident. For every n of five or more the same pairs are
      // asserted as before, and each assertion is now stronger, since a
      // two-hop window no longer counts as covering a run. The loop therefore
      // asserts nothing at all for n=3, which is why what those captures
      // *do* is pinned end to end in seed_search_test.dart instead, by 'a
      // break the confident ladder cannot step over ends in "nothing
      // matched"'.
      //
      // This test would also pass with the rung restored - adding windows
      // cannot make an `any` fail - so it does not guard the exclusion.
      // 'synthesises no window the app would refuse to save' does.
      for (var n = SeedCapture.minHops; n <= SeedCapture.maxHops + 6; n++) {
        final hops = List.generate(n, (i) => i);
        final offered = SeedController.windows(hops);
        for (var gap = 1; gap < n; gap++) {
          final runs = [hops.sublist(0, gap), hops.sublist(gap)];
          if (runs.every((run) => run.length < seedHopsConfident)) continue;
          final covered = offered.any(
            (window) => runs.any(
              (run) =>
                  window.length >= seedHopsConfident &&
                  run.length >= window.length &&
                  _isSubRun(run, window),
            ),
          );
          expect(
            covered,
            isTrue,
            reason:
                'n=$n with the counters breaking at $gap is not covered by '
                '$offered',
          );
        }
      }
    });

    test('synthesises no window the app would refuse to save', () {
      // The other half of #288. A window below seedHopsConfident comes back as
      // an answer canSave declines and the page shows as unconfirmed, after a
      // whole-space sweep to find it - so the only short window offered is the
      // capture itself, which is the user's own data rather than this ladder's
      // invention.
      for (var n = SeedCapture.minHops; n <= SeedCapture.maxHops; n++) {
        final hops = List.generate(n, (i) => i);
        final offered = SeedController.windows(hops);
        expect(offered.first, hops, reason: 'n=$n should start with itself');
        for (final window in offered.skip(1)) {
          expect(
            window.length,
            greaterThanOrEqualTo(seedHopsConfident),
            reason: 'n=$n offered $window',
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

    test('and none below the confidence line on an over-long capture', () {
      // Above maxHops the first window is the trimmed tail rather than the
      // capture itself, so the test above cannot simply run further. The
      // exclusion still has to hold here: a capture of 20 hops is a supported
      // input the parser keeps whole.
      for (var n = SeedCapture.maxHops + 1; n <= SeedCapture.maxHops + 6; n++) {
        final offered = SeedController.windows(List.generate(n, (i) => i));
        for (final window in offered) {
          expect(
            window.length,
            greaterThanOrEqualTo(seedHopsConfident),
            reason: 'n=$n offered $window',
          );
        }
      }
    });

    test('offers the prefix even when its first hop recurs', () {
      // A capture whose first hop value appears again where the suffix window
      // starts. The ladder used to carry a de-duplication check keyed on the
      // first hop's *value*, which discarded the prefix here - a run that may
      // be the only gap-free one in the capture, dropped silently, for a value
      // collision that says nothing about position. A repeated hop further
      // back is exactly what the parser now deliberately keeps (#289), so the
      // shape is reachable rather than hypothetical.
      final offered = SeedController.windows([9, 1, 2, 3, 4, 9, 6, 7]);
      expect(offered, [
        [9, 1, 2, 3, 4, 9, 6, 7],
        [9, 6, 7],
        [9, 1, 2],
      ]);
    });

    test('three sweeps at most, whatever the capture', () {
      // Three is the whole point: the first version of this ladder offered
      // twelve, and twelve sweeps of a 2^32 space is the user watching a bar
      // for minutes to be told nothing matched. A sweep that finds nothing
      // measured seventeen seconds on a current phone, so each rung is a real
      // wait rather than a rounding error.
      for (var n = SeedCapture.minHops; n <= SeedCapture.maxHops + 6; n++) {
        final count = SeedController.windows(List.generate(n, (i) => i)).length;
        expect(count, lessThanOrEqualTo(3), reason: 'n=$n offered $count');
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
