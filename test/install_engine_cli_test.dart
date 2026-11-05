import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/data/binary_sources.dart';
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/pages/apps/data/catalog_context.dart';
import 'package:qunleashed/pages/apps/data/install_engine.dart';
import 'package:qunleashed/pages/apps/data/manifest_registry.dart';
import 'package:qunleashed/pages/apps/data/models/card.dart';
import 'package:qunleashed/services/storage/paths.dart';

/// Where a CLI app lives. The terminal loads external commands as `.fal`
/// files from its own plugin folder; written as a `.fap` under the apps root,
/// the way every other app is, it would be installed and never found.
class _Flipper implements FlipperClient {
  final List<String> deleted = [];

  @override
  bool get isConnected => true;
  @override
  bool get isRpcReady => true;
  @override
  FlipperMode get mode => FlipperMode.rpc;
  @override
  DeviceToken get deviceToken => DeviceToken.fixed(current: true);
  @override
  Future<String> awaitName() async => 'TestFlipper';
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
    if (!request.hasStorageDeleteRequest()) {
      throw UnimplementedError('unexpected request: $request');
    }
    deleted.add(request.storageDeleteRequest.path);
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppCard card({String? family, String? installPath}) => AppCard.fromJson({
  'id': 'cli:cli_tictactoe',
  'alias': 'cli_tictactoe',
  'category_id': 'games',
  'author': '@apfxtech',
  'family': ?family,
  'install_path': ?installPath,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Flipper client;
  late InstallEngine engine;
  late io.Directory root;

  setUpAll(() {
    root = io.Directory.systemTemp.createTempSync('install_engine_cli');
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

  setUp(() {
    client = _Flipper();
    final api = AppsCatalogApi();
    final catalog = CatalogContext(client: client, api: api);
    engine = InstallEngine(
      client: client,
      api: api,
      manifests: ManifestRegistry(client: client),
      catalog: catalog,
      source: CatalogBinarySource(api: api, catalog: catalog),
      onInstalled: ({
        required String alias,
        required String devicePath,
        required List<int> fapBytes,
      }) async {},
    );
  });

  Future<String> binaryOf(AppCard app) async {
    expect(await engine.uninstall(app), isTrue);
    return client.deleted.last;
  }

  test(
    'a CLI app is a .fal in the plugin folder the catalogue names',
    () async {
      expect(
        await binaryOf(card(family: 'cli', installPath: kCliPluginsRoot)),
        '$kCliPluginsRoot/cli_tictactoe.fal',
      );
    },
  );

  test('a folder below the plugin root is kept', () async {
    expect(
      await binaryOf(
        card(family: 'cli', installPath: '$kCliPluginsRoot/games'),
      ),
      '$kCliPluginsRoot/games/cli_tictactoe.fal',
    );
  });

  test('a path out of the plugin root falls back to it', () async {
    for (final path in ['/ext/apps/Games', '$kCliPluginsRoot/../../apps']) {
      client.deleted.clear();
      expect(
        await binaryOf(card(family: 'cli', installPath: path)),
        '$kCliPluginsRoot/cli_tictactoe.fal',
      );
    }
  });

  test('other apps stay .fap files under the apps root', () async {
    expect(
      await binaryOf(card(family: 'application', installPath: 'Games')),
      '$kAppsRoot/Games/cli_tictactoe.fap',
    );
  });
}
