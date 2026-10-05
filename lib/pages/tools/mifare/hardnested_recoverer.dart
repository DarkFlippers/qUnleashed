import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../../../services/logging.dart';
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

typedef _BytesNative = Uint64 Function();
typedef _BytesDart = int Function();

/// Whether an attack needing [tableBytes] should be started on a device with
/// [availableBytes] going spare. Returns the refusal to hand back, or null to
/// go ahead.
///
/// This exists because the engine's own out-of-memory handling cannot run where
/// it is needed. It calls `exit()` when an allocation fails - but Android and
/// iOS overcommit, so the allocation does not fail: the kernel kills the process
/// when the pages are first touched, with no return value anywhere to check.
/// Before the attack starts is the only place left to catch it, and
/// [HardnestedOutcome.outOfMemory] was an outcome that essentially never fired.
///
/// Pure, and separate from the lookups, because the whole judgement is in the
/// two comparisons below and testing them must not need a loaded engine.
@visibleForTesting
HardnestedResult? hardnestedMemoryVerdict({
  required int tableBytes,
  required int availableBytes,
}) {
  // Either figure missing means the question could not be asked - no engine, or
  // a platform with no answer for it. Going ahead is what shipped before this
  // gate existed; refusing on an absent figure would turn an unasked question
  // into a failed attack.
  if (tableBytes <= 0 || availableBytes <= 0) return null;
  // The tables are a floor, not the total: the sum-property bitarrays and the
  // candidate statelists sit on top of them and scale with the nonce set. A
  // quarter again is a margin, not a measurement, and deliberately a small one.
  // Being too strict costs an attack that would have finished; being too loose
  // costs what happens today, which is the app disappearing.
  if (availableBytes * 4 >= tableBytes * 5) return null;
  return (key: null, outcome: HardnestedOutcome.outOfMemory);
}

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

    // Before anything is allocated, and before the isolate: once the engine is
    // inside init_bitflip_bitarrays there is nothing left to refuse with.
    final refusal = _memoryVerdict();
    if (refusal != null) return refusal;

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

  /// Asks the engine what it needs and the OS what it has, then judges.
  ///
  /// On the calling isolate, not in the attack's: both calls are a few
  /// microseconds (one walks the 2046-entry table index, the other reads a
  /// single OS figure), and the answer decides whether to spawn at all.
  static HardnestedResult? _memoryVerdict() {
    final int tableBytes;
    final int availableBytes;
    try {
      final library = openHardnestedNativeLibrary();
      tableBytes = lookupNativeFunction(
        () => library.lookupFunction<_BytesNative, _BytesDart>(
          'qunleashed_hn_table_bytes',
        ),
      )();
      availableBytes = lookupNativeFunction(
        () => library.lookupFunction<_BytesNative, _BytesDart>(
          'qunleashed_hn_available_bytes',
        ),
      )();
    } on NativeEngineUnavailable {
      // Not this gate's verdict to give. The isolate loads the engine too and
      // already reports a packaging fault as one; answering here would report a
      // build missing its native library as a device short of memory, and send
      // the user after the wrong thing.
      return null;
    }
    final refusal = hardnestedMemoryVerdict(
      tableBytes: tableBytes,
      availableBytes: availableBytes,
    );
    if (refusal != null) {
      // warn, not info: this is the whole record of why an attack the user
      // asked for never ran, and info reaches nothing in a release build. Both
      // figures, because which one was wrong is the first question.
      LogService.warn(
        '[Recover] hardnested not started: needs at least '
        '${tableBytes >> 20} MiB for its tables, OS reports '
        '${availableBytes >> 20} MiB available',
      );
    }
    return refusal;
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
