// Guards the one file in this repository that is meant to hold secrets and is
// meant never to be committed.
//
// `dart-defines.local.json` carries whatever a local build needs: the Sentry
// DSN, which is public by design, but also QU_CARTO_KEY and
// QU_BUILD_SERVER_KEY, which are not. `.gitignore` stops it reaching the index
// by accident, and that is the whole protection - an ignore rule is silent
// against `git add -f`, against a file created before the rule, and against a
// name nobody anticipated.
//
// So this asserts the outcome rather than the rule: whatever the ignore file
// says, the only dart-defines JSON git knows about is the template, and the
// template holds no values. A test cannot stop somebody committing a secret,
// but it can stop the commit after it being green.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every tracked or untracked-but-not-ignored path matching the defines shape.
///
/// `--cached --others --exclude-standard` is the pairing `ratchet.dart`'s
/// `dartFilesUnderLib` uses, and for the same reason: the index alone would
/// miss a file somebody has created and not yet added, which is exactly the
/// moment before the mistake. Spelled out here rather than shared, because
/// that helper is hardcoded to `lib/*.dart`.
List<String> definesFilesGitCanSee() {
  final result = Process.runSync('git', [
    'ls-files',
    '-z',
    '--cached',
    '--others',
    '--exclude-standard',
    '--',
    'dart-defines*.json',
  ]);
  expect(result.exitCode, 0, reason: 'git ls-files failed: ${result.stderr}');
  return (result.stdout as String)
      .split(String.fromCharCode(0))
      .where((path) => path.isNotEmpty)
      .toList();
}

void main() {
  const template = 'dart-defines.local.example.json';

  test('the only defines file git can see is the template', () {
    expect(
      definesFilesGitCanSee(),
      [template],
      reason:
          'A dart-defines JSON other than the template is either tracked or '
          'not ignored. That file is where QU_CARTO_KEY and '
          'QU_BUILD_SERVER_KEY go on a developer machine.\n'
          'If it is yours and local, it needs a name .gitignore covers. If it '
          'is meant to be committed, it must hold no values.',
    );
  });

  // The template is the one that is committed, so it is the one that can leak.
  // Empty strings rather than placeholder text, because a placeholder is a
  // thing somebody might take for a real value and leave in place.
  test('the template carries no values', () {
    final decoded =
        jsonDecode(File(template).readAsStringSync()) as Map<String, dynamic>;

    final filled = <String>[];
    decoded.forEach((key, value) {
      if (key.startsWith('_')) return; // the self-documenting comments
      if (key == 'QU_CHANNEL' && value == 'local') return; // the safe default
      if (key == 'QLOG' || key == 'QLOG_LEVEL') return; // not secrets
      if (value is String && value.isNotEmpty) filled.add('$key=$value');
    });

    expect(
      filled,
      isEmpty,
      reason:
          'The committed template has a value in it. Every secret key must be '
          'an empty string, so that copying the file cannot carry somebody '
          "else's credential into a build.",
    );
  });

  // The runbook tells people to copy this file, so the name it tells them to
  // copy to has to be one the ignore rule covers. Checked through git rather
  // than by reading .gitignore, so a rule that is written but shadowed by a
  // later one still fails.
  test('the name the runbook tells people to copy to is ignored', () {
    final copied = Process.runSync('git', [
      'check-ignore',
      'dart-defines.local.json',
    ]);
    expect(
      copied.exitCode,
      0,
      reason:
          'docs/releasing.md says to copy the template to '
          'dart-defines.local.json, and git does not ignore that name.',
    );
  });
}
