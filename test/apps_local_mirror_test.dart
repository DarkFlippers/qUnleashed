import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/pages/apps/data/device_source.dart';
import 'package:qunleashed/pages/apps/data/install_engine.dart';
import 'package:qunleashed/pages/apps/data/manifest_registry.dart';

import 'kept_lines.dart';

/// Reading the mirror of what is installed, and what it says when it cannot.
///
/// The list this walk builds is shown as the whole truth: an app missing from
/// it renders as one that is not installed, and a file it could not size
/// renders as zero bytes with no date. Both used to happen behind an empty
/// catch, so the screen was wrong and nothing anywhere said why. ADR 0008.
final sep = io.Platform.pathSeparator;

/// A device that is simply not connected, which is the state a mirror read
/// runs in before the link is up. Everything the read does not ask for falls
/// to [noSuchMethod], so a read that starts reaching elsewhere fails loudly.
class _OfflineFlipper implements FlipperClient {
  @override
  bool get isConnected => false;

  @override
  bool get isRpcReady => false;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  @override
  DeviceToken get deviceToken => DeviceToken.fixed(current: true);

  @override
  String? getName() => 'TestFlipper';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A mirror directory whose listing can stop part-way, the way a card pulled
/// mid-walk or a folder that loses its permissions does.
class _MirrorDir implements io.Directory {
  _MirrorDir(this.path, this.entries, {this.stopAfter});

  @override
  final String path;

  final List<io.FileSystemEntity> entries;

  /// Fails the walk once this many entries are out. Null walks to the end.
  final int? stopAfter;

  @override
  Future<bool> exists() async => true;

  @override
  Stream<io.FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    var out = 0;
    for (final entry in entries) {
      if (out == stopAfter) {
        throw const io.FileSystemException('the card went away');
      }
      out++;
      yield entry;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A real file on disk that may refuse to be stat'ed. The path is real so the
/// parse pass behind the walk reads the same bytes it would in the app.
class _MirroredFap implements io.File {
  _MirroredFap(this.path, {this.statFails = false});

  @override
  final String path;

  final bool statFails;

  @override
  io.Directory get parent =>
      io.Directory(path.substring(0, path.lastIndexOf(sep)));

  @override
  Future<io.FileStat> stat() {
    if (statFails) throw const io.FileSystemException('will not stat');
    return io.File(path).stat();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  late io.Directory root;
  late DeviceSource source;
  late int logBase;

  /// Writes a real `.fap` under the mirror and hands back the entry the walk
  /// will see for it.
  _MirroredFap mirrored(String alias, {bool statFails = false}) {
    final folder = io.Directory('${root.path}${sep}Tools');
    folder.createSync(recursive: true);
    final path = '${folder.path}$sep$alias.fap';
    io.File(path).writeAsStringSync('not really a fap');
    return _MirroredFap(path, statFails: statFails);
  }

  void mirrorHolds(List<io.FileSystemEntity> entries, {int? stopAfter}) {
    final dir = _MirrorDir(root.path, entries, stopAfter: stopAfter);
    DeviceSource.backupDirectory = (_) async => dir;
  }

  setUp(() {
    root = io.Directory.systemTemp.createTempSync('apps_local_mirror');
    final client = _OfflineFlipper();
    source = DeviceSource(
      client: client,
      api: AppsCatalogApi(),
      manifests: ManifestRegistry(client: client),
      engine: _UnusedEngine(),
    );
    clearKeptLines();
    logBase = keptLines.length;
    addTearDown(() {
      DeviceSource.backupDirectory = null;
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
  });

  Iterable<String> lines(String fragment) =>
      keptLines.skip(logBase).where((l) => l.contains(fragment));

  bool said(String fragment) => lines(fragment).isNotEmpty;

  group('a walk that stops part-way', () {
    test('says so, rather than passing off what it got as all of it', () async {
      mirrorHolds([mirrored('a'), mirrored('b'), mirrored('c')], stopAfter: 1);

      await source.prime();

      expect(said('stopped reading installed apps early'), isTrue);
    });

    // The reason the line has to exist: the shorter list is not marked as
    // short anywhere the user can see. These two apps are on the device and
    // the screen has already forgotten them.
    test('still shows the shorter list as the whole list', () async {
      mirrorHolds([mirrored('a'), mirrored('b'), mirrored('c')], stopAfter: 1);

      await source.prime();

      expect(source.apps.map((a) => a.alias), ['a']);
    });

    test('says nothing when the walk reaches the end', () async {
      mirrorHolds([mirrored('a'), mirrored('b')]);

      await source.prime();

      expect(said('stopped reading installed apps early'), isFalse);
      expect(source.apps.map((a) => a.alias), ['a', 'b']);
    });
  });

  group('files the walk cannot size', () {
    // Counted for the walk rather than named one by one: a folder the device
    // will not stat fails every file under it for the one reason, and the
    // count is what says how much of the screen is wrong.
    test('are reported with how many there were', () async {
      mirrorHolds([
        mirrored('a', statFails: true),
        mirrored('b'),
        mirrored('c', statFails: true),
      ]);

      await source.prime();

      expect(said('could not size 2 installed file(s)'), isTrue);
    });

    test('are still listed, at a size of zero', () async {
      mirrorHolds([mirrored('a', statFails: true)]);

      await source.prime();

      expect(source.apps.single.alias, 'a');
      expect(source.apps.single.size, 0);
    });

    test('say nothing when every file sizes', () async {
      mirrorHolds([mirrored('a'), mirrored('b')]);

      await source.prime();

      expect(said('could not size'), isFalse);
    });
  });
}

/// A mirror read never touches the install engine. Answering its calls with
/// null would hide a read that started to.
class _UnusedEngine implements InstallEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('engine.${invocation.memberName}');
}
