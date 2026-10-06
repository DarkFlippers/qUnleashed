// The search loop, driven against a fake engine.
//
// Each of these is a failure the controller used to have, and each was found by
// asking the question ADR 0008 asks: if this goes wrong, what does the user
// see? The answers were "the page says Searching forever", "the user who
// pressed Stop is told their capture is no good", and "a capture that is better
// than it needs to be is reported as the engine being broken".
//
// The recoverer is injectable, which is what makes all of this reachable
// without a device or a native library.
//
// What it cannot see: anything that needs a FlipperClient. `open`, `refresh`
// and `save` all take one, so they are not exercised here - the sibling takes
// injectable APIs for that reason and this controller does not yet.
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/mifare_native.dart';
import 'package:qunleashed/pages/tools/subghz/seed/faaccrack_recoverer.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_controller.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_models.dart';

/// An engine that answers however the test needs, and records what it was asked.
class _FakeRecoverer implements FaaccrackRecoverer {
  _FakeRecoverer(this._answer);

  /// Called once per window, with the window.
  final SeedResult Function(List<int> hops, int call) _answer;

  final windows = <List<int>>[];

  /// Run before answering, so a test can stop the search mid-flight.
  void Function()? beforeAnswer;

  @override
  Future<SeedResult> recover({
    required SeedManufacturer manufacturer,
    required int fix,
    required List<int> hops,
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  }) async {
    windows.add(List.of(hops));
    beforeAnswer?.call();
    onProgress?.call(0.5);
    return _answer(hops, windows.length - 1);
  }
}

SeedResult _result(SeedOutcome outcome, {int? seed}) => (
  outcome: outcome,
  seed: seed,
  lrkey: seed == null ? null : 0x1122334455667788,
  counter: seed == null ? null : 0x123,
  frameHop: seed == null ? null : 0xAABBCCDD,
  hopsUsed: seed == null ? null : 3,
);

/// A controller with a capture already loaded, so `search()` can be reached
/// without a device.
SeedController _controllerWith(_FakeRecoverer recoverer, List<int> hops) {
  final controller = SeedController(
    client: FlipperClient(),
    recoverer: recoverer,
  );
  controller.debugSetCapture(
    SeedCapture(
      fix: 0xA0DC9330,
      hops: hops,
      manufacturer: SeedManufacturer.genius,
      frequencyHz: 868350000,
    ),
  );
  return controller;
}

void main() {
  test('a found seed stops the search and is reported', () async {
    final recoverer = _FakeRecoverer(
      (hops, call) => _result(SeedOutcome.found, seed: 0x789),
    );
    final controller = _controllerWith(recoverer, [1, 2, 3]);

    await controller.search();

    expect(controller.result!.outcome, SeedOutcome.found);
    expect(controller.result!.seed, 0x789);
    expect(controller.stage, SeedStage.idle);
    expect(recoverer.windows, hasLength(1), reason: 'no need for a subset');
    expect(controller.canSave, isTrue);
  });

  test('a capture with a missed press solves on a shorter window', () async {
    // The whole point of the retry: the full set cannot solve because the
    // counters are not all adjacent, while a run either side of the gap can.
    final recoverer = _FakeRecoverer(
      (hops, call) => hops.length == 4
          ? _result(SeedOutcome.nothingMatched)
          : _result(SeedOutcome.found, seed: 0x789),
    );
    final controller = _controllerWith(recoverer, [1, 2, 3, 4]);

    await controller.search();

    expect(controller.result!.outcome, SeedOutcome.found);
    expect(recoverer.windows.first, [1, 2, 3, 4]);
    expect(recoverer.windows[1], hasLength(3));
  });

  test('a stop between windows is a stop, not "nothing matched"', () async {
    // The failure this test exists for: `break` left the previous window's
    // answer in place, so the user who pressed Stop was told no seed matched
    // their capture and sent to re-record a remote that was fine.
    late final SeedController controller;
    final recoverer = _FakeRecoverer(
      (hops, call) => _result(SeedOutcome.nothingMatched),
    );
    controller = _controllerWith(recoverer, [1, 2, 3, 4]);
    recoverer.beforeAnswer = controller.stop;

    await controller.search();

    expect(controller.result!.outcome, SeedOutcome.stopped);
    expect(controller.stage, SeedStage.idle);
  });

  test('a missing engine ends the search instead of latching the page', () async {
    // Without a catch, this throw escaped a discarded future: the page sat on
    // "Searching the seed space..." with a 0% bar and a dead Stop button until
    // the user left, and the only trace was an uncaught zone error naming no
    // operation.
    final recoverer = _FakeRecoverer((hops, call) {
      throw const NativeEngineUnavailable('no library here');
    });
    final controller = _controllerWith(recoverer, [1, 2, 3]);

    await controller.search();

    expect(controller.stage, SeedStage.idle);
    expect(controller.result!.outcome, SeedOutcome.engineUnavailable);
    expect(controller.canSave, isFalse);
  });

  test('any other throw ends the search too', () async {
    final recoverer = _FakeRecoverer((hops, call) => throw StateError('boom'));
    final controller = _controllerWith(recoverer, [1, 2, 3]);

    await controller.search();

    expect(controller.stage, SeedStage.idle);
    expect(controller.result!.outcome, SeedOutcome.engineFault);
  });

  test('a fault is not retried on every subset', () async {
    // Retrying a fault would repeat it once per window, which on a long
    // capture is eight identical failures and eight times the wait.
    final recoverer = _FakeRecoverer(
      (hops, call) => _result(SeedOutcome.engineFault),
    );
    final controller = _controllerWith(recoverer, [1, 2, 3, 4, 5]);

    await controller.search();

    expect(recoverer.windows, hasLength(1));
  });

  test('an unverified seed is shown but cannot be saved', () async {
    // The seed is real; the rebuilt frame did not reproduce the capture, so a
    // file carrying it would transmit nothing.
    final recoverer = _FakeRecoverer(
      (hops, call) => _result(SeedOutcome.unverified, seed: 0x789),
    );
    final controller = _controllerWith(recoverer, [1, 2, 3]);

    await controller.search();

    expect(controller.result!.seed, 0x789);
    expect(controller.canSave, isFalse);
  });

  test('a capture with no frequency cannot be saved either', () async {
    // The frequency is not recoverable from a fix and a hop, so a capture
    // without one can be solved and not written.
    final recoverer = _FakeRecoverer(
      (hops, call) => _result(SeedOutcome.found, seed: 0x789),
    );
    final controller =
        SeedController(client: FlipperClient(), recoverer: recoverer)
          ..debugSetCapture(
            SeedCapture(
              fix: 0xA0DC9330,
              hops: const [1, 2, 3],
              manufacturer: SeedManufacturer.genius,
            ),
          );

    await controller.search();

    expect(controller.result!.outcome, SeedOutcome.found);
    expect(controller.canSave, isFalse);
  });
}
