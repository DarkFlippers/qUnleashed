import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every C source of a native library is named in both of its build lists.
///
/// There are two per library, both hand-maintained, and a file has to be in
/// each: the CMake target that Windows, Linux and Android build, and the Apple
/// unity translation unit, which lists its sources by hand because a podspec
/// cannot reference files outside its own tree.
///
/// Adding `hardnested_bf_dispatch.c` and forgetting the second one is not
/// hypothetical - it is what happened, and the only thing that caught it was a
/// macOS build on CI, on a machine most contributors do not have. The failure
/// is a link error naming a symbol rather than the file nobody added, and it
/// arrives minutes later on a different platform than the one being worked on.
///
/// A source-text guard rather than a behavioural test, in the shape of
/// `ffi_export_test.dart`: it runs on any machine, needs nothing built, and
/// fails in the same second as the omission.
///
/// Parameterised over both libraries rather than copied, because faaccrack has
/// the identical two-list problem and a second copy of this file would drift
/// from the first.
typedef NativeLibrary = ({
  String name,
  String dir,
  String unity,

  /// Files that are `.c` but deliberately in neither list: the unity file,
  /// which *is* the Apple list, and anything built only by a test.
  Set<String> notBuilt,
});

const _libraries = <NativeLibrary>[
  (
    name: 'hardnested',
    dir: 'lib/modules/cpp/hardnested',
    unity: 'lib/modules/cpp/hardnested/apple/qunleashed_hardnested_unity.c',
    notBuilt: {'qunleashed_hardnested_unity.c'},
  ),
  (
    name: 'faaccrack',
    dir: 'lib/modules/cpp/faaccrack',
    unity: 'lib/modules/cpp/faaccrack/apple/qunleashed_faaccrack_unity.c',
    // The probe is compiled by .github/scripts/check_faaccrack_engine.sh, never
    // into the shipped library - it carries its own `main`.
    notBuilt: {'qunleashed_faaccrack_unity.c', 'faaccrack_abi_probe.c'},
  ),
];

void main() {
  for (final library in _libraries) {
    group(library.name, () {
      final sources = Directory(library.dir)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path.replaceAll(r'\', '/'))
          .where((p) => p.endsWith('.c'))
          .where((p) => !library.notBuilt.contains(p.split('/').last))
          .toList(growable: false);

      late String cmake;
      late String unity;

      setUpAll(() {
        cmake = File('${library.dir}/CMakeLists.txt').readAsStringSync();
        unity = File(library.unity).readAsStringSync();
      });

      test('the two build lists agree with what is on disk', () {
        expect(
          sources,
          isNotEmpty,
          reason: 'the glob has to find the sources for this to mean anything',
        );

        final missing = <String>[];
        for (final path in sources) {
          final relative = path.split('${library.dir}/').last;
          final name = relative.split('/').last;
          // CMake lists paths relative to its own directory; the unity file
          // uses `../` prefixes. Matching on the tail of each covers both
          // without caring how either spells the prefix.
          if (!cmake.contains(relative)) {
            missing.add('CMakeLists.txt: $relative');
          }
          if (!unity.contains('/$name') && !unity.contains('"$name')) {
            missing.add('unity: $relative');
          }
        }

        expect(
          missing,
          isEmpty,
          reason:
              'a C source that is in neither list is not compiled on that '
              'platform, and the symptom is a link error somewhere else',
        );
      });
    });
  }
}
