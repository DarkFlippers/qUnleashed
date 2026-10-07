// Paths and contents the native source guards share.
//
// Not a `_test.dart`: the repo's convention for test scaffolding, alongside
// `ratchet.dart` and `firmware_fixture.dart`. It exists because the guards were
// each spelling the same paths, and because the set of quoted includes the
// engine is allowed to have was pinned twice in two different shapes - so adding
// one meant four edits across three files and only one of them failed with a
// message that named the problem.
//
// Most of it is faaccrack's, which is the library with an allowlist and a keep
// list. It stopped being only faaccrack's when a second library's header gained
// a mirror in the same Dart file: see [nativeBindingPath] and
// `docs/adr/0015-hand-written-ffi-bindings.md`. A path added here rather than
// spelled locally is one fewer place a move has to find.
import 'dart:io';

const faaccrackDir = 'lib/modules/cpp/faaccrack';
const hardnestedDir = 'lib/modules/cpp/hardnested';
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
  'pthread_shim.h': hardnestedDir,
};

/// Where the hand-written Dart mirror of `faaccrack_result` lives. Its sibling
/// mirror of `faaccrack_progress` moved to [nativeBindingPath], because
/// hardnested reads the same words - see
/// `docs/adr/0015-hand-written-ffi-bindings.md`.
const faaccrackRecovererPath =
    'lib/pages/tools/subghz/seed/faaccrack_recoverer.dart';

/// The shared Dart mirror of both progress channels, and the plumbing every
/// native feature loads its library through.
const nativeBindingPath = 'lib/services/native.dart';

/// The hardnested progress channel, whose struct [nativeBindingPath] mirrors
/// the first three words of.
const hardnestedProgressHeaderPath = '$hardnestedDir/qunleashed_hn_progress.h';

/// The engine, the header, the notes and the keep list.
String faaccrackEngine() => File(faaccrackEnginePath).readAsStringSync();
String faaccrackHeader() => File(faaccrackHeaderPath).readAsStringSync();
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
