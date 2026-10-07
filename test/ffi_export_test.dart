// A guard on the wiring that keeps the native FFI entry points reachable on
// Apple.
//
// The bug this was written for shipped: on iOS and macOS the qunleashed_mfkey32
// sources compile straight into the Runner executable rather than into a shared
// library, and ld64 roots an executable's dead-stripping at the entry point, not
// at its exported globals. Nothing in Swift or Obj-C calls these - only Dart
// does, by name, at runtime, through DynamicLibrary.process() - so the linker
// saw four unreachable functions and dropped them. Every MIFARE recovery path
// was dead on both Apple platforms, and the one that said anything blamed the
// build. `used` on QUNLEASHED_EXPORT is what keeps them.
//
// That fix is two tokens in a macro and five source entries in two pbxproj
// files, and nothing else in the tree notices if either goes. The release job
// checks the linked binary (`.github/scripts/check_ffi_exports.sh`), but that
// runs on a tag, on a machine this project does not have, after a full Xcode
// build - so it is the backstop. These are the checks that can run on every PR
// on Linux, which is where a "simplification" of the macro would be caught.
//
// What it cannot see:
//
//  * Whether the linker actually kept the symbols. That is the whole point of
//    the release-time check; this one only pins the inputs.
//  * Whether the hardnested pod is still embedded in the bundle. It is wired
//    through CocoaPods rather than the pbxproj, and a Podfile that still names
//    the pod says nothing about what ends up in the app.
//  * A fifth entry point added to the C without a Dart caller, or the reverse.
//    The release-time guard derives its list from the C, so it would cover the
//    first; neither covers the second.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The bridges whose exported symbols Dart resolves at runtime. They all share
/// the macro, so they all carry the same risk the day one of them stops being
/// built as a shared library.
const _bridges = [
  'lib/modules/cpp/mfkey32/mfkey32_bridge.c',
  'lib/modules/cpp/mfkey32/nested_bridge.c',
  'lib/modules/cpp/hardnested/qunleashed_hardnested_bridge.c',
  'lib/modules/cpp/faaccrack/faaccrack_bridge.c',
];

/// The sources the Apple Runner targets must still compile. Dropping one is
/// silent: the app builds, installs and runs, and only the MIFARE tools fail.
const _appleSources = ['mfkey32_bridge.c', 'nested_bridge.c'];

const _appleProjects = [
  'ios/Runner.xcodeproj/project.pbxproj',
  'macos/Runner.xcodeproj/project.pbxproj',
];

void main() {
  group('QUNLEASHED_EXPORT', () {
    for (final path in _bridges) {
      test('$path keeps `used`', () {
        final source = File(path).readAsStringSync();
        // The _WIN32 branch is dllexport, which already implies retention; it
        // is the else branch that has to say so.
        final attribute = RegExp(
          r'#define\s+QUNLEASHED_EXPORT\s+__attribute__\(\((.*)\)\)',
        ).firstMatch(source);
        expect(
          attribute,
          isNotNull,
          reason: 'no __attribute__ form of QUNLEASHED_EXPORT in $path',
        );
        expect(
          attribute!.group(1),
          contains('used'),
          reason:
              'Dropping `used` strips these symbols out of the Apple Runner '
              'binary. visibility("default") does not keep them - it says who '
              'may see the symbol, not that the linker must emit it.',
        );
      });
    }
  });

  group('Apple Runner targets', () {
    for (final project in _appleProjects) {
      for (final source in _appleSources) {
        test('$project still compiles $source', () {
          final text = File(project).readAsStringSync();
          // Counting the bare filename is not enough: it appears four times,
          // and two of those (the PBXFileReference and the group listing) are
          // just the file being visible in Xcode's navigator. Only `<name> in
          // Sources` tracks compilation - once declaring the PBXBuildFile, once
          // listing that build file in the target's Sources phase. Drop either
          // and the file stops being compiled while still reading, to anyone
          // skimming the project, as though it were.
          expect(
            '$source in Sources'.allMatches(text).length,
            2,
            reason:
                '$source must be declared as a PBXBuildFile and listed in the '
                'Sources build phase of $project, or it is not compiled into '
                'Runner and its symbols cannot be looked up at runtime.',
          );
        });
      }
    }
  });

  test('every native lookup reports a missing symbol the same way', () {
    // lookupFunction signals a missing symbol with a bare ArgumentError, which
    // this codebase cannot tell apart from an FFI allocation failure or a
    // refused dictionary entry. Three of the four call sites used to let it
    // through, so one stripped build aborted two screens with a generic failure
    // and told a third it was the build's fault. They go through
    // lookupNativeFunction now, which turns it into NativeEngineUnavailable.
    //
    // Counted in pairs rather than forbidden outright, because the wrapper takes
    // the lookup as a callback - the analyzer will not accept a type variable
    // for lookupFunction's native signature, so the call has to stay written out
    // at each site. What this pins is that the two appear the same number of
    // times per file. It cannot see that a given wrapper encloses a given
    // lookup; a file with one of each, wrongly arranged, would pass.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalised = entity.path.replaceAll(r'\', '/');
      // `lib/modules` is the submodules and the C sources. flipperlib has FFI
      // of its own, governed by its own repository.
      if (normalised.contains('lib/modules/')) continue;
      // The wrapper's own definition is the one bare call there should be.
      if (normalised.endsWith('lib/services/native.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      final lookups = '.lookupFunction<'.allMatches(source).length;
      final wrapped = 'lookupNativeFunction('.allMatches(source).length;
      if (lookups != wrapped) {
        offenders.add('$normalised ($lookups lookups, $wrapped wrapped)');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Wrap each lookup in lookupNativeFunction from services/native.dart, so '
          'a missing symbol raises NativeEngineUnavailable rather than an '
          'ArgumentError nothing can attribute.',
    );
  });
}
