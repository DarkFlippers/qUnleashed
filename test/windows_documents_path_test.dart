// Where the app puts its folder on Windows, and what happens when the OS
// will not say.
//
// `userDocumentsDirectory` used to answer `%USERPROFILE%\Documents` on
// Windows, which is a guess. OneDrive's Known Folder Move redirects Documents
// into `%USERPROFILE%\OneDrive\Documents` and the old path stops existing, and
// the folder can be moved by hand to another drive. Every path in
// `paths.dart` hangs off this one, so on such a machine nothing that keeps a
// file works: `PathNotFoundException: Creation failed ... errno = 2`, which is
// QUNLEASHED-5 and was still arriving from Windows 10 builds while this was
// written.
//
// So Windows is asked. `getApplicationDocumentsPath` there is
// `getPath(WindowsKnownFolder.Documents)` - `SHGetKnownFolderPath` for
// `FOLDERID_Documents` - which is the one answer that follows a redirect.
// Checked in `path_provider_windows` rather than assumed, because the same
// call on macOS returns the *sandbox* container's Documents, which is the
// opposite of what this app wants: users back up their own key dumps with a
// file manager, and a container is invisible to one. macOS and Linux still
// read `HOME`.
//
// ## What this file can and cannot reach
//
// The call site is behind `io.Platform.isWindows` and CI runs the suite on
// ubuntu, so these go through `debugWindowsDocumentsDirectory` instead - the
// helper itself, which has no platform check of its own. That covers the new
// code's two branches on every runner.
//
// What no test here covers is the wiring: that Windows reaches the helper and
// macOS does not. A platform-gated case would be vacuous on CI, which this
// repository treats as worse than no case at all, and there is no precedent
// for one - nothing under `test/` reads `Platform.isWindows`. The manual check
// is a Windows machine with Documents moved: the app's folder should appear
// beside it rather than the app failing to start its archive.
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qunleashed/services/storage/paths.dart';

import 'kept_lines.dart';

/// Answers with [path], or null to make `path_provider` throw its own
/// `MissingPlatformDirectoryException`.
class _Documents extends PathProviderPlatform {
  _Documents(this.path);

  final String? path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// A platform that fails rather than answers.
class _Refuses extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      throw const io.FileSystemException('no known folder');
}

void main() {
  setUp(recordKeptLines);

  final original = PathProviderPlatform.instance;
  tearDown(() => PathProviderPlatform.instance = original);

  test('takes the folder Windows names', () async {
    PathProviderPlatform.instance = _Documents(
      r'D:\Redirected\OneDrive\Documents',
    );

    final found = await debugWindowsDocumentsDirectory();

    expect(found, isNotNull);
    expect(found!.path, r'D:\Redirected\OneDrive\Documents');
    expect(
      keptLines,
      isEmpty,
      reason: 'the ordinary answer is not worth a line',
    );
  });

  test('falls back when the platform names nothing', () async {
    // `path_provider` turns a null path into `MissingPlatformDirectoryException`
    // rather than returning null, so this is the same branch as a throw from
    // the caller's side - and it has to be, or a machine with no known folder
    // would take an exception out of app start.
    PathProviderPlatform.instance = _Documents(null);

    expect(await debugWindowsDocumentsDirectory(), isNull);
    expect(
      keptLines.where((l) => l.contains('[Paths] Windows would not name')),
      hasLength(1),
      reason:
          'the fallback is usable and silent to the user, but a machine that '
          'cannot name its own known folder is what to look at when the '
          'fallback fails too',
    );
  });

  test('falls back when the platform answers with nothing at all', () async {
    // Not the same as null, which path_provider turns into a throw. An empty
    // string comes back as `Directory('')`, and `appDocumentsDirectory`
    // would then build `qUnleashed` relative to the process's working
    // directory - the app writing the user's keys beside its own executable.
    PathProviderPlatform.instance = _Documents('');

    expect(await debugWindowsDocumentsDirectory(), isNull);
  });

  test('falls back when the platform throws', () async {
    PathProviderPlatform.instance = _Refuses();

    expect(await debugWindowsDocumentsDirectory(), isNull);
    expect(
      keptLines.where((l) => l.contains('[Paths] Windows would not name')),
      hasLength(1),
    );
  });

  test('the app still has somewhere to put its folder', () async {
    // Whatever this runner is, and whichever branch it took. Without it the
    // three cases above could all pass against a `userDocumentsDirectory`
    // that had stopped returning anything usable.
    PathProviderPlatform.instance = _Refuses();

    final documents = await userDocumentsDirectory();

    expect(documents.path, isNotEmpty);
    expect(
      documents.path,
      contains('Documents'),
      reason:
          'every platform here ends at a Documents folder - the sandbox '
          'container is deliberately not a fallback',
    );
  });
}
