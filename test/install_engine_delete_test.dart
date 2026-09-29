import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/data/atp/atp_source.dart';
import 'package:qunleashed/pages/apps/data/binary_sources.dart';
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/pages/apps/data/catalog_context.dart';
import 'package:qunleashed/pages/apps/data/install_engine.dart';
import 'package:qunleashed/pages/apps/data/manifest_registry.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/storage/paths.dart';

/// Removing a file from the Flipper, and what it says when the file stays.
///
/// Every delete here is best-effort by design: the uninstall reports success
/// and the app disappears from the list whether or not the Flipper actually
/// removed anything. That is the right behaviour and the wrong silence - what
/// is left behind is a file on the SD card the app believes is gone, and it
/// used to leave no trace anywhere. ADR 0008.
const _fapPath = '$kAppsRoot/Tools/tool.fap';
const _manifestPath = '$kManifestsRoot/tool.fim';

/// A Flipper that answers every request, or refuses the deletes.
class _DeletingFlipper implements FlipperClient {
  /// Fails every delete, the way a read-only card or a file already gone does.
  bool deleteFails = false;

  final List<String> deleted = [];

  @override
  bool get isConnected => true;

  @override
  bool get isRpcReady => true;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  @override
  DeviceToken get deviceToken => DeviceToken.fixed(current: true);

  /// Answered because removing an alias writes the manifest cache, which is
  /// filed under the device's name. Left unanswered it would fail into the
  /// log this test reads.
  @override
  Future<String> awaitName() async => 'TestFlipper';

  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  /// storageDelete is an extension method, so it resolves statically and
  /// arrives here rather than being overridable itself.
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
    if (!request.hasStorageDeleteRequest()) {
      throw UnimplementedError('unexpected request: $request');
    }
    // The refusal deliberately does not name the file. A real one often
    // does, and a log line that only echoes it would read as the engine
    // having named it when it had not.
    if (deleteFails) throw StateError('ERROR_STORAGE_NOT_READY');
    deleted.add(request.storageDeleteRequest.path);
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _DeletingFlipper client;
  late InstallEngine engine;
  late io.Directory root;
  late int logBase;

  // The manifest cache this uninstall rewrites is filed under the user's
  // documents directory, which the test process cannot otherwise move. It is
  // saved unawaited, so the override has to outlive the case that triggers it
  // or a late write lands in the developer's own Documents folder.
  setUpAll(() {
    root = io.Directory.systemTemp.createTempSync('install_engine_delete');
    debugUseDocumentsRoot(root);
  });

  tearDownAll(() {
    debugUseDocumentsRoot(null);
    // Tolerated because the save that put a file here is unawaited and can
    // still hold it open. The directory is under the system temp root either
    // way, and failing the run over it would make this test flaky.
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on io.FileSystemException {
      return;
    }
  });

  setUp(() {
    client = _DeletingFlipper();
    final api = AppsCatalogApi();
    final catalog = CatalogContext(client: client, api: api);
    engine = InstallEngine(
      client: client,
      api: api,
      manifests: ManifestRegistry(client: client),
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
    );
    LogService.clearHistory();
    logBase = LogService.history.length;
  });

  Iterable<String> lines(String fragment) =>
      LogService.history.skip(logBase).where((l) => l.contains(fragment));

  Future<bool> uninstall() =>
      engine.deleteInstalled(alias: 'tool', fapPath: _fapPath);

  group('a delete the Flipper refuses', () {
    // Not a failure the user is shown, and deliberately so: the manifest may
    // already be gone, and stopping here would leave the app half-removed.
    test('still reports the uninstall as done', () async {
      client.deleteFails = true;

      expect(await uninstall(), isTrue);
    });

    test('names the file that is still there', () async {
      client.deleteFails = true;

      await uninstall();

      expect(lines(_fapPath), hasLength(1));
    });

    // Both files go in the same uninstall and either can be the one that
    // stays, so a line that covers only the first says nothing about the
    // .fap the user can still see in the file manager.
    test('names each of them, not just the first', () async {
      client.deleteFails = true;

      await uninstall();

      expect(lines(_manifestPath), hasLength(1));
      expect(lines('could not remove'), hasLength(2));
    });
  });

  test('a delete that goes through says nothing', () async {
    expect(await uninstall(), isTrue);

    expect(client.deleted, [_manifestPath, _fapPath]);
    expect(lines('[InstallEngine]'), isEmpty);
  });
}
