import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/pages/apps/data/atp/atp_source.dart';
import 'package:qunleashed/pages/apps/data/binary_sources.dart';
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/pages/apps/data/catalog_context.dart';
import 'package:qunleashed/pages/apps/data/install_engine.dart';
import 'package:qunleashed/pages/apps/data/manifest_registry.dart';
import 'package:qunleashed/pages/apps/data/update_registry.dart';
import 'package:qunleashed/services/storage/paths.dart';

/// Telling "nothing to show" apart from "could not look".
///
/// Every one of these lists renders the same empty screen for both, because
/// the only state they carried was loading/loaded and a count. A Flipper
/// nobody could read reads as a Flipper with no apps on it; a release nobody
/// could fetch reads as a release with nothing in it; an update check that
/// never finished reads as being up to date. #112.
class _RefusingFlipper implements FlipperClient {
  /// Raised instead of answering, when set.
  Object? refuses;

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

  /// The update check asks for the firmware target before anything else, and
  /// a Flipper that will not answer that is the plainest way to fail one.
  @override
  Future<Map<String, String>> awaitDeviceInfo() async {
    if (refuses != null) throw refuses!;
    return const {
      'hardware_target': '7',
      'firmware_api_major': '86',
      'firmware_api_minor': '0',
    };
  }

  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  List<Main> _framesFor(Main request) {
    if (refuses != null) throw refuses!;
    if (request.hasStorageListRequest()) {
      return [Main(storageListResponse: ListResponse())];
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
    final frames = _framesFor(request);
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
    final frames = _framesFor(request);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory root;

  setUpAll(() {
    // The manifest cache is filed under the device's name off the documents
    // directory, which the test process cannot otherwise move.
    root = io.Directory.systemTemp.createTempSync('apps_failed_state');
    debugUseDocumentsRoot(root);
  });

  tearDownAll(() {
    debugUseDocumentsRoot(null);
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on io.FileSystemException {
      return;
    }
  });

  group('the list of installed apps', () {
    late _RefusingFlipper client;
    late ManifestRegistry manifests;

    setUp(() {
      client = _RefusingFlipper();
      manifests = ManifestRegistry(client: client);
    });

    test('knows it could not be read', () async {
      client.refuses = StateError('ERROR_STORAGE_NOT_READY');

      await manifests.refresh();

      expect(manifests.failed, isTrue);
    });

    // An empty answer is an answer: this Flipper has no apps installed, and
    // the screen is right to say so.
    test('does not confuse an empty answer with no answer', () async {
      await manifests.refresh();

      expect(manifests.failed, isFalse);
      expect(manifests.all, isEmpty);
    });

    test('starts out knowing nothing either way', () {
      expect(manifests.failed, isFalse);
    });

    // A read that works after one that did not has to clear it, or the
    // screen keeps apologising for a failure that is over.
    test('forgets a failure once a read gets through', () async {
      client.refuses = StateError('ERROR_STORAGE_NOT_READY');
      await manifests.refresh();
      expect(manifests.failed, isTrue);

      client.refuses = null;
      await manifests.refresh(force: true);

      expect(manifests.failed, isFalse);
    });
  });

  group('the check for updates', () {
    late _RefusingFlipper client;
    late UpdateRegistry updates;

    setUp(() {
      client = _RefusingFlipper();
      final api = AppsCatalogApi();
      final catalog = CatalogContext(client: client, api: api);
      final manifests = ManifestRegistry(client: client);
      updates = UpdateRegistry(
        client: client,
        api: api,
        manifests: manifests,
        engine: InstallEngine(
          client: client,
          api: api,
          manifests: manifests,
          catalog: catalog,
          sources: AppSourceRegistry(
            catalog: CatalogBinarySource(api: api, catalog: catalog),
            atp: AtpBinarySource(AtpSource.instance),
          ),
          onInstalled: ({
            required String alias,
            required String devicePath,
            required List<int> fapBytes,
          }) async {},
        ),
        catalog: catalog,
      );
    });

    // The count is zero whether everything is current or nothing could be
    // checked, and the badge rendered only above zero - so a failure looked
    // exactly like being up to date.
    test('knows it never finished', () async {
      client.refuses = StateError('ERROR_STORAGE_NOT_READY');

      await updates.refresh();

      expect(updates.count, 0);
      expect(updates.failed, isTrue);
    });

    test('starts out knowing nothing either way', () {
      expect(updates.failed, isFalse);
    });

    // Or the badge keeps apologising for a check that has since succeeded.
    test('forgets it once a check gets through', () async {
      client.refuses = StateError('ERROR_STORAGE_NOT_READY');
      await updates.refresh();
      expect(updates.failed, isTrue);

      client.refuses = null;
      await updates.refresh(force: true);

      expect(updates.failed, isFalse);
    });
  });

  group('the plugin pack', () {
    setUp(() {
      addTearDown(() => AtpSource.debugFetchReleaseIndex = null);
    });

    test('knows the release could not be fetched', () async {
      AtpSource.debugFetchReleaseIndex = () async =>
          throw StateError('no network');

      await AtpSource.instance.downloadLatest();

      expect(AtpSource.instance.failed, isTrue);
    });

    // The quiet half. The fetch decides there is nothing to take - a
    // rate-limit object in place of the release, or a release with no index
    // asset - and raises nothing, so the catch never runs.
    test('knows an empty answer is not a release with no apps', () async {
      AtpSource.debugFetchReleaseIndex = () async => null;

      await AtpSource.instance.downloadLatest();

      expect(AtpSource.instance.failed, isTrue);
    });

    test('forgets it once a release comes back', () async {
      AtpSource.debugFetchReleaseIndex = () async =>
          throw StateError('no network');
      await AtpSource.instance.downloadLatest();
      expect(AtpSource.instance.failed, isTrue);

      AtpSource.debugFetchReleaseIndex = () async => '{"blocks":[]}';
      await AtpSource.instance.downloadLatest();

      expect(AtpSource.instance.failed, isFalse);
    });
  });
}
