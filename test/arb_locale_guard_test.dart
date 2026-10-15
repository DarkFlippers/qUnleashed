// Ties `check_arb_locales.sh` to the two places that have to run it, and every
// script CI runs to the mode it has to be committed with.
//
// The ARB rule - that `@@locale` agrees with the filename - cannot be asserted
// from Dart at all: `gen-l10n` runs inside `flutter pub get`, so a file that
// breaks it breaks the command `flutter test` needs to have succeeded first.
// `test/arb.dart` says so where someone would look for the rule, the guard is
// a shell script instead, and `check_arb_locales_test.sh` covers the script.
//
// What neither covers is whether anything still calls it, and whether calling
// it still has a consequence. Delete the step from the setup-flutter action and
// every suite stays green while the five jobs that run `pub get` go back to
// reporting a broken translation as a stale `pubspec.lock`. Drop the Crowdin
// sync's own call and the mismatch still fails its build - but gen-l10n names
// no file for that one shape, so the sync stops saying which translation is
// wrong, and the four shapes stricter than gen-l10n's own check stop being
// caught at all. Stop consuming that call's outcome and it reports to nobody.
// The script's own header calls all three "how a guard becomes decoration",
// and this repository already reads a shell script from Dart for the same kind
// of seam - see `dart_define_keys_test.dart`.
//
// Anchored on the `run:` line rather than on the script's name, because the
// comments in these workflows name scripts constantly: an assertion that only
// looked for `check_arb_locales.sh` was satisfied by the prose above the step
// and stayed green when the step itself was deleted.
//
// The mode is here because `chmod +x` on Windows does not reach the index:
// both of this guard's scripts were committed 100644 first time out and CI
// stopped at `Permission denied`, exit 126, before reading a single file.
// Asserted for every script a workflow invokes, not just those two, because
// the next one added from a Windows checkout will land the same way.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The mode git records for [path], as `git ls-files -s` prints it.
String indexMode(String path) {
  final result = Process.runSync('git', ['ls-files', '-s', '--', path]);
  expect(result.exitCode, 0, reason: 'git ls-files failed: ${result.stderr}');
  final out = (result.stdout as String).trim();
  expect(out, isNotEmpty, reason: '$path is not in the index');
  return out.split(RegExp(r'\s+')).first;
}

/// Every `.github/scripts/*.sh` named in a workflow or composite action.
///
/// Matched by path rather than by parsing the YAML: a script reaches a runner
/// from a `run:` line, a `with:` input or a composite action's own step, and
/// what matters is only that something names it.
Set<String> scriptsWorkflowsRun() {
  final referenced = <String>{};
  final pattern = RegExp(r'\.github/scripts/([a-z0-9_]+\.sh)');
  final files = <File>[
    ...Directory('.github/workflows')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.yml')),
    ...Directory('.github/actions')
        .listSync()
        .whereType<Directory>()
        .map((d) => File('${d.path}/action.yml'))
        .where((f) => f.existsSync()),
  ];
  for (final file in files) {
    for (final match in pattern.allMatches(file.readAsStringSync())) {
      referenced.add('.github/scripts/${match.group(1)}');
    }
  }
  return referenced;
}

void main() {
  const guard = '.github/scripts/check_arb_locales.sh';
  const action = '.github/actions/setup-flutter/action.yml';
  const sync = '.github/workflows/crowdin-rx.yml';

  test('the guard is there to be called', () {
    expect(File(guard).existsSync(), isTrue, reason: '$guard is missing');
  });

  test('every script a workflow runs is executable in the index', () {
    final referenced = scriptsWorkflowsRun();
    // A regex that stopped matching would otherwise pass this in silence.
    expect(
      referenced,
      contains(guard),
      reason: 'the scan found no reference to the guard, so it found nothing',
    );

    final wrong = <String, String>{};
    for (final path in referenced) {
      final mode = indexMode(path);
      if (mode != '100755') wrong[path] = mode;
    }
    expect(
      wrong,
      isEmpty,
      reason:
          'a script CI invokes directly has to be committed 100755, or the '
          'step fails with Permission denied before running it. chmod +x does '
          'not reach the index on Windows: git update-index --chmod=+x <path>',
    );
  });

  test('the Flutter setup runs the guard before pub get', () {
    final yaml = File(action).readAsStringSync();
    expect(
      yaml,
      contains('check_arb_locales.sh'),
      reason:
          'the five jobs that run pub get lose their preflight, and a broken '
          'translation goes back to being reported as a stale pubspec.lock',
    );
    expect(
      yaml.indexOf('check_arb_locales.sh'),
      lessThan(yaml.indexOf('flutter pub get')),
      reason: 'a preflight after the command it precedes is not one',
    );
  });

  test('the Crowdin sync checks what it is about to merge', () {
    final yaml = File(sync).readAsStringSync();

    // The invocation, not the name: see the header. A comment cannot satisfy
    // this, because the path has to open the line. The negative lookahead is
    // so a neighbouring `check_arb_locales_test.sh` cannot stand in for it.
    final call = RegExp(
      r'^\s*\.github/scripts/check_arb_locales\.sh(?![-\w])',
      multiLine: true,
    );
    final called = call.firstMatch(yaml);
    expect(
      called,
      isNotNull,
      reason:
          'the sync passes pub-get: false, which skips the copy of this inside '
          'setup-flutter - so without its own call it stops naming the file, '
          'and stops catching the shapes gen-l10n itself lets through',
    );

    // After the overlay, or it reads main's translations - which are already
    // known good - and passes on a branch it never looked at. The overlay's
    // own line is asserted first: compared blind, an overlay that was renamed
    // or deleted gives indexOf -1, and -1 is less than anything.
    const overlay = 'git checkout FETCH_HEAD -- translations';
    expect(yaml, contains(overlay), reason: 'the overlay step is gone');
    expect(
      yaml.indexOf(overlay),
      lessThan(called!.start),
      reason: "the guard has to see the pull request's files, not main's",
    );

    // Called is not the same as heard. The step is deliberately
    // continue-on-error, so its status is only worth anything if something
    // downstream spends it - crowdin-rx.yml does that twice, in the pull
    // request body and in a terminal gate.
    expect(
      yaml,
      contains("steps.locales.outcome == 'failure'"),
      reason: 'nothing fails the run when the guard refuses a translation',
    );
    expect(
      yaml,
      contains(r'LOCALES: ${{ steps.locales.outcome }}'),
      reason: "the guard's finding never reaches the pull request body",
    );

    // #323: the branch was repaired after the Crowdin action had committed to
    // it, so it never again matched the export and every sync became a diff.
    // The flag is not the mechanism - a worktree that commits and pushes
    // reproduces it without `--write` - so both are named.
    expect(
      yaml,
      isNot(contains('--write')),
      reason: 'see #323: a repair on the branch makes a diff out of every sync',
    );
    expect(
      yaml,
      isNot(contains('refs/heads/l10n/crowdin')),
      reason: 'see #323: this job must not push to the Crowdin branch',
    );
  });
}
