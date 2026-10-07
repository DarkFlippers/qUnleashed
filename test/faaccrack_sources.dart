// Paths and contents the two faaccrack source guards share.
//
// Not a `_test.dart`: the repo's convention for test scaffolding, alongside
// `ratchet.dart` and `firmware_fixture.dart`. It exists because the two guards
// were each spelling the same four paths, and because the set of quoted includes
// the engine is allowed to have was pinned twice in two different shapes - so
// adding one meant four edits across three files and only one of them failed
// with a message that named the problem.
import 'dart:io';

const faaccrackDir = 'lib/modules/cpp/faaccrack';
const faaccrackEnginePath = '$faaccrackDir/faaccrack.c';
const faaccrackHeaderPath = '$faaccrackDir/faaccrack.h';
const faaccrackNotesPath = '$faaccrackDir/BUILD_NOTES.md';
const faaccrackKeepPath = '$faaccrackDir/keep.txt';

/// Every file this directory is allowed to contain, and where the engine's
/// quoted includes resolve.
///
/// A file under `$faaccrackDir` that is not listed here is how the private
/// engine source arrives in the repository: `.gitignore` names three basenames,
/// which stops nothing under a fourth name and nothing at all under
/// `git add -f`. An allowlist does not have to
/// predict what the file would be called.
const faaccrackAllowedFiles = {
  'faaccrack.c',
  'faaccrack.h',
  'faaccrack_bridge.c',
  'faaccrack_dispatch.c',
  'keep.txt',
  'CMakeLists.txt',
  'BUILD_NOTES.md',
  'apple/qunleashed_faaccrack.podspec',
  'apple/qunleashed_faaccrack_unity.c',
  'test/faaccrack_abi_probe.c',
};

/// Where each header the engine quote-includes actually lives.
///
/// One spelling, because the build needs these on the include path and the
/// guard needs to know they resolve. `pthread_shim.h` is the interesting one:
/// it belongs to the hardnested library, so this is the only record that
/// faaccrack's build will need that directory too.
const faaccrackQuotedIncludes = {
  'faaccrack.h': faaccrackDir,
  'pthread_shim.h': 'lib/modules/cpp/hardnested',
};

/// Where the hand-written Dart mirror of the C structs lives.
const faaccrackRecovererPath =
    'lib/pages/tools/subghz/seed/faaccrack_recoverer.dart';

/// The engine, the header, the notes and the keep list.
String faaccrackEngine() => File(faaccrackEnginePath).readAsStringSync();
String faaccrackHeader() => File(faaccrackHeaderPath).readAsStringSync();
String faaccrackRecovererSource() =>
    File(faaccrackRecovererPath).readAsStringSync();
String faaccrackDispatcherSource() =>
    File('$faaccrackDir/faaccrack_dispatch.c').readAsStringSync();
String faaccrackCMakeSource() =>
    File('$faaccrackDir/CMakeLists.txt').readAsStringSync();
String faaccrackPodspecSource() =>
    File('$faaccrackDir/apple/qunleashed_faaccrack.podspec').readAsStringSync();

/// The names the obfuscator is told to leave alone, from `keep.txt`.
///
/// Comments and blank lines dropped. The file is the argument the regeneration
/// command passes, so this reads the same thing the generator did rather than a
/// description of it.
List<String> faaccrackKeepList() =>
    File(faaccrackKeepPath)
        .readAsLinesSync()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList(growable: false);
