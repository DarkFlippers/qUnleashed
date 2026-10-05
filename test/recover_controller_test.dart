import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/mfkey32_api.dart';
import 'package:qunleashed/pages/tools/mifare/mfkey32_models.dart';
import 'package:qunleashed/pages/tools/mifare/mfkey32_recoverer.dart';
import 'package:qunleashed/pages/tools/mifare/nested_api.dart';
import 'package:qunleashed/pages/tools/mifare/existed_keys_storage.dart';
import 'package:qunleashed/pages/tools/mifare/hardnested_recoverer.dart';
import 'package:qunleashed/pages/tools/mifare/known_key_filter.dart';
import 'package:qunleashed/pages/tools/mifare/recover_controller.dart';
import 'package:qunleashed/pages/tools/mifare/cuid_dict_format.dart';
import 'package:qunleashed/pages/tools/mifare/nested_models.dart';
import 'package:qunleashed/pages/tools/mifare/nested_recoverer.dart';
import 'package:qunleashed/pages/tools/mifare/recover_models.dart';
import 'package:qunleashed/pages/tools/mifare/static_encrypted_recoverer.dart';

/// Which answer "Recover MIFARE Keys" gives before it cracks anything.
///
/// The controller takes all seven of its collaborators as parameters already —
/// the client, both device APIs and four recoverers — so it needed no seam.
/// It had no tests anyway, and this is the half a user meets first: four ways
/// a run can end before a single nonce is read, and they are four different
/// things to tell someone holding a Flipper.
///
/// The cracking itself is not here. The four recoverers are injected the same
/// way and want their own files; what is pinned here is the state machine
/// around them.
class FakeRecoverClient implements FlipperClient {
  bool connected = true;

  /// Raised by `runTask`'s body host - the one call the controller makes on
  /// the client before it reaches either API.
  @override
  bool get isConnected => connected;

  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  /// Every RPC the controller makes past the probe - the stat and the read -
  /// refuses. Enough for the cases here, which are all about a run that ends
  /// before any nonce is parsed.
  @override
  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
    bool retainFrames = true,
    bool interleavable = false,
    bool pipelined = true,
  }) async => throw StateError('the card is not on the reader');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeReaderApi implements MfKey32Api {
  FakeReaderApi({this.exists = false, this.probeThrows});

  bool exists;
  Object? probeThrows;

  /// How many times the run asked the device what it has.
  int probes = 0;

  @override
  bool get isBruteforceFileExist => exists;

  @override
  Future<void> checkBruteforceFileExist(FlipperClient client) async {
    probes++;
    if (probeThrows != null) throw probeThrows!;
  }

  @override
  Stream<bool> hasNotification() => const Stream.empty();
}

class FakeTagApi implements NestedApi {
  FakeTagApi({this.exists = false, this.probeThrows});

  bool exists;
  Object? probeThrows;

  @override
  Future<bool> nonceFileExists(FlipperClient client) async {
    if (probeThrows != null) throw probeThrows!;
    return exists;
  }
}

void main() {
  _unitAccountingGroup();
  _stopGroup();
  late FakeRecoverClient client;
  late FakeReaderApi reader;
  late FakeTagApi tag;

  RecoverController build() {
    final controller = RecoverController(
      client: client,
      mfApi: reader,
      nestedApi: tag,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  setUp(() {
    client = FakeRecoverClient();
    reader = FakeReaderApi();
    tag = FakeTagApi();
  });

  RecoverErrorType? errorOf(RecoverController c) =>
      c.state is RecoverError ? (c.state as RecoverError).errorType : null;

  test('starts out saying there is no Flipper', () {
    expect(errorOf(build()), RecoverErrorType.flipperConnection);
  });

  group('a run that cannot begin', () {
    test('says so when nothing is connected', () async {
      client.connected = false;

      final controller = build();
      await controller.start();

      expect(errorOf(controller), RecoverErrorType.flipperConnection);
      expect(controller.running, isFalse);
    });

    // A drop while the probe is in flight is a connection problem, not the
    // catch-all "recovery unavailable". The two send the user to different
    // places: one to their cable, the other to a bug report.
    test('reads a failed probe as a connection problem', () async {
      reader.probeThrows = StateError('link went away');

      final controller = build();
      await controller.start();

      expect(errorOf(controller), RecoverErrorType.flipperConnection);
    });

    test('reads a failed tag probe the same way', () async {
      tag.probeThrows = StateError('link went away');

      final controller = build();
      await controller.start();

      expect(errorOf(controller), RecoverErrorType.flipperConnection);
    });

    // Neither log on the card's Flipper means the user has not read a card
    // yet, which is a different sentence from anything having gone wrong.
    test(
      'says there is nothing to work from when neither log is there',
      () async {
        final controller = build();
        await controller.start();

        expect(errorOf(controller), RecoverErrorType.notFoundFile);
      },
    );

    // The log was confirmed to exist a moment earlier, so a read that fails
    // now is a read error. Proceeding as though the file were empty would put
    // every key it held under a success screen.
    test('is a read error when a log is there and will not come off', () async {
      reader.exists = true;

      final controller = build();
      await controller.start();

      expect(errorOf(controller), RecoverErrorType.readWrite);
    });

    test('and the same for the tag log', () async {
      tag.exists = true;

      final controller = build();
      await controller.start();

      expect(errorOf(controller), RecoverErrorType.readWrite);
    });
  });

  group('while a run is going', () {
    // Counted, not inferred from the end state: two runs that both fail the
    // same way leave the controller looking exactly like one that did.
    test('a second start does not start a second run', () async {
      reader.probeThrows = StateError('link went away');
      final controller = build();

      await Future.wait([controller.start(), controller.start()]);

      expect(reader.probes, 1);
      expect(controller.running, isFalse);
    });

    test('it is not running once it has ended', () async {
      final controller = build();

      await controller.start();

      expect(controller.running, isFalse);
    });
  });

  // A dictionary is tens of thousands of entries, and over BLE that is minutes
  // during which every other readout on the page holds still. The run that
  // produced the report behind this had two sector keys sharing a nonce, so the
  // cross-filter reduced nothing and the file was 1.64 MB.
  group('writing a candidate dictionary', () {
    const log =
        'Sec 3 key A cuid e37aa759 nt0 db7df8ae ks0 77ff617e par0 1111 dist 0\n'
        'Sec 3 key B cuid e37aa759 nt0 db7df8ae ks0 77ff617e par0 1111 dist 0\n';

    late FakeUploadClient upload;

    RecoverController buildWithDicts(List<StaticCandidateDict> dicts) {
      final controller = RecoverController(
        client: upload,
        mfApi: reader,
        nestedApi: tag,
        staticRecoverer: FakeStaticRecoverer(dicts),
      );
      addTearDown(controller.dispose);
      return controller;
    }

    setUp(() {
      upload = FakeUploadClient(log);
      tag.exists = true;
      // ProgressThrottle's floor is wall-clock. With no delay a run finishes
      // inside one window and the only report that survives is the final 1.0,
      // which every wiring passes - including a wrong one.
      upload.frameDelay = const Duration(milliseconds: 60);
    });

    test('says how far along it is', () async {
      final seen = <double>[];
      final controller = buildWithDicts([dictOf(0xe37aa759, 400)]);
      controller.addListener(() {
        final state = controller.state;
        if (state is RecoverUploading && state.progress != null) {
          seen.add(state.progress!);
        }
      });

      await controller.start();

      expect(
        seen.any((p) => p > 0 && p < 1),
        isTrue,
        reason: 'a report only at the end is the frozen readout, not a fix',
      );
      expect(seen.last, 1.0);
    });

    // Scaled across every card, so a second dictionary does not send the bar
    // back to zero. Both halves of the run report against one denominator.
    test('counts both cards as one upload', () async {
      final seen = <double>[];
      final controller = buildWithDicts([
        dictOf(0xe37aa759, 400),
        dictOf(0x11223344, 400),
      ]);
      controller.addListener(() {
        final state = controller.state;
        if (state is RecoverUploading && state.progress != null) {
          seen.add(state.progress!);
        }
      });

      await controller.start();

      expect(seen.any((p) => p > 0 && p < 1), isTrue);
      expect(
        seen,
        orderedEquals(List<double>.from(seen)..sort()),
        reason:
            'a denominator per card sends the bar to 1.0 on the first and '
            'back down on the second. Within a card it may legitimately fall - '
            'a link drop restarts that upload - but nothing drops here.',
      );
    });

    // A card counted in the denominator and never in the numerator leaves the
    // bar short for the rest of the run, and the >= 1.0 shortcut that would
    // have corrected it never fires.
    test('a card whose write fails still counts toward the whole', () async {
      final seen = <double>[];
      upload.refuseWrite = (p) => p.contains('e37aa759');
      final controller = buildWithDicts([
        dictOf(0xe37aa759, 400),
        dictOf(0x11223344, 400),
      ]);
      controller.addListener(() {
        final state = controller.state;
        if (state is RecoverUploading && state.progress != null) {
          seen.add(state.progress!);
        }
      });

      await controller.start();

      expect(seen.last, 1.0, reason: 'the surviving card has to fill the bar');
    });

    // Stop is a pop. Without isCancelled the write runs to completion against a
    // device the user walked away from, reporting to a page that is gone.
    test('stops when the page does', () async {
      // Built without the teardown the others use: this one disposes itself
      // mid-write, and a second dispose throws.
      final controller = RecoverController(
        client: upload,
        mfApi: reader,
        nestedApi: tag,
        staticRecoverer: FakeStaticRecoverer([dictOf(0xe37aa759, 4000)]),
      );
      upload.onFrameSent = (frames) {
        if (frames == 2) controller.dispose();
      };

      await controller.start();

      expect(
        upload.framesSent,
        lessThan(10),
        reason: 'the write should end soon after the page went away',
      );
    });
  });

  // Cracking a key the user already has is the largest avoidable cost in a
  // run: the nonce logs are never cleared, so every run re-attacks every nonce
  // ever collected. The expensive paths must not be entered for a key the
  // dictionary already answers.
  group('a key the dictionary already holds', () {
    const log =
        'Sec 3 key A cuid e37aa759 nt0 db7df8ae ks0 77ff617e par0 1111 dist 0\n';
    late FakeUploadClient upload;

    setUp(() {
      upload = FakeUploadClient(log);
      tag.exists = true;
    });

    test('is recorded without generating any candidates', () async {
      final known = BigInt.parse('A0A1A2A3A4A5', radix: 16);
      final recoverer = FakeStaticRecoverer([dictOf(0xe37aa759, 400)]);
      final controller = RecoverController(
        client: upload,
        mfApi: reader,
        nestedApi: tag,
        staticRecoverer: recoverer,
        knownKeyFilter: (_) => FakeKnownKeys(nested: known),
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(
        recoverer.askedAbout,
        0,
        reason: 'the generator must not be asked about a key already known',
      );
      expect(
        controller.entries.any((e) => e.key == 'A0A1A2A3A4A5'),
        isTrue,
        reason: 'the key still has to be reported, just not re-derived',
      );
      expect(controller.state, isA<RecoverSaved>());
      expect((controller.state as RecoverSaved).skippedKnown, 1);
    });

    test('still runs the attack when the dictionary does not answer', () async {
      final recoverer = FakeStaticRecoverer([dictOf(0xe37aa759, 400)]);
      final controller = RecoverController(
        client: upload,
        mfApi: reader,
        nestedApi: tag,
        staticRecoverer: recoverer,
        knownKeyFilter: (_) => FakeKnownKeys(),
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(recoverer.askedAbout, 1);
      expect((controller.state as RecoverSaved).skippedKnown, 0);
    });
  });

  // A failed save is the one error whose work is still in memory. Retrying the
  // whole run would re-download both logs and re-run every attack - a
  // hardnested one among them - to redo a write of a few kilobytes.
  group('retrying a failed save', () {
    const log =
        'Sec 3 key A cuid e37aa759 nt0 db7df8ae ks0 77ff617e par0 1111 dist 0\n';

    test('writes again without redoing the run', () async {
      final upload = FakeUploadClient(log)
        ..refuseWrite = (p) => p == flipperDictUserPath;
      final controller = RecoverController(
        client: upload,
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        staticRecoverer: FakeStaticRecoverer([dictOf(0xe37aa759, 50)]),
        // A key for the dictionary, so the write this is all about happens.
        knownKeyFilter: (_) =>
            FakeKnownKeys(nested: BigInt.parse('A0A1A2A3A4A5', radix: 16)),
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(
        errorOf(controller),
        RecoverErrorType.saveFailed,
        reason: 'told apart from a plain storage error, because work was done',
      );
      final readsBefore = upload.reads;
      final entriesBefore = controller.entries.length;

      upload.refuseWrite = null;
      await controller.retrySave();

      expect(controller.state, isA<RecoverSaved>());
      expect(
        upload.reads,
        readsBefore,
        reason: 'the logs and dictionaries must not be fetched a second time',
      );
      expect(
        controller.entries,
        hasLength(entriesBefore),
        reason: 'and the results already on screen must survive',
      );
    });

    // The footnote under that error points at the copy, and it is the
    // difference between "tap Retry" and "stop and check the card".
    test('reports whether the previous keys were copied first', () async {
      final upload = FakeUploadClient(log)
        ..refuseWrite = (p) => p == flipperDictUserPath;
      final controller = RecoverController(
        client: upload,
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        staticRecoverer: FakeStaticRecoverer([dictOf(0xe37aa759, 50)]),
        knownKeyFilter: (_) =>
            FakeKnownKeys(nested: BigInt.parse('A0A1A2A3A4A5', radix: 16)),
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(errorOf(controller), RecoverErrorType.saveFailed);
      expect(controller.dictBackupKept, isTrue);
      expect(controller.dictBackupFailed, isFalse);
    });
  });

  // The page can be popped while a run is still in flight - Stop is a pop -
  // and a disposed ChangeNotifier that is notified throws.
  test('a run that outlives the page does not notify it', () async {
    final controller = RecoverController(
      client: client,
      mfApi: reader,
      nestedApi: tag,
    );
    final run = controller.start();
    controller.dispose();

    await expectLater(run, completes);
  });
}

/// Serves a `.nested.log` and accepts a dictionary write, so a run reaches the
/// one step whose duration a user cannot guess from the work in front of them.
///
/// `storageWriteChunked` is an extension on `FlipperClient`, so declaring one
/// here would do nothing — the real body runs either way. What it goes through
/// is `callRpcFramesMulti`, and that is what this fakes.
class FakeUploadClient extends FakeRecoverClient {
  FakeUploadClient(this.log, {this.byPath = const {}});

  final String log;

  /// Per-path overrides for the device read, for a test that needs the two logs
  /// to differ. Without it every read answers [log], which is fine while only
  /// one log matters but makes a reader nonce impossible to serve - the nested
  /// parser and the mfkey32 parser do not accept each other's format.
  final Map<String, String> byPath;

  /// Frames the real `storageWriteChunked` handed down, counted so a run that
  /// stopped early can be told from one that finished.
  int framesSent = 0;

  /// How many times the logs and dictionaries were read off the device. A retry
  /// that redid the run would read them again.
  int reads = 0;

  /// Runs after each frame, for a test that wants to pull the page away
  /// mid-upload. Not `onFrame`: `callRpcFrames` takes a parameter by that name
  /// and would shadow it.
  void Function(int framesSoFar)? onFrameSent;

  /// Refuses the writes this answers true for. A predicate rather than a cuid
  /// because the user dictionary's path carries none, and that is the write a
  /// scoped retry has to be able to fail.
  bool Function(String path)? refuseWrite;

  /// Slows each frame so the reports clear `ProgressThrottle`'s 150 ms floor.
  /// Without it a run finishes inside one window and the only report that
  /// survives is the final 1.0 - which every wiring passes, including a wrong
  /// one.
  Duration frameDelay = Duration.zero;

  @override
  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
    bool retainFrames = true,
    bool interleavable = false,
    bool pipelined = true,
  }) async {
    if (request.hasStorageReadRequest()) {
      reads++;
      final body = byPath[request.storageReadRequest.path] ?? log;
      final frame = Main()
        ..storageReadResponse = (ReadResponse()
          ..file = (File()..data = utf8.encode(body)));
      onFrame?.call(frame);
      return [frame];
    }
    if (request.hasSystemPingRequest()) {
      // storageWriteChunked paces a non-BLE transport with a ping every 16
      // frames. The dictionaries here are shorter than that, but a future one
      // would trip it and fail as a storage error rather than as itself.
      return [Main()..systemPingResponse = PingResponse()];
    }
    // Everything else - the stat ahead of the download, the delete behind a
    // cancelled write - is best-effort in the caller and refuses here.
    throw StateError('not served');
  }

  /// `storageWriteChunked` reads `transport` for its chunk size. Answered null
  /// here - which gives it the BLE chunk size, the transport these reports
  /// exist for - rather than letting the inherited noSuchMethod throw. Named
  /// through noSuchMethod because `Transport` is not exported from the package
  /// facade this file imports.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #transport) return null;
    return super.noSuchMethod(invocation);
  }

  @override
  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame)) body, {
    Duration timeout = const Duration(seconds: 60),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
  }) async {
    var refuse = false;
    await body((frame) async {
      if (refuseWrite != null &&
          frame.hasStorageWriteRequest() &&
          refuseWrite!(frame.storageWriteRequest.path)) {
        refuse = true;
        return;
      }
      if (frameDelay > Duration.zero) await Future<void>.delayed(frameDelay);
      framesSent++;
      onFrameSent?.call(framesSent);
    });
    if (refuse) throw StateError('the card refused the write');
    return const [];
  }
}

/// Answers for whichever keys the test says the dictionary already holds.
class FakeKnownKeys implements KnownKeyFilter {
  FakeKnownKeys({this.nested, this.reader});

  final BigInt? nested;
  final BigInt? reader;
  int disposed = 0;

  @override
  BigInt? nestedMatch({required int cuid, required int nt, required int ks}) =>
      nested;

  @override
  BigInt? readerMatch({
    required int uid,
    required int nt,
    required int nr,
    required int ar,
  }) => reader;

  @override
  void dispose() => disposed++;
}

class FakeStaticRecoverer implements StaticEncryptedRecoverer {
  FakeStaticRecoverer(this.dicts, {this.throws});

  final List<StaticCandidateDict> dicts;

  /// Raised instead of answering, for the run-level failure path.
  final Object? throws;

  /// How many nonces the generator was actually asked about. Zero is the claim
  /// the dedup makes: the expensive path was never entered.
  int askedAbout = 0;

  @override
  Future<List<StaticCandidateDict>> buildCandidateDicts(
    List<NestedNonce> nonces,
  ) async {
    askedAbout += nonces.length;
    if (throws != null) throw throws!;
    return dicts;
  }
}

/// Reports [fractions] in order and then finds nothing, so a test can watch
/// both what reaches the page while the attack runs and what it is left showing
/// once the group is over. A repeated value stands in for two polls of the
/// native channel that read the same permille.
class FakeHardnested implements HardnestedRecoverer {
  FakeHardnested(this.fractions);

  final List<double> fractions;

  @override
  Future<HardnestedResult> recoverKey({
    required int cuid,
    required List<int> ntEnc,
    required List<int> parEnc,
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  }) async {
    fractions.forEach(onProgress ?? (_) {});
    return (key: null, outcome: HardnestedOutcome.noKey);
  }
}

/// Answers every weak-nested nonce with [key], so a test can get a key into the
/// run before the step it means to interrupt.
class FakeNested implements NestedRecoverer {
  FakeNested(this.key);

  final BigInt key;

  @override
  Future<BigInt?> recoverKey(NestedNonce nonce) async => key;
}

/// Calls [onStarted] as the attack begins and then reports [outcome], so a test
/// can stop the run from inside the step that is running.
class FakeInterruptingHardnested implements HardnestedRecoverer {
  FakeInterruptingHardnested({required this.onStarted});

  final void Function() onStarted;
  int calls = 0;

  /// What `isCancelled` answered when the attack asked, which is the only way
  /// to see that callback bound to the right flag: a fake that reported
  /// `stopped` regardless would pass identically with it bound to `_disposed`.
  bool? sawCancelled;

  @override
  Future<HardnestedResult> recoverKey({
    required int cuid,
    required List<int> ntEnc,
    required List<int> parEnc,
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  }) async {
    calls++;
    onProgress?.call(0.47);
    onStarted();
    // Polled after, not before: the callback above is what asks the run to end,
    // and a real engine would see it at its next bucket.
    sawCancelled = isCancelled?.call() ?? false;
    return (
      key: null,
      outcome: sawCancelled!
          ? HardnestedOutcome.stopped
          : HardnestedOutcome.noKey,
    );
  }
}

/// Answers with [key] and calls [onFirstCall] once, so a test can stop the run
/// from inside the first nonce of a sweep and then count how many more the
/// sweep went on to attack.
class FakeStoppingNested implements NestedRecoverer {
  FakeStoppingNested({required this.key, required this.onFirstCall});

  final BigInt key;
  final void Function() onFirstCall;
  int calls = 0;

  @override
  Future<BigInt?> recoverKey(NestedNonce nonce) async {
    if (++calls == 1) onFirstCall();
    return key;
  }
}

/// The reader-sweep counterpart of [FakeStoppingNested].
class FakeStoppingMfKey32 implements MfKey32Recoverer {
  FakeStoppingMfKey32({required this.key, required this.onFirstCall});

  final BigInt key;
  final void Function() onFirstCall;
  int calls = 0;

  @override
  Future<BigInt?> bruteforceKey(MfKey32Nonce nonce) async {
    if (++calls == 1) onFirstCall();
    return key;
  }
}

/// Parks inside the attack until [release] completes, so a test can act on the
/// controller while a run is genuinely in flight and nothing else is emitting.
///
/// The two things that need it both turn on *when* something happens rather
/// than what: that `stop()` notifies by itself (any later emission would mask a
/// missing notify) and that `stop()` is inert on a disposed controller (which
/// needs `_running` still true, or the guard under test is never reached).
class FakeParkedHardnested implements HardnestedRecoverer {
  final release = Completer<void>();
  final parked = Completer<void>();

  @override
  Future<HardnestedResult> recoverKey({
    required int cuid,
    required List<int> ntEnc,
    required List<int> parEnc,
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!parked.isCompleted) parked.complete();
    await release.future;
    return (key: null, outcome: HardnestedOutcome.stopped);
  }
}

/// A dictionary of [entries] candidates for one sector key.
StaticCandidateDict dictOf(int cuid, int entries) {
  final builder = CuidDictBuilder()
    ..add(
      sector: 3,
      isKeyA: true,
      keys: Uint64List.fromList(List.generate(entries, (i) => i + 1)),
    );
  return StaticCandidateDict.built(cuid, builder.build());
}

/// What Stop does, and the one thing it must not do.
///
/// Before it existed, the engine's cancellation was reachable only by popping
/// the page - which runs dispose() and abandons every key the run had already
/// recovered. So the whole of Stop is the difference between the two: both end
/// the run early, and exactly one of them keeps the keys. A `_cancelled` that
/// drifted into being another name for `_disposed` would pass every test about
/// stopping and silently undo the reason for it.
void _stopGroup() {
  group('Stop', () {
    // One weak pair (recovered before the hardnested step) and two hardnested
    // groups, so there is both something to save and a step left to skip.
    const log =
        'Sec 1 key A cuid e37aa759 nt0 aaaaaaaa ks0 11111111 par0 1111 '
        'nt1 bbbbbbbb ks1 22222222 par1 1111 dist 0\n'
        'Sec 5 key A cuid e37aa759 nt0 db7df8ae ks0 77ff617e par0 1111\n'
        'Sec 6 key A cuid e37aa759 nt0 aabbccdd ks0 11223344 par0 1111\n';
    final recovered = BigInt.parse('A0A1A2A3A4A5', radix: 16);

    ({
      RecoverController controller,
      FakeUploadClient client,
      FakeInterruptingHardnested hard,
    })
    build({required void Function(RecoverController) onAttackStarted}) {
      final client = FakeUploadClient(log);
      late final RecoverController controller;
      final hard = FakeInterruptingHardnested(
        onStarted: () => onAttackStarted(controller),
      );
      controller = RecoverController(
        client: client,
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        nestedRecoverer: FakeNested(recovered),
        hardnestedRecoverer: hard,
        knownKeyFilter: (_) => FakeKnownKeys(),
      );
      return (controller: controller, client: client, hard: hard);
    }

    test('ends the run early but still writes what it found', () async {
      final parts = build(onAttackStarted: (c) => c.stop());
      addTearDown(parts.controller.dispose);

      await parts.controller.start();

      expect(
        parts.hard.calls,
        1,
        reason: 'the second hardnested group must not be started',
      );
      expect(
        parts.controller.state,
        isA<RecoverSaved>(),
        reason: 'a stopped run still reports, rather than looking like a hang',
      );
      expect(
        (parts.controller.state as RecoverSaved).keys,
        contains('A0A1A2A3A4A5'),
        reason: 'the key found before Stop is the thing being kept',
      );
      expect(
        parts.client.framesSent,
        greaterThan(0),
        reason: 'and it reached the card',
      );
      expect(
        (parts.controller.state as RecoverSaved).stopped,
        isTrue,
        reason: 'and the summary says so, or it reads as a complete run',
      );
    });

    // The other half of the contract. Same run, same moment, but the page goes
    // instead - and then the dictionary write must not happen at all, because
    // it is a read-modify-write over a client the page no longer owns.
    test('backing out of the page writes nothing', () async {
      final parts = build(onAttackStarted: (c) => c.dispose());

      await parts.controller.start();

      expect(parts.hard.calls, 1);
      // The precondition, asserted because without it this test's only claim is
      // a negative one and it stops testing anything. A mutation that stopped
      // registering keys at all makes `added` empty, upload() short-circuits
      // before any write, and framesSent is 0 for a reason with nothing to do
      // with dispose() - which it did, and this test passed.
      expect(
        parts.controller.entries.any((e) => e.key == 'A0A1A2A3A4A5'),
        isTrue,
        reason: 'a key has to have been pending when the page went',
      );
      expect(
        parts.client.framesSent,
        0,
        reason: 'a disposed run must not touch the shared client',
      );
    });

    test('stop() before a run has started does nothing', () {
      final parts = build(onAttackStarted: (_) {});
      addTearDown(parts.controller.dispose);

      parts.controller.stop();

      expect(parts.controller.cancelled, isFalse);
    });

    /// Starts a run and returns once it is parked inside the attack, so the
    /// test can act with nothing else emitting.
    ({
      RecoverController controller,
      FakeParkedHardnested hard,
      Future<void> run,
    })
    parked() {
      final hard = FakeParkedHardnested();
      final controller = RecoverController(
        client: FakeUploadClient(log),
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        nestedRecoverer: FakeNested(recovered),
        hardnestedRecoverer: hard,
        knownKeyFilter: (_) => FakeKnownKeys(),
      );
      return (controller: controller, hard: hard, run: controller.start());
    }

    // Reachable because the confirmation dialog is awaited: the page can be
    // popped while it is open, and the handler then calls stop() on a disposed
    // controller that is still running. notifyListeners() asserts in that
    // state, so without the guard this is a debug-build crash out of an async
    // button callback - which lands in the log as [uncaught] with nothing
    // naming the operation.
    test('stop() after the page has gone does nothing', () async {
      final p = parked();
      await p.hard.parked.future;
      expect(p.controller.running, isTrue, reason: 'the guard needs this true');

      p.controller.dispose();

      expect(p.controller.stop, returnsNormally);
      expect(p.controller.cancelled, isFalse);
      p.hard.release.complete();
      await p.run;
    });

    // The flag exists to be shown, and nothing else shows it: an attack notices
    // a Stop only at its next bounded check, and a hardnested bucket can be a
    // long way off. Without this notify the button stays enabled through the
    // whole of the wait it was pressed to end.
    //
    // Asserted while the run is parked, because any later emission would carry
    // the flag to the page anyway and mask a missing notify - which it did.
    test('stop() tells the page by itself', () async {
      final p = parked();
      addTearDown(p.controller.dispose);
      await p.hard.parked.future;
      var fires = 0;
      p.controller.addListener(() => fires++);

      p.controller.stop();

      expect(fires, 1, reason: 'stop() has to notify on its own');
      expect(p.controller.cancelled, isTrue);
      p.hard.release.complete();
      await p.run;
    });

    // The readout must not keep showing the figure of the attack that Stop
    // ended. Asserted on sequence position rather than a count: _emit fires on
    // every call and _tick emits the same value, so any count is fragile.
    test('the stopped attack leaves no figure on screen', () async {
      final seen = <RecoverState>[];
      final parts = build(onAttackStarted: (c) => c.stop());
      addTearDown(parts.controller.dispose);
      parts.controller.addListener(() => seen.add(parts.controller.state));

      await parts.controller.start();

      expect(
        seen.whereType<RecoverCalculating>().any((s) => s.fraction == 0.47),
        isTrue,
        reason: 'the fixture has to have put a figure up to begin with',
      );
      final uploadAt = seen.indexWhere((s) => s is RecoverUploading);
      expect(uploadAt, greaterThan(0), reason: 'the save has to be reached');
      final lastPhase = seen
          .take(uploadAt)
          .whereType<RecoverCalculating>()
          .last;
      expect(lastPhase.fraction, isNull);
      expect(lastPhase.label, isNull);
    });

    // The sector the user watched for however long before pressing Stop. It
    // used to be dropped, which reads as though it was never attempted.
    test('the stopped sector is still reported', () async {
      final parts = build(onAttackStarted: (c) => c.stop());
      addTearDown(parts.controller.dispose);

      await parts.controller.start();

      expect(
        parts.hard.sawCancelled,
        isTrue,
        reason: 'the attack has to see the Stop through its own isCancelled',
      );
      final row = parts.controller.entries.firstWhere(
        (e) => e.kind == RecoverKind.hardnested,
      );
      expect(row.sectorName, '5');
      expect(row.key, isNull);
      expect(row.note, isNotNull);
    });

    // Every attack has its own Stop check, and until these existed only the
    // hardnested one was pinned - each of the others could be reverted to
    // `_disposed` with the whole suite still green. They matter because of this
    // controller's own premise: the nonce logs are never cleared, so a mature
    // run re-attacks every nonce ever collected. A reader sweep is the longest
    // serial stretch of such a run.
    test('a Stop during the reader sweep ends it', () async {
      const readerLog =
          'Sec 1 key A cuid 11111111 nt0 11111111 nr0 11111111 ar0 11111111 '
          'nt1 22222222 nr1 22222222 ar1 22222222\n'
          'Sec 2 key A cuid 11111111 nt0 33333333 nr0 33333333 ar0 33333333 '
          'nt1 44444444 nr1 44444444 ar1 44444444\n'
          'Sec 3 key A cuid 11111111 nt0 55555555 nr0 55555555 ar0 55555555 '
          'nt1 66666666 nr1 66666666 ar1 66666666\n';
      final client = FakeUploadClient('', byPath: {pathNonceLog: readerLog});
      late final RecoverController controller;
      final reader = FakeStoppingMfKey32(
        key: recovered,
        onFirstCall: () => controller.stop(),
      );
      controller = RecoverController(
        client: client,
        mfApi: FakeReaderApi(exists: true),
        nestedApi: FakeTagApi(exists: false),
        mfRecoverer: reader,
        knownKeyFilter: (_) => FakeKnownKeys(),
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(
        reader.calls,
        1,
        reason: 'the sweep must not run on through the remaining nonces',
      );
      expect(controller.state, isA<RecoverSaved>());
      expect(
        (controller.state as RecoverSaved).keys,
        contains('A0A1A2A3A4A5'),
        reason: 'the key recovered before the Stop is still kept',
      );
    });

    // The weak path is batched four at a time, so its guard is at the batch
    // boundary - asserting exactly four pins that, rather than just "fewer
    // than all of them".
    test('a Stop during the weak sweep ends it at the batch boundary', () async {
      final pairs = [
        for (var sector = 1; sector <= 8; sector++)
          'Sec $sector key A cuid e37aa759 nt0 aaaaaaaa ks0 11111111 par0 1111 '
              'nt1 bbbbbbbb ks1 22222222 par1 1111 dist 0',
      ].join('\n');
      late final RecoverController controller;
      final nested = FakeStoppingNested(
        key: recovered,
        onFirstCall: () => controller.stop(),
      );
      controller = RecoverController(
        client: FakeUploadClient('$pairs\n'),
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        nestedRecoverer: nested,
        knownKeyFilter: (_) => FakeKnownKeys(),
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(
        nested.calls,
        4,
        reason: 'the batch in flight finishes; the next one must not start',
      );
    });

    // The step a user is most likely to interrupt: the write's own comment
    // calls it minutes over BLE, and it is the one with a percentage on screen.
    // A cancelled upload used to return without a row, so the card the user had
    // watched vanished from the summary - and with _wroteCandidates left false,
    // so did the "verify these on the device" footnote.
    test(
      'a Stop during the candidate upload says which card lost out',
      () async {
        const staticLog =
            'Sec 3 key A cuid e37aa759 nt0 db7df8ae ks0 77ff617e par0 1111 '
            'dist 0\n';
        late final RecoverController controller;
        final client = FakeUploadClient(staticLog)
          ..frameDelay = const Duration(milliseconds: 1);
        client.onFrameSent = (frames) {
          if (frames == 1) controller.stop();
        };
        controller = RecoverController(
          client: client,
          mfApi: FakeReaderApi(),
          nestedApi: FakeTagApi(exists: true),
          staticRecoverer: FakeStaticRecoverer([dictOf(0xe37aa759, 4000)]),
          knownKeyFilter: (_) => FakeKnownKeys(),
        );
        addTearDown(controller.dispose);

        await controller.start();

        expect(controller.state, isA<RecoverSaved>());
        final row = controller.entries.firstWhere(
          (e) => e.kind == RecoverKind.staticEncrypted,
        );
        expect(
          row.note,
          isNotNull,
          reason: 'the interrupted card has to be named, not dropped',
        );
        expect(
          row.candidateCount,
          isNull,
          reason: 'the file it would point at was deleted on the way out',
        );
      },
    );

    // The loop's own guard, which the test above cannot reach: there the
    // cancelled write throws and the catch returns before the next iteration
    // ever starts.
    //
    // Reaching it needs a card that finishes *without* a write, so the loop
    // actually comes round again - a dictionary whose generation failed does
    // that. The Stop then lands on the second card's guard, and that card must
    // not be uploaded at all: a row saying "stopped before the candidates were
    // saved" would claim it was attempted.
    test('a Stop between cards does not start the next one', () async {
      const twoStatic =
          'Sec 3 key A cuid e37aa759 nt0 db7df8ae ks0 77ff617e par0 1111 '
          'dist 0\n'
          'Sec 4 key A cuid 11223344 nt0 aabbccdd ks0 11223344 par0 1111 '
          'dist 0\n';
      final client = FakeUploadClient(twoStatic);
      final controller = RecoverController(
        client: client,
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        staticRecoverer: FakeStaticRecoverer([
          StaticCandidateDict.failed(0xe37aa759, StateError('no candidates')),
          dictOf(0x11223344, 20),
        ]),
        knownKeyFilter: (_) => FakeKnownKeys(),
      );
      addTearDown(controller.dispose);
      // _tick runs at the top of each iteration, so doneUnits reaching 1 is the
      // first card starting. That card writes nothing, so the Stop asked for
      // here is still unspent when the loop comes round to the second.
      controller.addListener(() {
        if (controller.doneUnits == 1) controller.stop();
      });

      await controller.start();

      expect(
        client.framesSent,
        0,
        reason: 'the second dictionary must never be sent',
      );
      expect(
        controller.entries
            .where((e) => e.kind == RecoverKind.staticEncrypted)
            .length,
        1,
        reason: 'and it gets no row, because it was not attempted',
      );
    });

    // The whole static-encrypted batch is skipped by a guard of its own, which
    // runs after the hardnested groups. Without a fixture carrying both kinds
    // it was unreachable: a Stop during hardnested would still fall through and
    // generate every candidate dictionary - minutes of work the user had just
    // asked to end, and a device write after it.
    test('a Stop during hardnested skips the static batch', () async {
      const mixed =
          'Sec 5 key A cuid e37aa759 nt0 db7df8ae ks0 77ff617e par0 1111\n'
          'Sec 3 key A cuid 11223344 nt0 aabbccdd ks0 11223344 par0 1111 '
          'dist 0\n';
      late final RecoverController controller;
      final staticRecoverer = FakeStaticRecoverer([dictOf(0x11223344, 20)]);
      final hard = FakeInterruptingHardnested(
        onStarted: () => controller.stop(),
      );
      final client = FakeUploadClient(mixed);
      controller = RecoverController(
        client: client,
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        hardnestedRecoverer: hard,
        staticRecoverer: staticRecoverer,
        knownKeyFilter: (_) => FakeKnownKeys(),
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(hard.calls, 1, reason: 'the fixture has to reach hardnested');
      expect(
        staticRecoverer.askedAbout,
        0,
        reason: 'candidate generation must not be entered at all',
      );
      expect(
        client.framesSent,
        0,
        reason: 'and nothing is written to the card',
      );
    });

    // Stop is offered while there is something to stop, and withdrawn for the
    // one step it must not interrupt. `_running` stays true through the
    // dictionary write, and retrySave sets it for an operation that is nothing
    // but that write - so a button gated on `running` alone would sit over the
    // save and do nothing when pressed, which is the failure offering a Stop
    // is meant to avoid.
    test(
      'Stop is offered during an attack, and not once the run has ended',
      () async {
        final p = parked();
        addTearDown(p.controller.dispose);
        await p.hard.parked.future;

        expect(
          p.controller.canStop,
          isTrue,
          reason: 'an attack in flight is exactly what Stop is for',
        );

        p.hard.release.complete();
        await p.run;

        expect(
          p.controller.canStop,
          isFalse,
          reason: 'and nothing is left to stop once the run has ended',
        );
      },
    );

    test('Stop is not offered while the dictionary is being written', () async {
      // One weak pair and nothing else: the only device write this run makes is
      // the user dictionary at the end, so a frame hook can only fire inside
      // the save. With a static card in the fixture it would also fire during a
      // candidate upload, where Stop *should* still be on offer.
      const weakOnly =
          'Sec 1 key A cuid e37aa759 nt0 aaaaaaaa ks0 11111111 par0 1111 '
          'nt1 bbbbbbbb ks1 22222222 par1 1111 dist 0';
      bool? duringSave;
      final client = FakeUploadClient(weakOnly);
      final controller = RecoverController(
        client: client,
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        nestedRecoverer: FakeNested(recovered),
        knownKeyFilter: (_) => FakeKnownKeys(),
      );
      addTearDown(controller.dispose);
      client.onFrameSent = (_) => duringSave ??= controller.canStop;

      await controller.start();

      expect(
        client.framesSent,
        greaterThan(0),
        reason: 'the fixture has to actually reach a write',
      );
      expect(duringSave, isFalse);

      // The latch has to be released, and this is where that shows: _saving is
      // an instance field, so one left true would withdraw Stop for the rest of
      // the page's life - every later run offering a button that never appears.
      final offered = <bool>[];
      controller.addListener(() => offered.add(controller.canStop));

      await controller.start();

      expect(
        offered,
        contains(true),
        reason: 'a second run has to offer Stop again',
      );
      expect(
        offered.last,
        isFalse,
        reason: 'and withdraw it once that run has finished',
      );
    });

    // The flag is per-run. A Stop left set would end the next run before it
    // reached its first attack, with nothing on screen saying why.
    test('a new run is not already cancelled', () async {
      final parts = build(onAttackStarted: (c) => c.stop());
      addTearDown(parts.controller.dispose);

      await parts.controller.start();
      expect(parts.controller.cancelled, isTrue);

      await parts.controller.start();
      expect(
        parts.hard.calls,
        greaterThan(1),
        reason: 'the second run has to actually attack',
      );
    });
  });
}

/// The readout's own arithmetic. Nothing asserted this, and two bugs lived
/// through it during development: units planned per card but ticked once for
/// the batch, and keys found in the dictionary ticking a counter sized without
/// them. Both leave the bar permanently short of its own total.
void _unitAccountingGroup() {
  group('the progress counter adds up', () {
    const twoCards =
        'Sec 3 key A cuid e37aa759 nt0 db7df8ae ks0 77ff617e par0 1111 dist 0\n'
        'Sec 3 key B cuid e37aa759 nt0 db7df8ae ks0 77ff617e par0 1111 dist 0\n'
        'Sec 4 key A cuid 11223344 nt0 aabbccdd ks0 11223344 par0 1111 dist 0\n';

    test('every planned unit is finished by the end of a run', () async {
      final upload = FakeUploadClient(twoCards);
      final controller = RecoverController(
        client: upload,
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        staticRecoverer: FakeStaticRecoverer([
          dictOf(0xe37aa759, 50),
          dictOf(0x11223344, 50),
        ]),
        knownKeyFilter: (_) => FakeKnownKeys(),
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.totalUnits, 2, reason: 'two cards, two units');
      expect(controller.doneUnits, controller.totalUnits);
    });

    // A key answered by the dictionary was removed from the plan, so it must
    // not advance the counter either.
    test('a key skipped as known does not advance the counter', () async {
      final upload = FakeUploadClient(twoCards);
      final controller = RecoverController(
        client: upload,
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        staticRecoverer: FakeStaticRecoverer([dictOf(0xe37aa759, 50)]),
        knownKeyFilter: (_) =>
            FakeKnownKeys(nested: BigInt.parse('A0A1A2A3A4A5', radix: 16)),
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.doneUnits, controller.totalUnits);
    });

    // The bug the collapsed model exists for: a hardnested group that ended at
    // 47% used to sit there through the next group's table decompression,
    // which reports nothing at all.
    test('a fraction does not survive the group that produced it', () async {
      // Two hardnested groups: single-sample lines with no `dist`, which is
      // what separates them from static-encrypted.
      const hardLog =
          'Sec 5 key A cuid e37aa759 nt0 db7df8ae ks0 77ff617e par0 1111\n'
          'Sec 6 key A cuid e37aa759 nt0 aabbccdd ks0 11223344 par0 1111\n';
      final seen = <RecoverCalculating>[];
      final controller = RecoverController(
        client: FakeUploadClient(hardLog),
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        hardnestedRecoverer: FakeHardnested([0.47]),
        knownKeyFilter: (_) => FakeKnownKeys(),
      );
      addTearDown(controller.dispose);
      controller.addListener(() {
        final state = controller.state;
        if (state is RecoverCalculating) seen.add(state);
      });

      await controller.start();

      expect(
        seen.any((s) => s.fraction == 0.47),
        isTrue,
        reason: 'the attack has to report while it runs',
      );
      expect(
        seen.last.fraction,
        isNull,
        reason: 'and the figure must not outlive the group it measured',
      );
    });

    // The native channel is polled on a timer, so most polls read the permille
    // the last one already reported. Rebuilding on those would be a rebuild
    // every 500 ms for hours showing the same number.
    test('a poll that reads the same figure twice rebuilds once', () async {
      const hardLog =
          'Sec 5 key A cuid e37aa759 nt0 db7df8ae ks0 77ff617e par0 1111\n';
      final seen = <double?>[];
      final controller = RecoverController(
        client: FakeUploadClient(hardLog),
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        hardnestedRecoverer: FakeHardnested([0.47, 0.47, 0.61]),
        knownKeyFilter: (_) => FakeKnownKeys(),
      );
      addTearDown(controller.dispose);
      controller.addListener(() {
        final state = controller.state;
        if (state is RecoverCalculating) seen.add(state.fraction);
      });

      await controller.start();

      expect(
        seen.where((f) => f == 0.47),
        hasLength(1),
        reason: 'the repeated poll must not reach the page a second time',
      );
      expect(
        seen.where((f) => f == 0.61),
        hasLength(1),
        reason: 'and a figure that did change still has to',
      );
    });

    // A phase that can name itself must also stop naming itself. A state per
    // phase used to leave its own last reading up after the phase ended - a
    // hardnested group that finished at 47% sat there through the next group's
    // table decompression, which reports nothing.
    test('a label does not outlive the phase it describes', () async {
      final upload = FakeUploadClient(twoCards);
      final seen = <RecoverCalculating>[];
      final controller = RecoverController(
        client: upload,
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        staticRecoverer: FakeStaticRecoverer([
          dictOf(0xe37aa759, 50),
          dictOf(0x11223344, 50),
        ]),
        knownKeyFilter: (_) => FakeKnownKeys(),
      );
      addTearDown(controller.dispose);
      controller.addListener(() {
        final state = controller.state;
        if (state is RecoverCalculating) seen.add(state);
      });

      await controller.start();

      expect(
        seen.any((s) => s.label != null),
        isTrue,
        reason: 'generation has to say what it is doing',
      );
      expect(
        seen.last.label,
        isNull,
        reason: 'and stop saying it once the work it named is done',
      );
    });

    // Every planned unit has to be accounted for even when the whole batch
    // failed, or the readout ends a run short of its own total.
    test('a failed generation still finishes its cards', () async {
      final upload = FakeUploadClient(twoCards);
      final controller = RecoverController(
        client: upload,
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        staticRecoverer: FakeStaticRecoverer(
          const [],
          throws: StateError('engine gone'),
        ),
        knownKeyFilter: (_) => FakeKnownKeys(),
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.totalUnits, 2, reason: 'two cards were planned');
      expect(controller.doneUnits, controller.totalUnits);
    });

    // The generation step is the one that used to leave a finished hardnested
    // percentage on screen for minutes.
    test('candidate generation names itself', () async {
      final upload = FakeUploadClient(twoCards);
      final seen = <RecoverState>[];
      final controller = RecoverController(
        client: upload,
        mfApi: FakeReaderApi(),
        nestedApi: FakeTagApi(exists: true),
        staticRecoverer: FakeStaticRecoverer([
          dictOf(0xe37aa759, 50),
          dictOf(0x11223344, 50),
        ]),
        knownKeyFilter: (_) => FakeKnownKeys(),
      );
      addTearDown(controller.dispose);
      controller.addListener(() => seen.add(controller.state));

      await controller.start();

      expect(
        seen.whereType<RecoverCalculating>().any((s) => s.label != null),
        isTrue,
        reason: 'generation has to say what it is doing, not just "recovering"',
      );
    });
  });
}
