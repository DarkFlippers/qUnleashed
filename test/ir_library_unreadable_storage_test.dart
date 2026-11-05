// A library folder the OS will not enumerate, which is what Android hands a
// run that has no MANAGE_EXTERNAL_STORAGE: the resources folder answers
// exists() and then refuses the listing with errno 1.
//
// QUNLEASHED-J is that refusal reaching Sentry as an error from the startup
// recovery pass - a permission the user declined, reported as a failure of the
// IR library. It cost more than the report: `IrLibController.initialize` awaits
// the same memoised pass with no catch of its own, so the IR page stayed in its
// initial state for the session.
//
// The refusal cannot be arranged on a real filesystem portably - `dart:io`
// cannot set mode bits, Windows has no equivalent, and on POSIX CI the test
// process is privileged enough to ignore them - so it is injected at the seam
// these paths read through: the Directory the repo was handed, and the parent
// it derives from it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/infrared/local_repo.dart';
import 'package:qunleashed/services/logging.dart';

import 'kept_lines.dart';

final String sep = Platform.pathSeparator;

/// A directory that is plainly there and will not say what is in it.
///
/// Forwards only the four members these paths touch and lets everything else
/// reach `super.noSuchMethod` - so a refactor onto `listSync` or `stat` fails
/// with a `NoSuchMethodError`, which is deliberately *not* a
/// `FileSystemException` and so cannot be swallowed by the code under test.
///
/// Its parent always refuses, which is what makes the two scenarios: a root
/// that refuses for `exists()`, and a readable root whose parent refuses for
/// the recovery pass. `rootRefuses`/`parentRefuses` in `main` name them, so no
/// test has to read a bare boolean to tell which it is in.
class _RefusingDirectory implements Directory {
  _RefusingDirectory(this._real, {required this.refusesListing});

  final Directory _real;
  final bool refusesListing;

  @override
  String get path => _real.path;

  @override
  Directory get parent =>
      _RefusingDirectory(_real.parent, refusesListing: true);

  @override
  Future<bool> exists() => _real.exists();

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    if (!refusesListing) {
      return _real.list(recursive: recursive, followLinks: followLinks);
    }
    return Stream<FileSystemEntity>.error(
      PathAccessException(
        path,
        const OSError('Operation not permitted', 1),
        'Directory listing failed',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory base;
  late Directory root;

  setUp(() {
    recordKeptLines();
    base = Directory.systemTemp.createTempSync('ir_unreadable_test');
    root = Directory('${base.path}${sep}irlib');
  });

  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  void useRoot(Directory dir) {
    IrLibLocalRepo.debugUseRoot(dir);
    addTearDown(() => IrLibLocalRepo.debugUseRoot(null));
  }

  /// The library itself will not list - what `exists()` runs into.
  void rootRefuses() {
    root.createSync(recursive: true);
    useRoot(_RefusingDirectory(root, refusesListing: true));
  }

  /// The library reads fine and the folder it sits in will not list - what the
  /// recovery pass and a delete run into, since both look for the sidecars
  /// beside the library rather than inside it.
  void parentRefuses() =>
      useRoot(_RefusingDirectory(root, refusesListing: false));

  /// A superseded tree with a marker, so a delete-and-recreate cannot pass for
  /// a tree that was left alone.
  Directory supersededTree(String marker) {
    final dir = Directory('${root.path}.superseded.2000')
      ..createSync(recursive: true);
    File('${dir.path}${sep}tv.ir').writeAsStringSync(marker);
    return dir;
  }

  String markerIn(Directory dir) =>
      File('${dir.path}${sep}tv.ir').readAsStringSync();

  /// The refusal that was kept, at the level a declined permission gets.
  ///
  /// No assertion on how many: `LogService` folds a consecutive repeat, so a
  /// count here could not tell "said once" from "said twice" anyway.
  String theKeptLine() {
    expect(
      keptLines,
      isNotEmpty,
      reason: 'the refusal is the only record anyone gets of it',
    );
    expect(
      keptLevels,
      everyElement(KeptLevel.caught),
      reason: 'a permission the user declined is not worth an alert',
    );
    return keptLines.first;
  }

  group('a library the OS will not list', () {
    test('reads as absent rather than throwing', () async {
      rootRefuses();

      expect(
        await IrLibLocalRepo().exists(),
        isFalse,
        reason: 'a library this process cannot read is no library to the app',
      );
    });

    test('says what was decided, over the folder and the errno', () async {
      rootRefuses();

      await IrLibLocalRepo().exists();
      final line = theKeptLine();

      // The decision, which the exception cannot state and which is the whole
      // reason the page then offers a download over a library that is there.
      expect(line, contains('reading the library as absent'));
      // The path pins the site: root.path is strictly longer than base.path,
      // so the recovery pass's line could not satisfy this.
      expect(line, contains(root.path));
      // And the errno, which is what tells a report about an absent library
      // from a report about a declined permission. It rides in on the
      // exception rather than being restated by the message.
      expect(line, contains('errno = 1'));
    });
  });

  group('the startup recovery pass', () {
    test('keeps the library it cannot see, and reports no strand', () async {
      // Root absent with a superseded tree beside it is the signature of an
      // interrupted swap - the one state in which the sweep could delete the
      // only copy of the library there is.
      final live = supersededTree('live');
      parentRefuses();

      // The pass is started by `guarded`, so a rejection here is exactly the
      // Sentry report being fixed.
      expect(await IrLibLocalRepo.recoverStranded(), isNull);

      expect(
        markerIn(live),
        'live',
        reason: 'a tree the listing never returned must not be swept up',
      );
      expect(
        IrLibLocalRepo.strandedLibrary.value,
        isNull,
        reason: 'nothing was stranded by this pass, so none was recorded',
      );

      final line = theKeptLine();
      expect(line, contains('leaving the library untouched'));
      expect(line, contains(base.path));
      expect(line, contains('errno = 1'));
    });
  });

  group('a delete the user asked for', () {
    test('is refused outright rather than half done', () async {
      // The order in _deleteAll is load-bearing: root gone while a superseded
      // tree still stands is the signature recoverInterrupted reads as an
      // interrupted swap, so the next pass would hand the deleted library
      // straight back. Answering the refusal with an empty list would produce
      // exactly that, so the refusal has to leave instead.
      final live = supersededTree('live');
      root.createSync(recursive: true);
      File('${root.path}${sep}tv.ir').writeAsStringSync('current');
      parentRefuses();

      await expectLater(
        IrLibLocalRepo().deleteAll(),
        throwsA(isA<PathAccessException>()),
      );

      expect(
        root.existsSync(),
        isTrue,
        reason: 'the library must not go while its sidecars cannot be found',
      );
      expect(markerIn(live), 'live');
      expect(
        keptLines,
        isEmpty,
        reason: 'the delete reports itself through the exception it threw',
      );
    });
  });
}
