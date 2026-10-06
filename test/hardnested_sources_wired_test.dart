import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every C source of the hardnested library is named in both build lists.
///
/// There are two, both hand-maintained, and a file has to be in each: the CMake
/// target that Windows, Linux and Android build, and the Apple unity
/// translation unit, which lists its sources by hand because a podspec cannot
/// reference files outside its own tree.
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
void main() {
  final root = Directory('lib/modules/cpp/hardnested');

  // minlzlib and tables.c are vendored wholesale and already listed; the point
  // is to catch a *new* file, so the check covers everything either list
  // mentions plus anything that appears beside them.
  final sources = root
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.replaceAll(r'\', '/'))
      .where((p) => p.endsWith('.c'))
      // The unity file is the Apple list itself, not an entry in it.
      .where((p) => !p.endsWith('qunleashed_hardnested_unity.c'))
      .toList(growable: false);

  late String cmake;
  late String unity;

  setUpAll(() {
    cmake = File('lib/modules/cpp/hardnested/CMakeLists.txt')
        .readAsStringSync();
    unity = File(
      'lib/modules/cpp/hardnested/apple/qunleashed_hardnested_unity.c',
    ).readAsStringSync();
  });

  test('the two build lists agree with what is on disk', () {
    expect(
      sources,
      isNotEmpty,
      reason: 'the glob has to find the sources for this to mean anything',
    );

    final missing = <String>[];
    for (final path in sources) {
      final relative = path.split('lib/modules/cpp/hardnested/').last;
      final name = relative.split('/').last;
      // CMake lists paths relative to its own directory; the unity file uses
      // `../` prefixes. Matching on the tail of each covers both without
      // caring how either spells the prefix.
      if (!cmake.contains(relative)) missing.add('CMakeLists.txt: $relative');
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
}
