import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/mfkey32_api.dart';
import 'package:qunleashed/pages/tools/mifare/nested_api.dart';
import 'package:qunleashed/pages/tools/mifare/known_key_filter.dart';
import 'package:qunleashed/pages/tools/mifare/recover_controller.dart';
import 'package:qunleashed/pages/tools/mifare/cuid_dict_format.dart';
import 'package:qunleashed/pages/tools/mifare/nested_models.dart';
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
      upload.failWriteForCuid = 0xe37aa759;
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
  FakeUploadClient(this.log);

  final String log;

  /// Frames the real `storageWriteChunked` handed down, counted so a run that
  /// stopped early can be told from one that finished.
  int framesSent = 0;

  /// Runs after each frame, for a test that wants to pull the page away
  /// mid-upload. Not `onFrame`: `callRpcFrames` takes a parameter by that name
  /// and would shadow it.
  void Function(int framesSoFar)? onFrameSent;

  /// Refuses the write whose path names this cuid, for the case where one card
  /// fails and the run carries on.
  int? failWriteForCuid;

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
      final frame = Main()
        ..storageReadResponse = (ReadResponse()
          ..file = (File()..data = utf8.encode(log)));
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
      if (failWriteForCuid != null &&
          frame.hasStorageWriteRequest() &&
          frame.storageWriteRequest.path.contains(
            failWriteForCuid!.toRadixString(16),
          )) {
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
  FakeStaticRecoverer(this.dicts);

  final List<StaticCandidateDict> dicts;

  /// How many nonces the generator was actually asked about. Zero is the claim
  /// the dedup makes: the expensive path was never entered.
  int askedAbout = 0;

  @override
  Future<List<StaticCandidateDict>> buildCandidateDicts(
    List<NestedNonce> nonces,
  ) async {
    askedAbout += nonces.length;
    return dicts;
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
