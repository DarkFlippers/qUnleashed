import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
// Not exported by the package root, and storageWriteChunked reads it off the
// client to size its frames, so a fake has to answer it by name.
import 'package:flipperlib/src/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/map/controller.dart';
import 'package:qunleashed/services/storage/paths.dart';

import 'kept_lines.dart';

/// Moving a pin on the map, and what it says when only half of it moved.
///
/// The file exists twice: the copy under the user's documents and the copy on
/// the Flipper. The save patches the local one, pushes it to the device and
/// reports success either way - which is right, because the local copy is
/// correct and the pin belongs where the user put it. What was missing is any
/// sign that the two have come apart. ADR 0008.
const _remotePath = '/ext/subghz/gate.sub';

const _sub = '''
Filetype: Flipper SubGhz Key File
Version: 1
Frequency: 433920000
Preset: FuriHalSubGhzPresetOok650Async
Protocol: Princeton
Bit: 24
Key: 00 00 00 00 00 12 34 56
Lat: 1.000000
Lon: 2.000000
''';

/// A Flipper that takes the write, or will not.
class _WritingFlipper implements FlipperClient {
  _WritingFlipper({this.connected = true, this.writeFails = false});

  final bool connected;
  final bool writeFails;

  final List<String> written = [];

  @override
  bool get isConnected => connected;

  @override
  bool get isRpcReady => connected;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  /// storageWriteChunked reads this to size its frames, and a client with no
  /// transport is the state the app is in before a link comes up.
  @override
  Transport? get transport => null;

  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  /// The upload is an extension method over callRpcFramesMulti, so it resolves
  /// statically and arrives here rather than being overridable itself.
  @override
  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame) sendFrame) send, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    bool retainFrames = true,
    bool interleavable = false,
  }) async {
    // The refusal deliberately does not name the file. A real one often does,
    // and a log line that only echoed it would read as the controller having
    // named it when it had not.
    if (writeFails) throw StateError('ERROR_STORAGE_NOT_READY');
    await send((frame) async {
      if (frame.hasStorageWriteRequest()) {
        written.add(frame.storageWriteRequest.path);
      }
    });
    return const [];
  }

  /// The upload asks this before deciding to retry. A storage refusal is not
  /// a dropped link, and answering it here keeps the failure the controller
  /// reports the one the device gave.
  @override
  bool isLinkDropError(Object e) => false;

  /// No device is synced, so the reload that follows a save finds nothing to
  /// list. This test is about the write, not about what the map then shows.
  @override
  String? getName() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  late io.Directory root;
  late io.File local;

  setUp(() {
    // The reload behind the save reads the last synced device out of the
    // documents directory, which the test process cannot otherwise move.
    root = io.Directory.systemTemp.createTempSync('map_write_coordinates');
    debugUseDocumentsRoot(root);
    local = io.File('${root.path}${io.Platform.pathSeparator}gate.sub')
      ..writeAsStringSync(_sub);
    clearKeptLines();
    addTearDown(() {
      debugUseDocumentsRoot(null);
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
  });

  Iterable<String> lines(String fragment) =>
      keptLines.where((l) => l.contains(fragment));

  Future<bool> move(_WritingFlipper client, {String? remotePath}) =>
      MapToolController(client: client).writeCoordinates(
        localPath: local.path,
        remotePath: remotePath,
        latitude: 50.45,
        longitude: 30.523,
      );

  group('a device copy that did not take the new coordinates', () {
    // The save is not failed over this on purpose: the pin is where the user
    // put it in the copy the map reads, and failing would say otherwise.
    test('still reports the save as done', () async {
      expect(
        await move(_WritingFlipper(writeFails: true), remotePath: _remotePath),
        isTrue,
      );
    });

    test('leaves the local copy correct', () async {
      await move(_WritingFlipper(writeFails: true), remotePath: _remotePath);

      expect(local.readAsStringSync(), contains('Lat: 50.450000'));
    });

    test('names the file the Flipper still holds the old ones for', () async {
      await move(_WritingFlipper(writeFails: true), remotePath: _remotePath);

      expect(lines(_remotePath), hasLength(1));
    });
  });

  group('nothing to say', () {
    test('when the device took the write', () async {
      final client = _WritingFlipper();

      expect(await move(client, remotePath: _remotePath), isTrue);
      expect(client.written, [_remotePath]);
      expect(lines('[Map]'), isEmpty);
    });

    // A file that was never on a Flipper has no second copy to disagree with.
    test('when the file has no device copy', () async {
      expect(await move(_WritingFlipper(writeFails: true)), isTrue);
      expect(lines('[Map]'), isEmpty);
    });

    test('when there is no Flipper connected', () async {
      expect(
        await move(
          _WritingFlipper(connected: false, writeFails: true),
          remotePath: _remotePath,
        ),
        isTrue,
      );
      expect(lines('[Map]'), isEmpty);
    });
  });
}
