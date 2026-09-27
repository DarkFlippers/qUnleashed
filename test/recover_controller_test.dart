import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/mfkey32_api.dart';
import 'package:qunleashed/pages/tools/mifare/nested_api.dart';
import 'package:qunleashed/pages/tools/mifare/recover_controller.dart';
import 'package:qunleashed/pages/tools/mifare/recover_models.dart';

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
