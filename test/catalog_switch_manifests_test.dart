import 'dart:async';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/pages/apps/data/binary_sources.dart';
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/pages/apps/data/catalog_context.dart';
import 'package:qunleashed/pages/apps/data/install_engine.dart';
import 'package:qunleashed/pages/apps/data/manifest_registry.dart';
import 'package:qunleashed/pages/apps/data/models/manifest.dart';
import 'package:qunleashed/pages/apps/data/update_registry.dart';

/// A Flipper with `.fim`s on it: lists them with their md5 and hands each
/// one out when read, counting the reads. A read can be held until let go.
class _FlipperWithApps implements FlipperClient {
  _FlipperWithApps(this.files);

  /// file name -> its text
  final Map<String, String> files;
  final List<String> reads = [];

  /// Held reads wait on this, when set.
  Completer<void>? gate;

  @override
  bool get isConnected => true;

  @override
  bool get isRpcReady => true;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  @override
  DeviceToken get deviceToken => DeviceToken.fixed(current: true);

  @override
  String? getName() => 'TestFlipper';

  @override
  Future<String> awaitName() async => 'TestFlipper';

  @override
  Future<Map<String, String>> awaitDeviceInfo() async => const {
    'hardware_target': '7',
    'firmware_api_major': '86',
    'firmware_api_minor': '0',
  };

  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  Future<List<Main>> _framesFor(Main request) async {
    if (request.hasStorageListRequest()) {
      // The apps' manifests only: the menu styles' folder is empty.
      if (request.storageListRequest.path != kManifestsRoot) {
        return [Main(storageListResponse: ListResponse())];
      }
      return [
        Main(
          storageListResponse: ListResponse(
            file: [
              for (final MapEntry(:key, :value) in files.entries)
                File(
                  name: key,
                  type: File_FileType.FILE,
                  md5sum: '${value.hashCode}',
                ),
            ],
          ),
        ),
      ];
    }
    if (request.hasStorageReadRequest()) {
      final name = request.storageReadRequest.path.split('/').last;
      reads.add(name);
      await gate?.future;
      return [
        Main(
          storageReadResponse: ReadResponse(
            file: File(data: utf8.encode(files[name] ?? '')),
          ),
        ),
      ];
    }
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
    final frames = await _framesFor(request);
    for (final frame in frames) {
      onFrame?.call(frame);
    }
    return frames;
  }

  @override
  Future<FlipperRpcBatch<T>> callRpc<T extends GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
  }) async {
    final frames = await _framesFor(request);
    final items = <T>[];
    for (final frame in frames) {
      onFrame?.call(frame);
      final picked = pick(frame);
      if (picked != null) items.add(picked);
    }
    return FlipperRpcBatch<T>(
      commandId: 0,
      request: request,
      frames: frames,
      items: items,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _fim(String alias, String uid) => AppManifest(
  uid: uid,
  versionUid: '${uid}v',
  path: '/ext/apps/USB/$alias.fap',
).encode();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FlipperWithApps flipper;
  late ManifestRegistry manifests;

  setUp(() {
    flipper = _FlipperWithApps({
      'usb_cdrom.fim': _fim('usb_cdrom', '5607f1a9fef11f5e27bfc1de'),
      'other.fim': _fim('other', '64971d0f6617ba37a4bc79b3'),
    });
    manifests = ManifestRegistry(client: flipper, cached: false);
  });

  group('switching the catalog', () {
    late UpdateRegistry updates;

    setUp(() {
      // A closed port: the catalog cannot be asked, which this does not need.
      final api = AppsCatalogApi(server: 'http://127.0.0.1:9');
      final catalog = CatalogContext(client: flipper, api: api);
      updates = UpdateRegistry(
        client: flipper,
        api: api,
        manifests: manifests,
        engine: InstallEngine(
          client: flipper,
          api: api,
          manifests: manifests,
          catalog: catalog,
          source: CatalogBinarySource(api: api, catalog: catalog),
          onInstalled: ({
            required String alias,
            required String devicePath,
            required List<int> fapBytes,
          }) async {},
        ),
        catalog: catalog,
      );
    });

    // v1 to v0 of one server changes where requests go, not what is on the
    // Flipper: reading every .fim again is what left the catalog showing an
    // installed app as one to install while it ran.
    test('asks the catalog again and reads no manifest again', () async {
      await manifests.refresh();
      expect(flipper.reads, hasLength(2));

      await updates.handleCatalogChange();

      expect(flipper.reads, hasLength(2));
      expect(manifests.byUid('5607f1a9fef11f5e27bfc1de'), isNotNull);
    });
  });

  group('a refresh that reads every manifest again', () {
    const usb = '5607f1a9fef11f5e27bfc1de';

    /// Starts a forced refresh and returns once it is held on its first
    /// read, with the list it read already taken.
    Future<({Future<void> done})> heldRefresh() async {
      flipper.gate = Completer<void>();
      final before = flipper.reads.length;
      final running = manifests.refresh(force: true);
      while (flipper.reads.length == before) {
        await Future<void>.delayed(Duration.zero);
      }
      return (done: running);
    }

    // Cleared first, an app read later in the pass looked not installed
    // until its own .fim came back, and the catalog offered to install it.
    test('keeps every installed app found while it reads', () async {
      await manifests.refresh();
      final running = (await heldRefresh()).done;

      expect(manifests.loading, isTrue);
      expect(manifests.byUid(usb), isNotNull);
      expect(manifests.byAlias('other'), isNotNull);

      flipper.gate!.complete();
      await running;
      expect(manifests.byUid(usb), isNotNull);
    });

    test(
      'lets an app gone from the Flipper go once the list is read',
      () async {
        await manifests.refresh();
        flipper.files.remove('other.fim');
        final running = (await heldRefresh()).done;
        expect(
          manifests.byAlias('other'),
          isNotNull,
          reason: 'not before the end',
        );

        flipper.gate!.complete();
        await running;
        expect(manifests.byAlias('other'), isNull);
        expect(manifests.byUid(usb), isNotNull);
      },
    );

    test('keeps an install that ended while it read', () async {
      await manifests.refresh();
      final running = (await heldRefresh()).done;
      final installed = AppManifest(
        uid: '64971d11577d519190ede5c5',
        path: '/ext/apps/Tools/fresh.fap',
      );
      manifests.put('fresh', installed);

      flipper.gate!.complete();
      await running;
      expect(manifests.byAlias('fresh'), same(installed));
      expect(manifests.byUid('64971d11577d519190ede5c5'), same(installed));
    });
  });
}
