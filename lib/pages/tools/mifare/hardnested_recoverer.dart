import 'dart:async';
import 'dart:ffi';
import 'dart:io';
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

  /// Not enough memory. Either the pre-flight gate refused the attack before
  /// it started ([hardnestedMemoryVerdict]), or the bridge could not allocate
  /// its own nonce buffer.
  ///
  /// Still not a verdict on the engine's *internal* allocations: those call
  /// exit(), which nothing here can catch, and on a 64-bit phone they do not
  /// fail at all - the kernel kills the process instead. The gate exists
  /// because that is unreachable from here once the attack has begun.
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

/// How much the requirement adds over the engine's measured peak: an eighth.
///
/// Small on purpose. `qunleashed_hn_peak_bytes` is a measurement of five named
/// allocations rather than an estimate - the note on its definition in
/// hardnested.c says which, and what it leaves out - so this only has to cover
/// the part it leaves out, plus the app's own working set alongside it.
const _memoryMarginDivisor = 8;

/// Bytes an attack needs available before it is worth starting.
///
/// One spelling, so the refusal message cannot quote a different number from
/// the one the judgement used. That had already happened once: the message named
/// the peak while the comparison used the peak plus the margin, so it read
/// "needs 702 MiB, has 800 MiB" on a run it had just refused.
int hardnestedRequiredBytes(int peakBytes) =>
    peakBytes + peakBytes ~/ _memoryMarginDivisor;

/// Whether both figures are answers at all.
///
/// Written once because the verdict and its caller both need it and for
/// different reasons: the verdict has to go ahead, the caller has to say so.
bool _figuresUsable(int peakBytes, int availableBytes) =>
    peakBytes > 0 && availableBytes > 0;

/// Whether an attack whose engine peaks at [peakBytes] should be started on a
/// device with [availableBytes] going spare. Returns the refusal to hand back,
/// or null to go ahead.
///
/// This exists because the engine's own out-of-memory handling cannot run where
/// it is needed. It calls `exit()` when an allocation fails - but Android and
/// iOS hand out address space lazily, so on 64-bit the allocation does not fail:
/// the kernel kills the process when the pages are first touched, with no return
/// value anywhere to check. Before the attack starts is the only place left, and
/// [HardnestedOutcome.outOfMemory] was an outcome that essentially never fired.
///
/// Pure, and separate from the lookups, because the whole judgement is the two
/// comparisons below and testing them must not need a loaded engine.
@visibleForTesting
HardnestedResult? hardnestedMemoryVerdict({
  required int peakBytes,
  required int availableBytes,
}) {
  // Either figure missing means the question could not be asked - no engine, or
  // a platform with no answer for it. Going ahead is what shipped before this
  // gate existed; refusing on an absent figure would turn an unasked question
  // into a failed attack. The caller logs this case; see [_memoryVerdict].
  if (!_figuresUsable(peakBytes, availableBytes)) return null;
  if (availableBytes >= hardnestedRequiredBytes(peakBytes)) return null;
  return (key: null, outcome: HardnestedOutcome.outOfMemory);
}

/// The one record of why an attack the user asked for never started.
///
/// Built here rather than inline so a test can hold it to naming the figure the
/// judgement actually used - the requirement, not the bare peak.
@visibleForTesting
String hardnestedMemoryRefusal({
  required int peakBytes,
  required int availableBytes,
}) =>
    '[Recover] hardnested not started: needs '
    '${hardnestedRequiredBytes(peakBytes) >> 20} MiB '
    '(engine peaks at ${peakBytes >> 20} MiB), '
    'OS reports ${availableBytes >> 20} MiB available';

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
      return await _spawnAttack(payload);
    } finally {
      poll.cancel();
      calloc.free(channel);
    }
  }

  /// Spawns the attack with [payload] as the only thing the sent closure can
  /// reach.
  ///
  /// Its own method, and that is the whole point - do not inline it back into
  /// [recoverKey]. A closure captures the context of the scope it is written
  /// in, not merely the variables it mentions, so written inline beside
  /// `isCancelled` and `onProgress` it also carried them. Those close over the
  /// RecoverController, which holds a FlipperClient, which holds a Future -
  /// and a Future cannot cross an isolate boundary. `Isolate.run` therefore
  /// threw before the engine started, every time:
  ///
  ///   Illegal argument in isolate message: object is unsendable
  ///     - Library:'dart:async' Class: _Future
  ///     <- Instance of 'FlipperClient'
  ///     <- Instance of 'RecoverController'
  ///
  /// which the caller reported as "the engine failed" - so hardnested looked
  /// broken rather than un-started, and no progress ever appeared because no
  /// attack ever ran. Here the enclosing scope holds one variable, so there is
  /// nothing else to drag along.
  static Future<HardnestedResult> _spawnAttack(_HardnestedPayload payload) =>
      Isolate.run(() => _recoverInIsolate(payload));

  /// The engine's peak, which is the same for the life of the process.
  ///
  /// Cached because it is a pure function of the vendored static tables - the
  /// note on its definition in hardnested.c says so - while this runs once per
  /// hardnested group, and a run re-attacks every nonce the card's log has ever
  /// collected. Left null on failure, so the next group retries and the warn
  /// below still fires rather than being swallowed by a cached miss.
  ///
  /// The available figure is deliberately *not* cached beside it: the previous
  /// group just released ~1.8 GiB and another app may have grown since, so a
  /// remembered figure would be exactly the stale number this gate exists to
  /// avoid - refusing a group that would now fit, or admitting one that no
  /// longer does.
  static int? _peakBytes;
  static DynamicLibrary? _library;

  /// Asks the engine what it needs and the OS what it has, then judges.
  ///
  /// On the calling isolate, not in the attack's: the figures are a few
  /// microseconds (the peak makes 2046 lookups into a static table index -
  /// 0x001 to 0x3ff over both parities - and sums five allocation sizes; the
  /// other reads a single OS figure), and the answer decides whether to spawn
  /// at all.
  ///
  /// Advisory, so every way of not getting an answer ends in "go ahead" - but
  /// none of them ends in silence. A gate that quietly switched itself off would
  /// leave a killed app looking exactly like one with no gate at all.
  static HardnestedResult? _memoryVerdict() {
    final int peakBytes;
    final int availableBytes;
    try {
      // Held too: on Windows openNativeLibrary stats the executable's directory
      // to find the bundled DLL, and doing that per group is the only
      // filesystem work on this path.
      final library = _library ??= openHardnestedNativeLibrary();
      peakBytes = _peakBytes ??= lookupNativeFunction(
        () => library.lookupFunction<_BytesNative, _BytesDart>(
          'qunleashed_hn_peak_bytes',
        ),
      )();
      availableBytes = lookupNativeFunction(
        () => library.lookupFunction<_BytesNative, _BytesDart>(
          'qunleashed_hn_available_bytes',
        ),
      )();
    } on NativeEngineUnavailable catch (e) {
      // The decision not to answer is right: the isolate loads the engine too
      // and reports a missing library as the packaging fault it is, so refusing
      // here would send the user after a memory problem they do not have.
      //
      // Logged all the same, because the case that gets here is not only a
      // missing library. On Apple the lookup is DynamicLibrary.process(), which
      // never fails, so a build carrying the engine but *not these two symbols*
      // lands here - and the isolate then looks up a different, older symbol,
      // succeeds, and reports nothing. That exact fault has shipped before (see
      // the note on QUNLEASHED_EXPORT in mfkey32/nested_bridge.c), and without
      // this line the only trace of a silently disabled gate would be an app
      // that disappears.
      LogService.warn(
        '[Recover] hardnested memory gate skipped, the engine did not '
        'answer: $e',
      );
      return null;
    } catch (e, st) {
      // Deliberately broad, and the one place in this file where that is right.
      // "Could not ask" already has a defined, safe meaning, so an advisory
      // check must not be the thing that fails the attack: anything escaping
      // here would otherwise reach _recoverHardnested's catch and be reported
      // to the user as the attack failing, on a card that was probably fine.
      LogService.error(
        '[Recover] hardnested memory gate failed, starting anyway: $e\n$st',
      );
      return null;
    }
    if (!_figuresUsable(peakBytes, availableBytes)) {
      // Only where a figure was expected. macOS and Windows answer 0 by design,
      // so saying this on a desktop would be noise on every single attack.
      if (Platform.isAndroid || Platform.isIOS) {
        LogService.warn(
          '[Recover] hardnested memory gate could not ask '
          '(engine peak $peakBytes, available $availableBytes); '
          'starting anyway',
        );
      }
      return null;
    }
    final refusal = hardnestedMemoryVerdict(
      peakBytes: peakBytes,
      availableBytes: availableBytes,
    );
    if (refusal != null) {
      // warn, not info: this is the whole record of why an attack the user
      // asked for never ran, and info reaches nothing in a release build.
      LogService.warn(
        hardnestedMemoryRefusal(
          peakBytes: peakBytes,
          availableBytes: availableBytes,
        ),
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
