import 'dart:async';
import 'dart:io' as io;

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/firmware/installer.dart';
import 'package:qunleashed/pages/devices/firmware/source.dart';
import 'package:qunleashed/pages/devices/firmware/update_state.dart';

/// Flashing a firmware, which is the one thing in this app where getting it
/// wrong bricks a device.
///
/// It had no tests. The client's API is extensions over `callRpcFrames` and
/// `callRpcFramesMulti` (see CLAUDE.md), so the fake sits there and reads the
/// protobuf request to decide what it is being asked - which is also what lets
/// it record the upload order.
///
/// What happens after `runUpdate` is decided by
/// `bindCurrentSession().device`, and until dart-flipperlib#6 the only binding
/// a fake could build named no device - so both outcomes collapsed into one
/// and the cases for them were left out rather than left green and empty.
/// `FlipperSessionBinding.to` is what opened them.
///
/// The wait itself is still not here: it is `LinkService.awaitUsbReturn`,
/// reached through the singleton rather than passed in, and it has its own
/// file. What is asserted is which side of it each link ends up on.
class FakeFlashClient implements FlipperClient {
  FakeFlashClient({this.connected = true, this.bound});

  bool connected;

  /// The device the install binds, which is what decides whether it waits for
  /// the Flipper to come back afterwards.
  FlipperDevice? bound;

  /// md5 the device reports per path. Absent means the file is not there.
  final Map<String, String> remote = {};

  /// Paths written, in order.
  final uploaded = <String>[];

  /// Directories made, in order.
  final made = <String>[];

  /// Set when `runUpdate` is called, with the manifest it was given.
  String? started;

  @override
  bool get isConnected => connected;

  @override
  FlipperSessionBinding bindCurrentSession() => bound == null
      ? const FlipperSessionBinding.unbound()
      : FlipperSessionBinding.to(bound!);

  /// Runs the body without a session, which is what an unbound binding does.
  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

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
    if (request.hasStorageMkdirRequest()) {
      made.add(request.storageMkdirRequest.path);
      return const [];
    }
    if (request.hasStorageMd5sumRequest()) {
      final md5 = remote[request.storageMd5sumRequest.path];
      if (md5 == null) throw StateError('no such file');
      return [Main(storageMd5sumResponse: Md5sumResponse(md5sum: md5))];
    }
    if (request.hasSystemUpdateRequest()) {
      started = request.systemUpdateRequest.updateManifest;
    }
    return const [];
  }

  /// `callRpc` is a method on the client rather than an extension, so unlike
  /// the storage and system API it does not route through `callRpcFrames` by
  /// itself. Picking the items out of the frames is all the real one adds.
  @override
  Future<FlipperRpcBatch<T>> callRpc<T extends GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
  }) async {
    final frames = await callRpcFrames(request, timeout: timeout);
    return FlipperRpcBatch<T>(
      commandId: 0,
      request: request,
      frames: frames,
      items: [for (final frame in frames) ?pick(frame)],
    );
  }

  /// The reboot at the end of `runUpdate` tears the link down.
  @override
  Future<void> disconnect() async {}

  /// Every chunked write arrives here. The first frame carries the path.
  @override
  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame) sendFrame) body, {
    Duration timeout = const Duration(seconds: 60),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
  }) async {
    await body((frame) async {
      if (frame.hasStorageWriteRequest()) {
        final path = frame.storageWriteRequest.path;
        if (path.isNotEmpty) uploaded.add(path);
      }
    });
    return const [];
  }

  /// `transport` answers null rather than throwing: `storageWriteChunked`
  /// reads it to pick a chunk size and to decide whether to pace its pings,
  /// and `Transport` is not part of the package's public surface, so it
  /// cannot be declared here. Everything else still fails loudly.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.memberName == #transport
      ? null
      : super.noSuchMethod(invocation);
}

class _Discovered implements DiscoveredDevice {
  const _Discovered(this.id, this.transport);

  @override
  final String id;

  @override
  String get name => id;

  @override
  final DeviceTransport transport;
}

FlipperDevice device(FlipperLink link) => FlipperDevice(
  id: 'A',
  name: 'A',
  link: link,
  source: _Discovered(
    'A',
    link == FlipperLink.usb ? DeviceTransport.usb : DeviceTransport.ble,
  ),
);

/// A source that hands back an archive already on disk.
class _LocalArchive implements FirmwareSource {
  _LocalArchive(this.path);

  final String path;

  @override
  bool get isRemote => false;

  @override
  Future<String> resolveArchive(
    String tmpDir,
    void Function(double progress) onProgress,
  ) async => path;
}

/// Writes a `.tgz` of `root/<name>` entries and returns its path.
String archiveOf(Map<String, String> files, {String root = 'f7-update-1.0'}) {
  final dir = io.Directory.systemTemp.createTempSync('flash_test');
  addTearDown(() => dir.deleteSync(recursive: true));

  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8Bytes(content);
    archive.addFile(ArchiveFile('$root/$name', bytes.length, bytes));
  });

  final tar = TarEncoder().encode(archive);
  final path = '${dir.path}${io.Platform.pathSeparator}update.tgz';
  io.File(path).writeAsBytesSync(GZipEncoder().encode(tar));
  return path;
}

List<int> utf8Bytes(String s) => s.codeUnits;

String md5Of(String content) => md5.convert(utf8Bytes(content)).toString();

void main() {
  late FakeFlashClient client;
  late List<UpdateState> states;

  setUp(() {
    client = FakeFlashClient();
    states = [];
  });

  Future<void> flash(String archivePath) => FirmwareInstaller.install(
    source: _LocalArchive(archivePath),
    client: client,
    onState: states.add,
  );

  /// Polls until [ready], or gives up after five seconds.
  Future<void> waitFor(bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!ready() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  String? errorText() =>
      states.whereType<UpdateError>().map((e) => e.message).firstOrNull;

  test(
    'an archive with nothing in it is an error, not an empty install',
    () async {
      await flash(archiveOf(const {}));

      expect(errorText(), isNotNull);
      expect(client.made, isEmpty, reason: 'nothing was sent to the device');
      expect(client.started, isNull);
    },
  );

  // Without update.fuf the Flipper has nothing to install from. Starting the
  // update anyway is what leaves a device with half a firmware and a reboot.
  test('an archive with no manifest never starts an update', () async {
    await flash(archiveOf(const {'flipper.bin': 'image'}));

    expect(errorText(), isNotNull);
    expect(client.started, isNull);
    expect(
      client.uploaded,
      contains('/ext/update/f7-update-1.0/flipper.bin'),
      reason: 'the files still went up; it is the start that is refused',
    );
  });

  group('a complete archive', () {
    final files = {'update.fuf': 'manifest', 'flipper.bin': 'image'};

    test('makes the update directory before it writes into it', () async {
      await flash(archiveOf(files));

      expect(client.made, ['/ext/update', '/ext/update/f7-update-1.0']);
    });

    test(
      'uploads every file and starts the update from the manifest',
      () async {
        await flash(archiveOf(files));

        expect(client.uploaded, [
          '/ext/update/f7-update-1.0/update.fuf',
          '/ext/update/f7-update-1.0/flipper.bin',
        ]);
        expect(client.started, '/ext/update/f7-update-1.0/update.fuf');
      },
    );

    // A retried install over a slow link is the reason this exists: the files
    // already there are the expensive part, and re-sending them is minutes.
    test('keeps a file the device already has', () async {
      client.remote['/ext/update/f7-update-1.0/flipper.bin'] = md5Of('image');

      await flash(archiveOf(files));

      expect(client.uploaded, ['/ext/update/f7-update-1.0/update.fuf']);
      expect(client.started, isNotNull);
    });

    // Same name, different content. Trusting the name would flash the old
    // image and report success.
    test('replaces one whose contents have changed', () async {
      client.remote['/ext/update/f7-update-1.0/flipper.bin'] = md5Of(
        'a different image',
      );

      await flash(archiveOf(files));

      expect(
        client.uploaded,
        contains('/ext/update/f7-update-1.0/flipper.bin'),
      );
    });

    test('reports each file as it verifies it', () async {
      await flash(archiveOf(files));

      final verifying = states.whereType<UpdateVerifying>().toList();
      expect(verifying.map((s) => s.fileIndex), [1, 2]);
      expect(verifying.every((s) => s.fileCount == 2), isTrue);
    });
  });

  group('after the update has been told to start', () {
    final files = {'update.fuf': 'manifest'};

    // Over BLE the radio comes back whenever the install is done and only the
    // user knows when to reach for it, so the app stops here.
    test('a BLE install is done, and waits for nothing', () async {
      client.bound = device(FlipperLink.ble);

      await flash(archiveOf(files));

      expect(states.last, isA<UpdateDone>());
    });

    // Over USB the port coming back is the signal, so the install is not over
    // until it does. The wait is `LinkService.awaitUsbReturn`; what matters
    // here is that this is the link that enters it.
    test('a USB install says it is installing, and does not finish', () async {
      client.bound = device(FlipperLink.usb);
      var finished = false;

      unawaited(flash(archiveOf(files)).then((_) => finished = true));
      // Waited for rather than slept past: the flash does real work - gzip,
      // md5, the writes - and a fixed delay is either flaky or slow.
      await waitFor(() => states.any((s) => s is UpdateInstalling));

      expect(states.last, isA<UpdateInstalling>());
      expect(
        finished,
        isFalse,
        reason: 'it is waiting on the port coming back',
      );
    });

    // Nothing bound at all - no session when the update went out. There is no
    // device to wait for, so waiting would be waiting on nothing.
    test('an install that bound no device is done', () async {
      await flash(archiveOf(files));

      expect(states.last, isA<UpdateDone>());
    });
  });
}
