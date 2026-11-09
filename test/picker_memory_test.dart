// Where a system picker opens, and that every one of them is told.
//
// Users reported that some pickers opened where they had left off and others
// at the root, and both were true: the Flibler folder pick remembered its
// folder, the nine other pickers in the app opened wherever the system put
// them - on Linux, the working directory, which for an app started from a
// launcher is often `/`. `services/storage/picker_memory.dart` gives each
// kind of pick a place that remembers its last folder and starts somewhere
// sensible before it has one.
//
// The rule at the top is what keeps the tenth picker from regressing it: a
// `FilePicker.platform` call that does not pass `initialDirectory` opens
// wherever the system likes, and nothing else in the suite would notice. A
// folder pick goes through `pickFolder`, which takes a required `place:` and
// so is held by the compiler instead.
import 'dart:io' as io;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/storage/picker_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kept_lines.dart';
import 'ratchet.dart';

/// Every `FilePicker.platform` call in [unit], and whether it says where to
/// open.
class _PickerVisitor extends RecursiveAstVisitor<void> {
  _PickerVisitor(this.unit);

  final CompilationUnit unit;
  final List<int> all = [];
  final List<int> unplaced = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (isPickerCall(node)) {
      final line = unit.lineInfo.getLocation(node.offset).lineNumber;
      all.add(line);
      if (namedArgument(node.argumentList, 'initialDirectory') == null) {
        unplaced.add(line);
      }
    }
    super.visitMethodInvocation(node);
  }
}

_PickerVisitor _visit(CompilationUnit unit) {
  final visitor = _PickerVisitor(unit);
  unit.accept(visitor);
  return visitor;
}

/// Answers Downloads with [path], or fails when it is null.
class _Downloads extends PathProviderPlatform {
  _Downloads(this.path);

  final String? path;

  @override
  Future<String?> getDownloadsPath() async =>
      path ?? (throw const io.FileSystemException('no known folder'));
}

/// Runs [body] as if on [platform], and puts the platform back after.
Future<T> _on<T>(TargetPlatform platform, Future<T> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    return await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  group('every picker under lib/', () {
    var total = 0;

    test('says where it opens', () {
      final found = countAcrossLib((unit, path) {
        final visit = _visit(unit);
        total += visit.all.length;
        return visit.unplaced;
      });
      expectWithinBudget(
        counted: found.counted,
        budget: const <String, int>{},
        sites: found.sites,
        budgetFile: 'test/picker_memory_test.dart',
        why:
            'A picker with no initialDirectory opens wherever the system '
            'likes - the root, on a Linux desktop - while the others open '
            'where the user left off, which is the inconsistency users '
            'reported. Pass `initialDirectory: await pickerStart(place)` '
            'and, once the pick succeeds, `rememberPickedFile(place, path)`. '
            'A folder pick is `pickFolder(..., place: ...)`, which does both.',
      );
      // The vacuity guard: nine `FilePicker.platform` calls when this went
      // in, and a walk that found none would pass the rule above.
      expect(total, greaterThanOrEqualTo(6));
    });
  });

  group('where a place opens the first time', () {
    test('firmware starts in Downloads, as the system names it', () {
      expect(
        firstFoldersFor(
          PickerPlace.firmware,
          windows: false,
          home: '/home/u',
          downloads: '/home/u/Загрузки',
        ),
        ['/home/u/Загрузки', '/home/u/Downloads', '/home/u'],
      );
    });

    test('and in the conventional Downloads when it does not', () {
      expect(
        firstFoldersFor(
          PickerPlace.firmware,
          windows: true,
          home: r'C:\Users\u',
        ),
        [r'C:\Users\u\Downloads', r'C:\Users\u'],
      );
    });

    test('media and paint start in Pictures', () {
      for (final place in [PickerPlace.media, PickerPlace.paint]) {
        expect(firstFoldersFor(place, windows: false, home: '/Users/u'), [
          '/Users/u/Pictures',
          '/Users/u',
        ], reason: place.name);
      }
    });

    test('Pictures on Linux is whatever user-dirs says first', () {
      expect(
        firstFoldersFor(
          PickerPlace.media,
          windows: false,
          home: '/home/u',
          xdgPictures: '/home/u/Изображения',
        ),
        ['/home/u/Изображения', '/home/u/Pictures', '/home/u'],
      );
    });

    test('Pictures on Windows tries the OneDrive copy too', () {
      expect(
        firstFoldersFor(PickerPlace.paint, windows: true, home: r'C:\Users\u'),
        [
          r'C:\Users\u\Pictures',
          r'C:\Users\u\OneDrive\Pictures',
          r'C:\Users\u',
        ],
      );
    });

    test('disk and flibler start at home, never at the root', () {
      for (final place in [PickerPlace.disk, PickerPlace.flibler]) {
        expect(
          firstFoldersFor(
            place,
            windows: false,
            home: '/home/u',
            downloads: '/home/u/Downloads',
          ),
          ['/home/u'],
          reason: place.name,
        );
      }
    });

    test('with no home there is nothing to offer', () {
      expect(
        firstFoldersFor(PickerPlace.disk, windows: false, home: null),
        isEmpty,
      );
    });
  });

  group('user-dirs.dirs', () {
    const home = '/home/u';

    test(r'a $HOME-relative entry', () {
      expect(
        parseXdgUserDir(
          '# written by xdg-user-dirs-update\n'
              'XDG_DOWNLOAD_DIR="\$HOME/Загрузки"\n'
              'XDG_PICTURES_DIR="\$HOME/Изображения"\n',
          'PICTURES',
          home,
        ),
        '/home/u/Изображения',
      );
    });

    test('an absolute entry, and a trailing slash', () {
      expect(
        parseXdgUserDir('XDG_PICTURES_DIR="/data/pics/"\n', 'PICTURES', home),
        '/data/pics',
      );
    });

    test('an entry equal to home is switched off, not home', () {
      expect(
        parseXdgUserDir('XDG_PICTURES_DIR="\$HOME/"\n', 'PICTURES', home),
        isNull,
      );
    });

    test('a relative entry or a missing one answers null', () {
      expect(
        parseXdgUserDir('XDG_PICTURES_DIR="pics"\n', 'PICTURES', home),
        isNull,
      );
      expect(
        parseXdgUserDir('XDG_MUSIC_DIR="\$HOME/m"\n', 'PICTURES', home),
        isNull,
      );
    });
  });

  group('pickerStart and remembering', () {
    late io.Directory scratch;
    final originalPaths = PathProviderPlatform.instance;

    setUp(() {
      recordKeptLines();
      SharedPreferences.setMockInitialValues({});
      scratch = io.Directory.systemTemp.createTempSync('picker_memory');
    });
    tearDown(() {
      PathProviderPlatform.instance = originalPaths;
      scratch.deleteSync(recursive: true);
    });

    for (final mobile in const [TargetPlatform.android, TargetPlatform.iOS]) {
      test('on ${mobile.name} nothing is passed and nothing is kept', () async {
        await _on(mobile, () async {
          await rememberPickerFolder(PickerPlace.disk, scratch.path);
          expect(await pickerStart(PickerPlace.disk), isNull);
        });
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getKeys(), isEmpty);
      });
    }

    test('a desktop opens where the place was last used', () async {
      final picked = io.File('${scratch.path}/firmware.tgz')..createSync();
      final start = await _on(TargetPlatform.linux, () async {
        await rememberPickedFile(PickerPlace.firmware, picked.path);
        return pickerStart(PickerPlace.firmware);
      });
      expect(start, scratch.path);
      expect(keptLines, isEmpty);
    });

    test('and each place remembers its own', () async {
      final other = io.Directory('${scratch.path}/other')..createSync();
      PathProviderPlatform.instance = _Downloads(other.path);
      final start = await _on(TargetPlatform.linux, () async {
        await rememberPickerFolder(PickerPlace.disk, scratch.path);
        return pickerStart(PickerPlace.firmware);
      });
      expect(start, other.path);
    });

    test('a remembered folder that is gone falls back', () async {
      PathProviderPlatform.instance = _Downloads(scratch.path);
      SharedPreferences.setMockInitialValues({
        'picker_last_firmware': '${scratch.path}/unplugged-drive',
      });
      final start = await _on(
        TargetPlatform.linux,
        () => pickerStart(PickerPlace.firmware),
      );
      expect(start, scratch.path);
    });

    test('Flibler keeps the key it had before this file', () async {
      SharedPreferences.setMockInitialValues({
        'flibler_last_folder': scratch.path,
      });
      final start = await _on(
        TargetPlatform.macOS,
        () => pickerStart(PickerPlace.flibler),
      );
      expect(start, scratch.path);
    });

    test('a system that will not name Downloads is kept, and the pick still '
        'opens', () async {
      PathProviderPlatform.instance = _Downloads(null);
      final start = await _on(
        TargetPlatform.linux,
        () => pickerStart(PickerPlace.firmware),
      );
      // Home/Downloads or home itself, whichever this machine has - never
      // null on a runner with a HOME, and never the root.
      expect(start, isNotNull);
      expect(start, isNot('/'));
      expect(keptLines, hasLength(1));
      expect(keptLines.single, contains('would not name Downloads'));
      expect(keptLevels, [KeptLevel.caught]);
    });
  });
}
