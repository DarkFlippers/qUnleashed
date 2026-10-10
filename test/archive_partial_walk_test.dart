import 'dart:async';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flipperlib/flipperlib.dart' as fl show File;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/archive/models/key.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/services/archive/storage.dart';
import 'package:qunleashed/services/storage/paths.dart';

import 'kept_lines.dart';

/// Reconciling what is on the Flipper against what is on the phone, when the
/// walk did not get to see all of it.
///
/// Seven of the eight categories are searched recursively, and the walk used
/// to swallow a failed listing and hand back whatever it had. Everything the
/// user held locally in that category was then marked deleted - one RPC
/// timeout, or a BUSY while the Flipper runs an app, and the NFC tab reads as
/// gone. #109.
const _device = 'TestFlipper';
const _nfcRoot = '/ext/nfc';

class _WalkingFlipper implements FlipperClient {
  /// Directory path -> the entries it holds.
  final Map<String, List<fl.File>> tree = {};

  /// Paths whose listing fails outright, as one does for a card pulled out or
  /// a Flipper that is busy running an app.
  final Set<String> refuses = {};

  final List<String> listed = [];

  final _connection = StreamController<FlipperConnectionState>.broadcast();
  final _info = StreamController<Map<String, String>>.broadcast();

  Future<void> close() async {
    await _connection.close();
    await _info.close();
  }

  /// initialize() subscribes to both before its first refresh; nothing here
  /// ever pushes to them.
  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  Stream<Map<String, String>> get deviceInfoUpdates => _info.stream;

  @override
  bool get isConnected => true;

  @override
  bool get isRpcReady => true;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  @override
  String? getName() => _device;

  @override
  Future<String> awaitName() async => _device;

  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  List<Main> _framesFor(Main request) {
    if (!request.hasStorageListRequest()) return const [];
    final path = request.storageListRequest.path;
    listed.add(path);
    if (refuses.contains(path)) {
      throw StateError('ERROR_STORAGE_NOT_READY');
    }
    return [
      Main(
        storageListResponse: ListResponse()
          ..file.addAll(tree[path] ?? const []),
      ),
    ];
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

fl.File dir(String name) => fl.File(name: name, type: File_FileType.DIR);

fl.File tag(String name) =>
    fl.File(name: name, type: File_FileType.FILE, size: 64);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  late io.Directory root;
  late _WalkingFlipper client;
  late ArchiveStorage storage;
  late ArchiveController ctrl;

  // ArchiveStorage caches its root in a static, so the root is set once for
  // the file and the device folder is rebuilt between cases.
  setUpAll(() {
    root = io.Directory.systemTemp.createTempSync('archive_partial_walk');
    debugUseDocumentsRoot(root);
    // The migration of the pre-Devices layout runs at the top of every
    // refresh and asks path_provider where the old folders were. Unanswered
    // it throws, and the whole refresh ends in the catch below it.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '${root.path}${io.Platform.pathSeparator}legacy',
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    debugUseDocumentsRoot(null);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Writes a local copy of an NFC tag, which is what the reconcile decides
  /// the fate of.
  void localTag(String name, {String subFolder = ''}) {
    final dir = storage.categoryDir(
      _device,
      ArchiveCategory.nfc,
      subFolder: subFolder,
    )..createSync(recursive: true);
    io.File('${dir.path}${io.Platform.pathSeparator}$name.nfc')
        .writeAsStringSync('Filetype: Flipper NFC device\n');
  }

  setUp(() async {
    client = _WalkingFlipper();
    storage = ArchiveStorage();
    // resolveRootDir caches into a static and every path getter asserts on
    // it, so it has to be awaited before the first deviceDir of the case.
    await storage.resolveRootDir();
    final device = storage.deviceDir(_device);
    if (device.existsSync()) device.deleteSync(recursive: true);
    await storage.writeLastDeviceName(_device);
    ctrl = ArchiveController(client: client, storage: storage);
    clearKeptLines();
    addTearDown(() async {
      ctrl.dispose();
      await client.close();
    });
  });

  /// Opens the archive the way the page does. Not refresh() on its own: the
  /// device name is read here, and without it a refresh empties the map and
  /// returns before any of this is reached.
  Future<void> open() => ctrl.initialize();

  Iterable<String> lines(String fragment) =>
      keptLines.where((l) => l.contains(fragment));

  /// Read through the two lists the UI itself reads, rather than the map
  /// behind them: "shows as deleted" is what the bug is about.
  bool readsAsDeleted(String name) =>
      ctrl.deletedKeys().any((k) => k.name == name);

  ArchiveKey? nfcKey(String name) => ctrl
      .keysFor(ArchiveCategory.nfc)
      .where((k) => k.name == name)
      .firstOrNull;

  group('a listing the Flipper refused', () {
    // The reported bug, in its plainest form: one failed storageList at the
    // top of the category, and everything the user has locally reads as gone.
    test('does not turn the whole category into deleted keys', () async {
      localTag('home');
      localTag('work');
      client.refuses.add(_nfcRoot);

      await open();

      expect(readsAsDeleted('home'), isFalse);
      expect(readsAsDeleted('work'), isFalse);
    });

    test('leaves the keys it could not check alone entirely', () async {
      localTag('home');
      client.refuses.add(_nfcRoot);

      await open();

      expect(nfcKey('home'), isNotNull);
    });

    // A folder deeper in the tree failing must not take the rest with it.
    test('only holds back the folder it happened in', () async {
      localTag('home');
      localTag('spare', subFolder: 'Locks');
      client.tree[_nfcRoot] = [tag('home.nfc'), dir('Locks')];
      client.refuses.add('$_nfcRoot/Locks');

      await open();

      expect(nfcKey('home')?.state, ArchiveKeyState.synced);
      expect(readsAsDeleted('spare'), isFalse);
    });

    // Under the walked folder rather than in it: holding back only the exact
    // path that failed would leave everything below it reconciled against a
    // listing that never happened.
    test('holds back what is underneath it too', () async {
      localTag('spare', subFolder: 'Locks/2024');
      client.tree[_nfcRoot] = [dir('Locks')];
      client.refuses.add('$_nfcRoot/Locks');

      await open();

      expect(readsAsDeleted('spare'), isFalse);
    });

    // A sibling whose name merely starts the same way is a different folder.
    // Comparing paths as text rather than by segment quietly holds it back
    // too, and nothing in that folder is ever reconciled again.
    test('does not hold back a folder that only shares its prefix', () async {
      localTag('old', subFolder: 'LocksOld');
      client.tree[_nfcRoot] = [dir('Locks'), dir('LocksOld')];
      client.tree['$_nfcRoot/LocksOld'] = const [];
      client.refuses.add('$_nfcRoot/Locks');

      await open();

      expect(readsAsDeleted('old'), isTrue);
    });

    // The other half of "only": a folder that did list is still reconciled,
    // so a file genuinely gone from it is still marked gone. All-or-nothing
    // would leave it alone and call that safe.
    test('still reconciles the folders that did list', () async {
      localTag('home');
      localTag('spare', subFolder: 'Locks');
      client.tree[_nfcRoot] = [dir('Locks')];
      client.refuses.add('$_nfcRoot/Locks');

      await open();

      expect(readsAsDeleted('home'), isTrue);
      expect(readsAsDeleted('spare'), isFalse);
    });
  });

  group('a walk that saw everything', () {
    // The behaviour the guard must not cost: a file really removed from the
    // Flipper still has to read as deleted.
    test('still marks a file the Flipper no longer has', () async {
      localTag('home');
      client.tree[_nfcRoot] = const [];

      await open();

      expect(readsAsDeleted('home'), isTrue);
    });

    // The subtle one. A folder that is simply gone was never listed either,
    // and a rule written as "only reconcile what was listed" would leave its
    // keys untouched for ever.
    test('marks a whole folder the user deleted on the device', () async {
      localTag('spare', subFolder: 'Locks');
      client.tree[_nfcRoot] = const [];

      await open();

      expect(readsAsDeleted('spare'), isTrue);
    });

    test('says nothing about folders it could not read', () async {
      localTag('home');
      client.tree[_nfcRoot] = [tag('home.nfc')];

      await open();

      expect(lines('could not be listed'), isEmpty);
    });
  });

  group('what the log gets', () {
    // One line for the walk. The per-directory lines below it are info and
    // stay there: a degrading link over a whole SD card would put hundreds of
    // them into a five-hundred entry history.
    test('is one line per walk, not one per folder', () async {
      client.tree[_nfcRoot] = [dir('Locks'), dir('Cards')];
      client.refuses
        ..add('$_nfcRoot/Locks')
        ..add('$_nfcRoot/Cards');

      await open();

      expect(lines('could not be listed'), hasLength(1));
      expect(lines('2 folder(s)'), hasLength(1));
    });

    test('names the category it happened in', () async {
      client.refuses.add(_nfcRoot);

      await open();

      expect(lines(ArchiveCategory.nfc.name), isNotEmpty);
    });
  });
}
