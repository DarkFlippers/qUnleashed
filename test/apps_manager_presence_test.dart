import 'dart:convert';
import 'dart:io';

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flipperlib/flipperlib.dart' as fl show File;
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/pages/apps/data/catalog_context.dart';
import 'package:qunleashed/pages/apps/data/device_source.dart';
import 'package:qunleashed/pages/apps/data/install_engine.dart';
import 'package:qunleashed/pages/apps/data/manifest_registry.dart';
import 'package:qunleashed/pages/apps/data/models/manifest.dart';

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

  /// The listing after which the device "disappears", by path. This is how a
  /// walk is cut short part-way, which is the difference between "these apps
  /// are gone" and "I did not get to look". Keyed on the path rather than a
  /// count so that adding a listing elsewhere cannot silently turn this into a
  /// different test.
  String? dropAfterListing;

  /// A path whose listing fails outright, as a real one does for a missing
  /// directory or a yanked card.
  String? failListing;

  final List<String> listed = [];

  @override
  bool get isConnected => connected;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  /// storageList and storageReadChunked are extension methods, so they resolve
  /// statically and arrive here rather than being overridable themselves.
  List<Main> _framesFor(Main request) {
    if (request.hasStorageListRequest()) {
      final path = request.storageListRequest.path;
      listed.add(path);
      if (path == failListing) {
        throw StateError('ERROR_STORAGE_NOT_READY: $path');
      }
      final frames = [
        Main(
          storageListResponse: ListResponse()
            ..file.addAll(tree[path] ?? const []),
        ),
      ];
      if (path == dropAfterListing) connected = false;
      return frames;
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
  Future<String> awaitName() async => 'TestFlipper';

  @override
  String? getName() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A scan never touches the install engine, so building a real one - which
/// needs a catalog source registry and a live install pipeline - would only
/// add surface that the test does not exercise.
class _FakeEngine implements InstallEngine {
  final List<String> deleted = [];
  final List<String> restored = [];
  bool restoreSucceeds = true;

  @override
  Future<bool> deleteInstalled({
    required String alias,
    required String fapPath,
  }) async {
    deleted.add(alias);
    return true;
  }

  @override
  Future<bool> restore({
    required String alias,
    required String fapPath,
    required List<int> fapBytes,
    AppManifest? manifest,
  }) async {
    restored.add(alias);
    return restoreSucceeds;
  }

  /// Anything else is a call this test did not expect, and answering it with
  /// null would hide that rather than show it.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('engine.${invocation.memberName}');
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
  late _FakeEngine engine;
  late DeviceSource source;
  late Directory backup;

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
    // Without this the mirror phase reads and writes the real Devices folder
    // under the developer's documents directory, so what the suite covers
    // depends on whose machine it runs on.
    backup = Directory.systemTemp.createTempSync('apps_presence');
    DeviceSource.backupDirectory = (_) async => backup;
    client = _FakeClient();
    engine = _FakeEngine();
    final registry = ManifestRegistry(client: client);
    final api = AppsCatalogApi();
    source = DeviceSource(
      client: client,
      api: api,
      manifests: registry,
      engine: engine,
    );
  });

  tearDown(() {
    DeviceSource.backupDirectory = null;
    if (backup.existsSync()) backup.deleteSync(recursive: true);
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
      client.dropAfterListing = kAppsRoot;

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
      // The mirror stores it in its own root, so the folder has to agree or
      // restore and delete go looking in a directory that never exists.
      expect(loose.folder, '');
    });

    // handleConnect is the same-device branch; a different Flipper routes to
    // handleDeviceChange, so testing only the former proves nothing about the
    // case that actually matters.
    test('swapping to another device forgets what the last one held', () async {
      give(manifests: ['ghost'], onDisk: []);
      await source.scan();
      expect(source.apps.single.isMissingFromDevice, isTrue);

      source.handleDeviceChange();

      expect(source.apps.single.onDevice, isNull);
    });

    test('connecting a device forgets what the last one held', () async {
      give(manifests: ['ghost'], onDisk: []);
      await source.scan();
      expect(source.apps.single.isMissingFromDevice, isTrue);

      source.handleConnect();

      expect(source.apps.single.onDevice, isNull);
    });

    // A listing that fails is not a listing that came back empty. Nothing may
    // be concluded from it - least of all that a folder's apps are gone.
    test('a folder that will not list leaves presence alone', () async {
      give(manifests: ['ghost'], onDisk: ['ghost']);
      client.failListing = '$kAppsRoot/Tools';

      await source.scan();

      expect(source.apps.single.onDevice, isNull);
    });

    test('a device with no apps at all still proves absence', () async {
      give(manifests: ['ghost'], onDisk: []);
      client.tree[kAppsRoot] = const [];

      await source.scan();

      expect(source.apps.single.isMissingFromDevice, isTrue);
    });

    // The other half of the union: an app that survives only as a backup copy,
    // its manifest gone with its .fap. This is the case the whole fix is for.
    test('a local copy with no manifest reads as missing', () async {
      give(manifests: [], onDisk: []);
      Directory(
        '${backup.path}${Platform.pathSeparator}Tools',
      ).createSync(recursive: true);
      File(
        '${backup.path}${Platform.pathSeparator}Tools'
        '${Platform.pathSeparator}orphan.fap',
      ).writeAsStringSync('not really a fap');

      await source.prime();
      await source.scan();

      final orphan = source.apps.firstWhere((a) => a.alias == 'orphan');
      expect(orphan.isMissingFromDevice, isTrue);
      expect(orphan.hasManifest, isFalse);
    });

    test('a walk cut short still syncs what it did see', () async {
      give(manifests: ['a', 'b'], onDisk: ['a']);
      client.tree[kAppsRoot] = [dir('Tools'), dir('Games')];
      client.tree['$kAppsRoot/Games'] = [fap('b.fap')];
      client.dropAfterListing = '$kAppsRoot/Tools';

      await source.scan();

      expect(source.apps.every((a) => a.onDevice == null), isTrue);
    });
  });

  group('presence follows what the app itself does', () {
    // adoptInstalled runs after every install. Without it the set still
    // describes the walk that ran before, so an app the user has just
    // installed renders as one that is missing from the device.
    test('installing an app marks it present without another walk', () async {
      give(manifests: ['tool'], onDisk: ['tool']);
      await source.scan();
      expect(source.apps.any((a) => a.alias == 'fresh'), isFalse);

      await source.adoptInstalled(
        alias: 'fresh',
        devicePath: '$kAppsRoot/Tools/fresh.fap',
        fapBytes: utf8.encode('not really a fap'),
      );

      final fresh = source.apps.firstWhere((a) => a.alias == 'fresh');
      expect(fresh.onDevice, isTrue);
    });

    test('uninstalling marks the app absent without another walk', () async {
      give(manifests: ['tool'], onDisk: ['tool']);
      await source.scan();
      final tool = source.apps.single;
      expect(tool.onDevice, isTrue);

      await source.uninstallFromDevice(tool);

      expect(engine.deleted, ['tool']);
      expect(source.apps.single.isMissingFromDevice, isTrue);
    });

    test('restoring marks the app present again', () async {
      give(manifests: ['tool'], onDisk: []);
      Directory(
        '${backup.path}${Platform.pathSeparator}Tools',
      ).createSync(recursive: true);
      File(
        '${backup.path}${Platform.pathSeparator}Tools'
        '${Platform.pathSeparator}tool.fap',
      ).writeAsStringSync('backup');
      await source.scan();
      expect(source.apps.single.isMissingFromDevice, isTrue);

      final ok = await source.restore(source.apps.single);

      expect(ok, isTrue);
      expect(source.apps.single.onDevice, isTrue);
    });

    test('a failed restore leaves the app absent', () async {
      give(manifests: ['tool'], onDisk: []);
      Directory(
        '${backup.path}${Platform.pathSeparator}Tools',
      ).createSync(recursive: true);
      File(
        '${backup.path}${Platform.pathSeparator}Tools'
        '${Platform.pathSeparator}tool.fap',
      ).writeAsStringSync('backup');
      await source.scan();
      engine.restoreSucceeds = false;

      expect(await source.restore(source.apps.single), isFalse);
      expect(source.apps.single.isMissingFromDevice, isTrue);
    });
  });
}
