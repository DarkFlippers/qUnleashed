// Guards the one file in this repository meant to hold secrets and meant never
// to be committed: `dart-defines.local.json`, which carries whatever a local
// build needs - the Sentry DSN, which is public by design, but also
// QU_CARTO_KEY and QU_BUILD_SERVER_KEY, which are not.
//
// It asserts the outcome rather than the rule, because an ignore rule is silent
// against `git add -f`, against a file that existed before the rule, and
// against a name nobody anticipated.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

void main() {
  const template = 'dart-defines.local.example.json';

  group('no defines file reaches the repository', () {
    test('the only one git can see is the template', () {
      expect(
        gitVisibleFiles('dart-defines*.json'),
        [template],
        reason:
            'A dart-defines JSON other than the template is either tracked or '
            'not ignored. That file is where QU_CARTO_KEY and '
            'QU_BUILD_SERVER_KEY go on a developer machine.\n'
            'If it is yours and local, it needs a name .gitignore covers. If '
            'it is meant to be committed, it must hold no values.',
      );
    });

    // The check above only fires once such a file exists, so on a clean
    // checkout it passes whether or not the rule is there. This is the half
    // that tests the rule itself.
    test('and the name the template says to copy to is ignored', () {
      final ignored = Process.runSync('git', [
        'check-ignore',
        'dart-defines.local.json',
      ]);
      // 0 ignored, 1 not ignored, 128 git could not answer - which is a
      // different failure and deserves a different message.
      expect(
        ignored.exitCode,
        isNot(128),
        reason: 'git could not answer: ${ignored.stderr}',
      );
      expect(
        ignored.exitCode,
        0,
        reason:
            'The template says to copy it to dart-defines.local.json, and git '
            'does not ignore that name.',
      );
    });
  });

  // The template is the committed one, so it is the one that can leak. Default
  // deny: any value that is not on the list below fails, so a secret key added
  // later is covered without anyone remembering to cover it.
  //
  // Empty strings rather than placeholder text, because a placeholder is a
  // thing somebody might take for a real value and leave in place.
  test('the template carries no values', () {
    const allowFilled = {
      'QU_CHANNEL': 'local',
      'QLOG': 'true',
      'QLOG_LEVEL': 'trace',
    };

    final decoded =
        jsonDecode(File(template).readAsStringSync()) as Map<String, dynamic>;

    final filled = [
      for (final entry in decoded.entries)
        if (!entry.key.startsWith('_') && // the self-documenting comments
            entry.value is String &&
            (entry.value as String).isNotEmpty &&
            entry.value != allowFilled[entry.key])
          '${entry.key}=${entry.value}',
    ];

    expect(
      filled,
      isEmpty,
      reason:
          'The committed template has a value in it. Every secret key must be '
          'an empty string, so that copying the file cannot carry somebody '
          "else's credential into a build.",
    );
  });
}
