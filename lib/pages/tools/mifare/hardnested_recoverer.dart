import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'mifare_native.dart';

/// How an attack ended, which the user needs told apart.
enum HardnestedOutcome {
  /// A key came back.
  found,

  /// Ran to the end and found nothing - an answer about the card.
  noKey,

  /// Stopped because the caller asked.
  stopped,

  /// The bridge could not allocate its own nonce buffer. Not a verdict on
  /// whether the device could host the attack: the engine's own allocations
  /// still call exit(), which nothing here can catch.
  outOfMemory,

  /// Another attack is already running. The engine keeps one channel, so a
  /// second would take the first one's and send its Stop nowhere.
  engineBusy,

  /// The engine answered something this build does not know. Its own fault
  /// rather than the card's, and said that way.
  engineFault,
}

/// A key, or the reason there isn't one.
///
/// `outcome` is never null, so the switch that consumes it is exhaustive and
/// the compiler catches a new engine status instead of letting it fall into
/// "no key on this card".
typedef HardnestedResult = ({BigInt? key, HardnestedOutcome outcome});

/// Recovers a hardened-PRNG (hardnested) MIFARE Classic sector key from the
/// encrypted nonces collected into `.nested.log`. The whole ciphertext-only
/// attack runs on the app host via the native `qunleashed_hardnested_recover`
/// (bitflip tables are embedded in the native lib - nothing to bundle/extract).
abstract class HardnestedRecoverer {
  /// Recovers the sector key from [ntEnc]/[parEnc] (parallel arrays, one entry
  /// per collected nonce) for card [cuid].
  ///
  /// [onProgress] receives brute-force completion, 0..1, and is not called at
  /// all until that phase starts - the phases before it are bounded and
  /// comparatively short, and a number invented for them would be worse than an
  /// honest "working". [isCancelled] is polled on the same timer: the attack can
  /// take hours, so Stop has to reach it rather than waiting it out.
  ///
  /// No time estimate: the engine measures its own rate only after the brute
  /// force has finished, so there is none to report while it runs.
  Future<HardnestedResult> recoverKey({
    required int cuid,
    required List<int> ntEnc,
    required List<int> parEnc,
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  });
}

/// Mirrors `qunleashed_hn_progress` - three 32-bit words, two written by the
/// engine and read here, one (`abort`) written here and read by the engine,
/// while the attack runs in another isolate. Shared memory
/// rather than a callback, because the engine reports from its own worker
/// threads; see the header for the reasoning.
final class _HnProgress extends Struct {
  @Uint32()
  external int permille;
  @Uint32()
  external int abort;
  @Uint32()
  external int started;
}

typedef _RecoverNative = Int32 Function(
  Uint32 cuid,
  Pointer<Uint32> ntEnc,
  Pointer<Uint8> parEnc,
  Uint32 count,
  Pointer<Uint64> found,
  Pointer<_HnProgress> progress,
);

typedef _RecoverDart = int Function(
  int cuid,
  Pointer<Uint32> ntEnc,
  Pointer<Uint8> parEnc,
  int count,
  Pointer<Uint64> found,
  Pointer<_HnProgress> progress,
);

/// Maps the bridge's status to an outcome.
///
/// Its own function so the mapping can be tested: everything around it needs a
/// loaded engine and an isolate. The codes are the bridge's, and `-2` is its
/// "bad arguments" - a fault in this app rather than an answer about the card,
/// which is what it used to be reported as.
@visibleForTesting
HardnestedResult hardnestedResultFor(int status, int foundKey) =>
    switch (status) {
      0 => (key: BigInt.from(foundKey), outcome: HardnestedOutcome.found),
      -1 => (key: null, outcome: HardnestedOutcome.outOfMemory),
      -3 => (key: null, outcome: HardnestedOutcome.stopped),
      -4 => (key: null, outcome: HardnestedOutcome.engineBusy),
      -10 => (key: null, outcome: HardnestedOutcome.noKey),
      _ => (key: null, outcome: HardnestedOutcome.engineFault),
    };

/// How often the caller looks at the channel. The engine reports once per
/// brute-force bucket, which is far more often than this, so the interval sets
/// how fresh the bar is and how quickly a Stop lands.
const _pollInterval = Duration(milliseconds: 500);

class NativeHardnestedRecoverer implements HardnestedRecoverer {
  @override
  Future<HardnestedResult> recoverKey({
    required int cuid,
    required List<int> ntEnc,
    required List<int> parEnc,
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  }) async {
    // ntEnc/parEnc are parallel arrays built from the same nonce group, so a
    // length mismatch is a caller bug (assert), not a "too few nonces" result.
    assert(ntEnc.length == parEnc.length, 'ntEnc/parEnc must be parallel');
    // The engine consumes nonces in pairs, so it needs at least two.
    if (ntEnc.length < 2) {
      return (key: null, outcome: HardnestedOutcome.noKey);
    }

    // Allocated here rather than in the isolate: this side has to read it while
    // the other side is blocked inside the engine. Native memory is
    // process-scoped, so the address is all that has to cross.
    final channel = calloc<_HnProgress>();
    final payload = _HardnestedPayload(
      cuid: cuid,
      ntEnc: Uint32List.fromList(ntEnc),
      parEnc: Uint8List.fromList(parEnc),
      channelAddress: channel.address,
    );

    final poll = Timer.periodic(_pollInterval, (_) {
      if (isCancelled?.call() ?? false) channel.ref.abort = 1;
      if (onProgress == null || channel.ref.started == 0) return;
      onProgress(channel.ref.permille / 1000);
    });

    try {
      return await Isolate.run(() => _recoverInIsolate(payload));
    } finally {
      poll.cancel();
      calloc.free(channel);
    }
  }

  static HardnestedResult _recoverInIsolate(_HardnestedPayload p) {
    final recover = lookupNativeFunction(
      () => openHardnestedNativeLibrary()
          .lookupFunction<_RecoverNative, _RecoverDart>(
            'qunleashed_hardnested_recover',
          ),
    );
    final count = p.ntEnc.length;
    final ntPtr = calloc<Uint32>(count);
    final parPtr = calloc<Uint8>(count);
    final found = calloc<Uint64>();
    try {
      ntPtr.asTypedList(count).setAll(0, p.ntEnc);
      parPtr.asTypedList(count).setAll(0, p.parEnc);
      final result = recover(
        p.cuid,
        ntPtr,
        parPtr,
        count,
        found,
        Pointer<_HnProgress>.fromAddress(p.channelAddress),
      );
      return hardnestedResultFor(result, found.value);
    } finally {
      calloc.free(ntPtr);
      calloc.free(parPtr);
      calloc.free(found);
    }
  }
}

class _HardnestedPayload {
  const _HardnestedPayload({
    required this.cuid,
    required this.ntEnc,
    required this.parEnc,
    required this.channelAddress,
  });

  final int cuid;
  final Uint32List ntEnc;
  final Uint8List parEnc;

  /// An address rather than a pointer: a Pointer cannot be sent to an isolate,
  /// and the memory it names is process-scoped so the address is enough.
  final int channelAddress;
}
