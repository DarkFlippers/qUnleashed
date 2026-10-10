import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/archive/storage.dart';
import 'package:qunleashed/services/storage/paths.dart';

import 'kept_lines.dart';

/// What the archive writes down about the user's own choices, and what it does
/// when it cannot.
///
/// Three of these used to be `catch (_) {}`: the last device the app was on,
/// and the two favourites lists. Each is a choice the user made, on screen and
/// gone on the next launch, with nothing anywhere to say why - a bug report
/// that reads "favourites do not save" and no line to go with it.
///
/// Nothing is waiting on any of them, so the answer is a kept log rather than
/// a surface. ADR 0008.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  late Directory root;
  late ArchiveStorage storage;

  // One root for the file, not one per case. `ArchiveStorage` caches its root
  // in a static, so a second temp directory would be created and then ignored
  // while the service went on writing into the first - which is how the first
  // version of this file came to fail from the second case onwards.
  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('archive_storage_test');
    // `userDocumentsDirectory` reads USERPROFILE or HOME directly on desktop
    // and never goes through path_provider, so this is the only hook that
    // keeps a test out of the developer's real folder.
    debugUseDocumentsRoot(root);
    storage = ArchiveStorage();
    await storage.resolveRootDir();
  });

  tearDownAll(() {
    debugUseDocumentsRoot(null);
    root.deleteSync(recursive: true);
  });

  setUp(() {
    // Empty the devices folder rather than replacing it, for the same reason.
    final devices = storage.rootDir;
    if (devices.existsSync()) {
      for (final entity in devices.listSync()) {
        entity.deleteSync(recursive: true);
      }
    } else {
      devices.createSync(recursive: true);
    }
    clearKeptLines();
  });

  bool said(String fragment) => keptLines.any((l) => l.contains(fragment));

  /// Puts a directory where [file] wants to be, so writing it fails.
  void blockFile(File file) {
    file.parent.createSync(recursive: true);
    Directory(file.path).createSync();
  }

  /// Puts a file where the device's folder wants to be, so creating it fails.
  void blockDeviceDir(String deviceName) {
    final dir = storage.deviceDir(deviceName);
    dir.parent.createSync(recursive: true);
    File(dir.path).writeAsStringSync('in the way');
  }

  group('the last device', () {
    test('is written, and read back', () async {
      await storage.writeLastDeviceName('Kitchen');

      expect(await storage.readLastDeviceName(), 'Kitchen');
      expect(said('could not remember'), isFalse);
    });

    // Losing this opens the next launch with no device and an empty archive.
    test('says so when it cannot be written', () async {
      blockFile(
        File('${storage.rootDir.path}${Platform.pathSeparator}.last_device'),
      );

      await storage.writeLastDeviceName('Kitchen');

      expect(said('could not remember the last device'), isTrue);
    });

    test('does not throw out of the write', () async {
      blockFile(
        File('${storage.rootDir.path}${Platform.pathSeparator}.last_device'),
      );

      await expectLater(storage.writeLastDeviceName('Kitchen'), completes);
    });
  });

  group('favourites', () {
    test('are written, and read back', () async {
      await storage.writeFavorites('Kitchen', {'/ext/nfc/a.nfc'});

      expect(
        await storage.readFavorites('Kitchen'),
        contains('/ext/nfc/a.nfc'),
      );
      expect(said('could not save'), isFalse);
    });

    // The star is on screen and will not be there next time.
    test('say so when they cannot be written', () async {
      blockDeviceDir('Kitchen');

      await storage.writeFavorites('Kitchen', {'/ext/nfc/a.nfc'});

      expect(said('could not save favourites for "Kitchen"'), isTrue);
    });

    test('name the device they were for', () async {
      blockDeviceDir('Bench');

      await storage.writeFavorites('Bench', {'/ext/nfc/a.nfc'});

      expect(said('"Bench"'), isTrue);
    });

    test('do not throw out of the write', () async {
      blockDeviceDir('Kitchen');

      await expectLater(
        storage.writeFavorites('Kitchen', {'/ext/nfc/a.nfc'}),
        completes,
      );
    });
  });

  group('app favourites', () {
    test('say so when they cannot be written', () async {
      blockDeviceDir('Kitchen');

      await storage.writeFapFavorites('Kitchen', const [
        (path: '/ext/apps/Tools/x.fap', name: 'X'),
      ]);

      expect(said('could not save app favourites for "Kitchen"'), isTrue);
    });
  });

  // The two that stay silent, and the reason they are allowed to: an icon is
  // fetched again when it is missing, so losing one costs a round trip rather
  // than a user's choice.
  group('a cached icon', () {
    test('says nothing when it cannot be written', () async {
      blockDeviceDir('Kitchen');

      await storage.writeFapIcon('Kitchen', '/ext/apps/Tools/x.fap', const [1]);

      expect(
        keptLines,
        isEmpty,
        reason: 'best-effort, and the budget entry says so',
      );
    });
  });
}
