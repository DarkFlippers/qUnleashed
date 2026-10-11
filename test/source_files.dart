// Asking git which source files exist.
//
// Split out of `test/ratchet.dart` so a test that wants a file list does not
// pay for `package:analyzer`. The ratchets parse Dart and need it; the tests
// that only want the list - `local_defines_test.dart` and
// `font_glyph_coverage_test.dart` - do not, and importing it costs each of
// them about 0.4 s of isolate start-up for nothing. `ratchet.dart` re-exports
// this file, so the seven ratchets import it exactly as before.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files matching [pathspec] that git can see, tracked or not.
///
/// `--others --exclude-standard` as well as the index, because a file that has
/// not been added yet is exactly the one its author is about to run this
/// against. Without it a local run before `git add` is a false green - which is
/// how the formatting check on the first ratchet came to be missed.
///
/// Takes the pathspec because `test/local_defines_test.dart` wants the same
/// question asked of a different glob, and had a verbatim copy of this
/// function until it did. The pathspec is the only part that differs.
List<String> gitVisibleFiles(String pathspec) {
  final result = Process.runSync('git', [
    'ls-files',
    '-z',
    '--cached',
    '--others',
    '--exclude-standard',
    '--',
    pathspec,
  ]);
  expect(result.exitCode, 0, reason: 'git ls-files failed: ${result.stderr}');
  return (result.stdout as String)
      .split(String.fromCharCode(0))
      .where((path) => path.isNotEmpty)
      .toList();
}

/// Dart under `lib/` that git can see, tracked or not.
List<String> dartFilesUnderLib() => gitVisibleFiles('lib/*.dart');
