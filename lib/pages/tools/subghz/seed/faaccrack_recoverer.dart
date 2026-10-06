import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../../../../services/logging.dart';
import '../../mifare/mifare_native.dart';
import 'seed_models.dart';

/// Recovers the seed of a FAAC SLH, Genius, BFT or Erreka remote from a capture.
///
/// The whole search runs on the app host through `qunleashed_faaccrack`; the
/// Flipper only ever collected the frames. See
/// `lib/modules/cpp/faaccrack/BUILD_NOTES.md`.
abstract class FaaccrackRecoverer {
  /// Searches for the seed of [manufacturer]'s remote [fix], given [hops] in
  /// the order they were sent.
  ///
  /// [onProgress] receives 0..1 and is not called until the sweep has begun.
  /// [isCancelled] is polled on the same timer; a stop reaches the engine
  /// within one claimed chunk, which is milliseconds.
  Future<SeedResult> recover({
    required SeedManufacturer manufacturer,
    required int fix,
    required List<int> hops,
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  });
}

/// Mirrors `struct faaccrack_progress`. Four 32-bit words, three written by the
/// engine and one by this side, while the search runs in another isolate.
///
/// A second declaration of the same shape as `_HnProgress` in
/// `hardnested_recoverer.dart` rather than a reuse, because that one is private
/// to its file. `faaccrackProgressSize` below is what keeps both honest.
final class _FaaccrackProgress extends Struct {
  @Uint32()
  external int permille;
  @Uint32()
  external int abort;
  @Uint32()
  external int started;
  @Uint32()
  external int threadsStarted;
}

/// Mirrors `struct faaccrack_result`. The 64-bit key comes first so the eight
/// 32-bit fields pack behind it with no padding - the C header pins that with
/// `_Static_assert`, and this side checks the total size against the bridge.
final class _FaaccrackResult extends Struct {
  @Uint64()
  external int lrkey;
  @Uint32()
  external int seed;
  @Uint32()
  external int lastPlain;
  @Uint32()
  external int counter;
  @Uint32()
  external int framePlain;
  @Uint32()
  external int frameHop;
  @Uint32()
  external int roundTripOk;
  @Uint32()
  external int hopsUsed;
  @Uint32()
  external int lanes;
}

typedef _RecoverNative = Int32 Function(
  Uint32 mode,
  Uint32 fix,
  Pointer<Uint32> hops,
  Uint32 nhop,
  Int32 threads,
  Pointer<_FaaccrackProgress> progress,
  Pointer<_FaaccrackResult> result,
);

typedef _RecoverDart = int Function(
  int mode,
  int fix,
  Pointer<Uint32> hops,
  int nhop,
  int threads,
  Pointer<_FaaccrackProgress> progress,
  Pointer<_FaaccrackResult> result,
);

typedef _Uint32Native = Uint32 Function();
typedef _Uint32Dart = int Function();
typedef _StringNative = Pointer<Utf8> Function();

/// The native status codes, from `enum faaccrack_status`.
///
/// Retyped rather than derived - this project has no code generation - which is
/// why [seedOutcomeFor] has a test of its own. A code the C side adds without a
/// case here lands in [SeedOutcome.engineFault], which reads as "this build is
/// wrong" rather than as an answer about the remote. That is the safe default,
/// and it is still worth noticing.
const _statusOk = 0;
const _statusBadArgs = -2;
const _statusStopped = -3;
const _statusBusy = -4;
const _statusUnverified = -5;
const _statusNotFound = -10;
const _statusSelfTestFirst = -22;
const _statusSelfTestLast = -20;

/// Maps a native status to an outcome.
///
/// Its own function so the mapping can be tested: everything around it needs a
/// loaded engine and an isolate.
@visibleForTesting
SeedOutcome seedOutcomeFor(int status) {
  if (status >= _statusSelfTestFirst && status <= _statusSelfTestLast) {
    return SeedOutcome.engineSelfTestFailed;
  }
  return switch (status) {
    _statusOk => SeedOutcome.found,
    _statusUnverified => SeedOutcome.unverified,
    _statusNotFound => SeedOutcome.nothingMatched,
    _statusStopped => SeedOutcome.stopped,
    _statusBusy => SeedOutcome.engineBusy,
    _statusBadArgs => SeedOutcome.engineFault,
    _ => SeedOutcome.engineFault,
  };
}

/// Whether the result struct carries anything worth reading.
///
/// The C side fills it for a find and for a frame that would not rebuild, and
/// zeroes it otherwise - and zero is a legal seed, so the outcome is the only
/// thing that says the struct means anything.
@visibleForTesting
bool seedResultIsMeaningful(SeedOutcome outcome) =>
    outcome == SeedOutcome.found || outcome == SeedOutcome.unverified;

/// How often the caller looks at the channel. The engine republishes far more
/// often than this, so the interval sets how fresh the bar is and how quickly a
/// Stop lands.
const _pollInterval = Duration(milliseconds: 250);

class NativeFaaccrackRecoverer implements FaaccrackRecoverer {
  @override
  Future<SeedResult> recover({
    required SeedManufacturer manufacturer,
    required int fix,
    required List<int> hops,
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  }) async {
    // Both of these are the user's situation rather than a bug, and the engine
    // reports either as "bad arguments" - which a caller would show as the
    // engine being broken. Caught here so the page can say what to do instead.
    if (hops.length < SeedCapture.minHops ||
        hops.length > SeedCapture.maxHops) {
      return _empty(SeedOutcome.engineFault);
    }

    // Allocated on this side: the poll timer has to read it while the other
    // isolate is blocked inside the engine. Native memory is process-scoped, so
    // only the address has to cross.
    final channel = calloc<_FaaccrackProgress>();
    final payload = _SeedPayload(
      mode: manufacturer.mode,
      fix: fix,
      hops: Uint32List.fromList(hops),
      threads: _threadCount(),
      channelAddress: channel.address,
    );

    final poll = Timer.periodic(_pollInterval, (_) {
      if (isCancelled?.call() ?? false) channel.ref.abort = 1;
      if (onProgress == null || channel.ref.started == 0) return;
      onProgress(channel.ref.permille / 1000);
    });

    try {
      return await _spawnSearch(payload);
    } finally {
      poll.cancel();
      calloc.free(channel);
    }
  }

  /// Spawns the search with [payload] as the only thing the sent closure can
  /// reach.
  ///
  /// Its own method, and that is the point - do not inline it. A Dart closure
  /// captures the context of the scope it is written in, not merely the
  /// variables it names, so written beside `isCancelled` it would also carry
  /// whatever that closes over. In the MIFARE recoverer that reached a
  /// FlipperClient holding a Future, which cannot cross an isolate boundary, so
  /// every attack was rejected before any native code ran. The note on
  /// `spawnAttackIsolate` in mifare_native.dart is the full account.
  static Future<SeedResult> _spawnSearch(_SeedPayload payload) =>
      spawnAttackIsolate(_searchInIsolate, payload);

  /// Workers to ask for.
  ///
  /// The engine does not ask the OS itself: that is a different call per
  /// platform, and this side needs the figure anyway to estimate the wait. The
  /// bridge answers 0 when it has no answer, which means "pick a default"
  /// rather than "no CPUs".
  static int _threadCount() {
    try {
      final count = lookupNativeFunction(
        () => openFaaccrackNativeLibrary()
            .lookupFunction<_Uint32Native, _Uint32Dart>(
              'qunleashed_faaccrack_cpu_count',
            ),
      )();
      if (count > 0) return count;
    } on NativeEngineUnavailable catch (e) {
      // The isolate loads the engine too and reports a missing library as the
      // packaging fault it is, so this must not fail the search - but a build
      // that loads and is missing *this* symbol is worth a line, because on
      // Apple the lookup never fails and a stripped export would otherwise be
      // silent.
      LogService.warn('[Seed] CPU count unavailable, using a default: $e');
    }
    return 4;
  }

  static SeedResult _searchInIsolate(_SeedPayload p) {
    final library = openFaaccrackNativeLibrary();
    final recover = lookupNativeFunction(
      () => library.lookupFunction<_RecoverNative, _RecoverDart>(
        'qunleashed_faaccrack_recover',
      ),
    );
    _assertLayout(library);

    final hops = calloc<Uint32>(p.hops.length);
    final result = calloc<_FaaccrackResult>();
    try {
      hops.asTypedList(p.hops.length).setAll(0, p.hops);
      final status = recover(
        p.mode,
        p.fix,
        hops,
        p.hops.length,
        p.threads,
        Pointer<_FaaccrackProgress>.fromAddress(p.channelAddress),
        result,
      );
      final outcome = seedOutcomeFor(status);
      if (!seedResultIsMeaningful(outcome)) return _empty(outcome);
      final found = result.ref;
      return (
        outcome: outcome,
        seed: found.seed,
        lrkey: found.lrkey,
        counter: found.counter,
        frameHop: found.frameHop,
        hopsUsed: found.hopsUsed,
      );
    } finally {
      calloc.free(hops);
      calloc.free(result);
    }
  }

  /// Checks the hand-written mirrors against the sizes the bridge reports.
  ///
  /// This is the one hole the build cannot cover. `keep.txt` and the compiler
  /// keep the C side honest, and `_Static_assert`s pin the layout for every
  /// compiled variant - but nothing protects a Dart `Struct`. Add a field on
  /// one side only and Dart reads wrong offsets with no compile error, no link
  /// error, and a plausible-looking seed.
  ///
  /// An assert rather than a thrown error: in release the sizes are whatever
  /// the shipped library says, and refusing to run then would turn a layout
  /// mistake into a dead feature for everyone. In debug and in tests it fails
  /// loudly, which is where it would be introduced.
  static void _assertLayout(DynamicLibrary library) {
    assert(() {
      int sizeFrom(String symbol) => lookupNativeFunction(
        () => library.lookupFunction<_Uint32Native, _Uint32Dart>(symbol),
      )();
      final result = sizeFrom('qunleashed_faaccrack_result_size');
      final progress = sizeFrom('qunleashed_faaccrack_progress_size');
      if (result != sizeOf<_FaaccrackResult>()) {
        throw StateError(
          'faaccrack_result is $result bytes natively and '
          '${sizeOf<_FaaccrackResult>()} in Dart - the mirror is stale',
        );
      }
      if (progress != sizeOf<_FaaccrackProgress>()) {
        throw StateError(
          'faaccrack_progress is $progress bytes natively and '
          '${sizeOf<_FaaccrackProgress>()} in Dart - the mirror is stale',
        );
      }
      return true;
    }());
  }

  /// Which per-instruction-set variant the dispatcher picked.
  ///
  /// Worth logging once per run: the difference between the fastest and
  /// slowest is several-fold, so a machine that is unexpectedly slow is
  /// answered by this one string.
  static String variantName() {
    try {
      final name = lookupNativeFunction(
        () => openFaaccrackNativeLibrary()
            .lookupFunction<_StringNative, Pointer<Utf8> Function()>(
              'qunleashed_faaccrack_variant',
            ),
      )();
      return name.toDartString();
    } on NativeEngineUnavailable {
      return 'unavailable';
    }
  }
}

SeedResult _empty(SeedOutcome outcome) => (
  outcome: outcome,
  seed: null,
  lrkey: null,
  counter: null,
  frameHop: null,
  hopsUsed: null,
);

class _SeedPayload {
  const _SeedPayload({
    required this.mode,
    required this.fix,
    required this.hops,
    required this.threads,
    required this.channelAddress,
  });

  final int mode;
  final int fix;
  final Uint32List hops;
  final int threads;

  /// An address rather than a pointer: a Pointer cannot be sent to an isolate,
  /// and the memory it names is process-scoped so the address is enough.
  final int channelAddress;
}
