// Ties the `--dart-define` keys the build passes to the ones the app reads.
//
// Neither suite on its own can see this seam. `derive_version_test.sh` pins the
// emitted string literally, so the producer cannot drift; `build_identity_test`
// cannot set a define at all, so the consumer is unobservable from Dart. Rename
// or typo a key on either side and both stay green while every CI build reports
// a `local` channel and no commits - `displayVersion` renders `0.15.0-local` on
// a shipped release, the Sentry release splits off a line of its own, and the
// About screen and the copied log lose the commit, which is the one thing ADR
// 0014 §3 exists for.
//
// A source-reading test rather than an integration one, in the style of the
// five guards already in `test/`: the thing being asserted is that two files
// agree about a string, and that is checkable without building anything.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every `String.fromEnvironment('KEY')` in [source], in source order.
///
/// A regex and not the analyzer, unlike the ratchets: the subject is a string
/// literal in a const context, there is no scope to resolve, and the shell side
/// has to be read with a regex regardless.
Set<String> fromEnvironmentKeys(String source) =>
    RegExp(r"""String\.fromEnvironment\(\s*['"]([A-Za-z0-9_]+)['"]""")
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();

/// Every `--dart-define=KEY=` in [source].
Set<String> dartDefineKeys(String source) =>
    RegExp(r'--dart-define=([A-Za-z0-9_]+)=')
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();

void main() {
  const identity = 'lib/services/build_identity.dart';
  const script = '.github/scripts/derive_version.sh';

  test('every key build_identity reads is one derive_version passes', () {
    final read = fromEnvironmentKeys(File(identity).readAsStringSync());
    final passed = dartDefineKeys(File(script).readAsStringSync());

    // A guard that finds nothing passes every assertion. Both halves are
    // asserted non-empty so a moved file, a changed call shape or a broken
    // regex is a red test rather than a silent green one.
    expect(
      read,
      isNotEmpty,
      reason: 'found no String.fromEnvironment in $identity',
    );
    expect(passed, isNotEmpty, reason: 'found no --dart-define in $script');

    expect(
      read.difference(passed),
      isEmpty,
      reason:
          '$identity reads a define $script never passes, so the app would '
          'see its default in every build. Pass it, or stop reading it.',
    );
  });

  // The other direction is not symmetrical: the script passes keys this file
  // does not read - the map key and the build server - and those are read
  // elsewhere. So only the keys that name a build identity are checked back.
  test('every identity define the script passes is read somewhere', () {
    final passed = dartDefineKeys(File(script).readAsStringSync());
    final identityKeys = passed
        .where((k) => k == 'QU_CHANNEL' || k.startsWith('QU_COMMIT'))
        .toSet();
    final read = fromEnvironmentKeys(File(identity).readAsStringSync());

    expect(
      identityKeys,
      isNotEmpty,
      reason: 'found no identity defines in $script',
    );
    expect(
      identityKeys.difference(read),
      isEmpty,
      reason:
          '$script passes an identity define nothing in $identity reads, so '
          'the build pays for a value no surface can show.',
    );
  });
}
