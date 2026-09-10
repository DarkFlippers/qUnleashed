import 'dart:convert';

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flipperlib/flipperlib.dart' as fl show File;
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/pages/apps/data/catalog_context.dart';
import 'package:qunleashed/pages/apps/data/device_source.dart';
import 'package:qunleashed/pages/apps/data/install_engine.dart';
import 'package:qunleashed/pages/apps/data/manifest_registry.dart';

/// A device whose storage is whatever the test says it is.
///
/// Only the four calls a scan makes are answered; everything else falls to
/// [noSuchMethod], so a scan that starts reaching for something new fails
/// loudly instead of quietly reading a default.
class _FakeClient implements FlipperClient {
  /// Directory path -> entries, as `storageList` would report them.
  final Map<String, List<fl.File>> tree = {};

  /// Manifest path -> its text.
  final Map<String, String> manifestBodies = {};

  bool connected = true;

  /// Listings to answer before the device "disappears", or null to stay up.
  /// This is how a walk is cut short part-way, which is the difference between
  /// "these apps are gone" and "I did not get to look".
  int? dropAfterListings;
  int listings = 0;

  @override
  bool get isConnected => connected;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  /// storageList and storageReadChunked are extension methods, so they resolve
  /// statically and arrive here rather than being overridable themselves.
  List<Main> _framesFor(Main request) {
    if (request.hasStorageListRequest()) {
      listings += 1;
      final drop = dropAfterListings;
      if (drop != null && listings >= drop) connected = false;
      final path = request.storageListRequest.path;
      return [
        Main(
          storageListResponse: ListResponse()
            ..file.addAll(tree[path] ?? const []),
        ),
      ];
    }
    if (request.hasStorageReadRequest()) {
      final body = manifestBodies[request.storageReadRequest.path];
      if (body == null) return const [];
      return [
        Main(
          storageReadResponse: ReadResponse(
            file: fl.File(data: utf8.encode(body)),
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
    FlipperRequestPriority priority = FlipperRequestPriority.defaultPriority,
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
    return retainFrames ? frames : const [];
  }

  @override
  Future<FlipperRpcBatch<T>> callRpc<T extends GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.defaultPriority,
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
  Future<String> awaitName() => Future<String>.error(StateError('no name'));

  @override
  String? getName() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A scan never touches the install engine, so building a real one - which
/// needs a catalog source registry and a live install pipeline - would only
/// add surface that the test does not exercise.
class _FakeEngine implements InstallEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

fl.File dir(String name) => fl.File(name: name, type: File_FileType.DIR);

fl.File fap(String name) => fl.File(
  name: name,
  type: File_FileType.FILE,
  size: 1024,
  md5sum: 'deadbeef',
);

String manifestFor(String alias, String folder) =>
    'UID: uid-$alias\nPath: $kAppsRoot/$folder/$alias.fap\nFull Name: $alias\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeClient client;
  late DeviceSource source;

  /// A device that reports [manifests] as installed and [onDisk] as the apps
  /// actually present under /ext/apps/Tools.
  void give({required List<String> manifests, required List<String> onDisk}) {
    client.tree[kManifestsRoot] = [
      for (final alias in manifests) fap('$alias.fim'),
    ];
    for (final alias in manifests) {
      client.manifestBodies['$kManifestsRoot/$alias.fim'] = manifestFor(
        alias,
        'Tools',
      );
    }
    client.tree[kAppsRoot] = [dir('Tools')];
    client.tree['$kAppsRoot/Tools'] = [
      for (final alias in onDisk) fap('$alias.fap'),
    ];
  }

  setUp(() {
    client = _FakeClient();
    final registry = ManifestRegistry(client: client);
    final api = AppsCatalogApi();
    source = DeviceSource(
      client: client,
      api: api,
      manifests: registry,
      engine: _FakeEngine(),
    );
  });

  group('presence on the device', () {
    // The reported bug: apps deleted through the file manager kept showing as
    // installed, and Refresh could not clear them because Refresh is the scan.
    test('an app whose fap is gone is reported as not on the device', () async {
      give(manifests: ['ghost', 'real'], onDisk: ['real']);

      await source.scan();

      final ghost = source.apps.firstWhere((a) => a.alias == 'ghost');
      final real = source.apps.firstWhere((a) => a.alias == 'real');
      expect(ghost.isMissingFromDevice, isTrue);
      expect(real.isMissingFromDevice, isFalse);
      expect(real.onDevice, isTrue);
    });

    // Absence is only knowable from a walk that finished. A disconnect
    // part-way must not turn every app into a missing one.
    test('a walk cut short claims nothing is missing', () async {
      give(manifests: ['ghost'], onDisk: []);
      // Two listings get through - the manifests and the apps root - and the
      // device goes away before any folder is read.
      client.dropAfterListings = 2;

      await source.scan();

      final ghost = source.apps.firstWhere((a) => a.alias == 'ghost');
      expect(ghost.onDevice, isNull, reason: 'not proven either way');
      expect(ghost.isMissingFromDevice, isFalse);
    });

    // A .fap directly in the apps root is installed too. Overlooking it would
    // make a complete walk call it absent.
    test('an app in the apps root counts as present', () async {
      give(manifests: ['loose'], onDisk: []);
      client.manifestBodies['$kManifestsRoot/loose.fim'] =
          'UID: uid-loose\nPath: $kAppsRoot/loose.fap\n';
      client.tree[kAppsRoot] = [dir('Tools'), fap('loose.fap')];

      await source.scan();

      final loose = source.apps.firstWhere((a) => a.alias == 'loose');
      expect(loose.onDevice, isTrue);
    });

    test('connecting a device forgets what the last one held', () async {
      give(manifests: ['ghost'], onDisk: []);
      await source.scan();
      expect(source.apps.single.isMissingFromDevice, isTrue);

      source.handleConnect();

      expect(source.apps.single.onDevice, isNull);
    });
  });
}
