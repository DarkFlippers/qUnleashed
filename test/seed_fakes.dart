// A Flipper and an engine for the seed-recovery tests.
//
// Shared rather than copied, because two suites need the same device: the
// controller tests drive it directly, and the page test drives it through the
// widget tree. `test/fake_app_client.dart` records why that is the moment to
// pull one out.
//
// The client is faked at `callRpcFrames`, `callRpcFramesMulti` and `callRpc`.
// The first two are what the storage calls are built on. `callRpc` is a method
// on the client rather than one of the extensions over it, so a fake that
// stops at the frame level never gets asked and `storageStat` dies in
// `noSuchMethod` before reaching any of this.
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flipperlib/flipperlib.dart' as fl show File;
// Not exported by the package root, and storageWriteChunked reads it off the
// client to size its frames - so a fake has to answer it by name. The archive
// tests reach for it the same way, for the same call.
import 'package:flipperlib/src/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/pages/tools/subghz/seed/faaccrack_recoverer.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_controller.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_models.dart';

/// A capture the parser accepts, as the Flipper-side app writes one.
const seedCaptureFixture = '''
Filetype: Flipper SubGhz Seed Capture
Version: 1
Manufacturer: Genius
Frequency: 433920000
Fix: A0DC9330
Hops: 3
Hop: 29389EF7
Hop: 40101499
Hop: A1F9C88F
''';

/// A Flipper holding a capture folder and a Sub-GHz folder.
class SeedFakeClient implements FlipperClient {
  /// What the capture folder holds, by file name.
  final folder = <String, String>{};

  /// Paths a stat should answer for, i.e. files already on the device.
  final existing = <String>{};

  /// What the write pump delivered, by path.
  final writes = <String, List<int>>{};

  final calls = <String>[];

  bool connected = true;

  /// Raised instead of answering a list, when set.
  Object? listThrows;

  /// Raised instead of answering a stat, when set. A *free* path is not this -
  /// the firmware refuses the stat, which arrives as
  /// [FlipperRpcStorageNotExistException] and is answered below.
  Object? statThrows;

  /// Raised instead of accepting a write, when set.
  Object? writeThrows;

  /// Raised instead of accepting a delete, when set.
  Object? deleteThrows;

  @override
  bool get isConnected => connected;

  /// No transport, which is what picks the chunk size and the ping pace. The
  /// write pump reads it before sending anything.
  @override
  Transport? get transport => null;

  /// `storageWriteChunked` asks this inside its own catch, to decide between
  /// rethrowing and restarting the upload. Without it the configured error is
  /// replaced by a `NoSuchMethodError` from `noSuchMethod`, and a test that
  /// names the configured one passes on a different mechanism.
  @override
  bool isLinkDropError(Object e) => false;

  @override
  FlipperSessionBinding bindCurrentSession() => connected
      ? FlipperSessionBinding.to(_fakeDevice)
      : const FlipperSessionBinding.unbound();

  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  @override
  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame) sendFrame) body, {
    Duration timeout = const Duration(seconds: 60),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
  }) async {
    await body((frame) async {
      if (!frame.hasStorageWriteRequest()) return;
      final request = frame.storageWriteRequest;
      calls.add('write(${request.path})');
      if (writeThrows != null) throw writeThrows!;
      (writes[request.path] ??= <int>[]).addAll(request.file.data);
      existing.add(request.path);
    });
    return const [];
  }

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
    if (request.hasStorageListRequest()) {
      calls.add('list(${request.storageListRequest.path})');
      if (listThrows != null) throw listThrows!;
      return _one(
        Main(
          storageListResponse: ListResponse(
            file: [
              for (final entry in folder.entries)
                fl.File(
                  name: entry.key,
                  type: File_FileType.FILE,
                  size: utf8.encode(entry.value).length,
                ),
            ],
          ),
        ),
        onFrame,
      );
    }
    if (request.hasStorageReadRequest()) {
      final path = request.storageReadRequest.path;
      calls.add('read($path)');
      final body = folder[path.split('/').last];
      if (body == null) throw FlipperRpcStorageNotExistException(Main());
      return _one(
        Main(
          storageReadResponse: ReadResponse(
            file: fl.File(data: utf8.encode(body)),
          ),
        ),
        onFrame,
      );
    }
    if (request.hasStorageStatRequest()) {
      final path = request.storageStatRequest.path;
      calls.add('stat($path)');
      if (statThrows != null) throw statThrows!;
      if (!existing.contains(path)) {
        throw FlipperRpcStorageNotExistException(Main());
      }
      return _one(
        Main(storageStatResponse: StatResponse(file: fl.File(size: 64))),
        onFrame,
      );
    }
    if (request.hasStorageDeleteRequest()) {
      final path = request.storageDeleteRequest.path;
      calls.add('delete($path)');
      if (deleteThrows != null) throw deleteThrows!;
      folder.remove(path.split('/').last);
      return const [];
    }
    calls.add('unexpected ${request.whichContent()}');
    return const [];
  }

  List<Main> _one(Main frame, void Function(Main frame)? onFrame) {
    onFrame?.call(frame);
    return [frame];
  }

  /// Forwarded to [callRpcFrames], keeping the shape of the real one.
  @override
  Future<FlipperRpcBatch<T>> callRpc<T extends GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
  }) async {
    final frames = await callRpcFrames(
      request,
      timeout: timeout,
      priority: priority,
      onFrame: onFrame,
    );
    return FlipperRpcBatch<T>(
      commandId: request.commandId,
      request: request,
      frames: frames,
      items: [for (final frame in frames) ?pick(frame)],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A device for the binding, so [FlipperSessionBinding.isAlive] can be true.
/// The controller reads only that; nothing here looks at the device itself.
class _FakeDiscovered implements DiscoveredDevice {
  @override
  String get id => 'fake';
  @override
  String get name => 'Flipper';
  @override
  DeviceTransport get transport => DeviceTransport.usb;
}

final _fakeDevice = FlipperDevice(
  id: 'fake',
  name: 'Flipper',
  link: FlipperLink.usb,
  source: _FakeDiscovered(),
);

/// An engine that recovers whatever it is handed.
class FoundRecoverer implements FaaccrackRecoverer {
  @override
  Future<SeedResult> recover({
    required SeedManufacturer manufacturer,
    required int fix,
    required List<int> hops,
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  }) async => seedResult(
    SeedOutcome.found,
    seed: 0x546AA44F,
    lrkey: 0x1122334455667788,
    counter: 0xC,
    frameHop: 0x29389EF7,
    hopsUsed: hops.length,
  );
}

/// An engine whose answer `canSave` refuses: a seed it could not verify.
class UnverifiedRecoverer implements FaaccrackRecoverer {
  @override
  Future<SeedResult> recover({
    required SeedManufacturer manufacturer,
    required int fix,
    required List<int> hops,
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  }) async => seedResult(SeedOutcome.unverified);
}

/// A controller that has listed the folder and opened one capture in it,
/// through the real device path rather than a debug setter.
Future<SeedController> openedSeedController(
  SeedFakeClient client, {
  FaaccrackRecoverer? recoverer,
  String open = 'one.txt',
}) async {
  if (client.folder.isEmpty) client.folder['one.txt'] = seedCaptureFixture;
  final controller = SeedController(
    client: client,
    recoverer: recoverer ?? FoundRecoverer(),
  );
  await controller.refresh();
  final file = controller.files.firstWhere((f) => f.name == open);
  await controller.open(file);
  expect(controller.capture, isNotNull, reason: 'fixture must parse');
  return controller;
}

/// A controller holding a recovery that `canSave` accepts.
Future<SeedController> saveableSeedController(SeedFakeClient client) async {
  final controller = await openedSeedController(client);
  await controller.search();
  expect(controller.canSave, isTrue, reason: 'fixture must be saveable');
  return controller;
}
