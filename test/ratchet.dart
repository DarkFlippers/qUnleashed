// The machinery three ratchets share.
//
// A ratchet counts something the project wants less of, per area, and fails
// when a number rises. `test/log_level_budget_test.dart` was the first and
// carries the full argument for counting rather than forbidding; ADR 0004
// records why architectural rules are written this way here rather than as
// lint plugins.
//
// Extracted when the second and third arrived, not before. Each ratchet keeps
// its own visitor and its own budget - what they share is how a file list is
// obtained, how a path becomes an area, and how two maps are compared.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parses [source], failing the test rather than counting zero if it cannot.
///
/// A file that does not parse would otherwise contribute nothing without
/// saying so, and nothing lands in the under-budget branch - which tells the
/// reader to lower the budget, baking the undercount in for good. The
/// realistic trigger is version skew: this parses with the pub `analyzer`
/// while `flutter analyze` uses the SDK's own, so syntax newer than the pinned
/// major would leave the analyzer green and a ratchet silently miscounting.
CompilationUnit parseUnit(String source, {String? path}) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  expect(
    parsed.errors,
    isEmpty,
    reason:
        'could not parse ${path ?? 'the source'}. If the file itself is fine, '
        'the analyzer pinned in pubspec.yaml is probably older than the '
        'language version the SDK now accepts.',
  );
  return parsed.unit;
}

/// Dart under `lib/` that git can see, tracked or not.
///
/// git rather than a directory walk: submodule contents under lib/modules are
/// gitlinks rather than tracked files, so flipperlib and dartufbt drop out
/// without being named, and generated l10n is gitignored so it drops out too.
/// The same reasoning as check_format.sh.
///
/// `--others --exclude-standard` as well as the index, because a file that has
/// not been added yet is exactly the one its author is about to run this
/// against. Without it a local run before `git add` is a false green - which is
/// how the formatting check on the first ratchet came to be missed.
List<String> dartFilesUnderLib() {
  final result = Process.runSync('git', [
    'ls-files',
    '-z',
    '--cached',
    '--others',
    '--exclude-standard',
    '--',
    'lib/*.dart',
  ]);
  expect(result.exitCode, 0, reason: 'git ls-files failed: ${result.stderr}');
  return (result.stdout as String)
      .split(String.fromCharCode(0))
      .where((path) => path.isNotEmpty)
      .toList();
}

/// The budget bucket a file belongs to.
///
/// `lib/pages` is split a level deeper because that is where most sites are.
/// A file sitting directly in `lib/` becomes its own bucket named for the
/// file, which is honest - `lib/main.dart` is not part of any area, and if it
/// ever grows one of these it should have to be declared rather than absorbed
/// into a neighbour. A file directly under `lib/pages/` would get its own
/// bucket the same way.
String areaOf(String path) {
  final parts = path.split('/');
  if (parts.length < 3) return parts.last;
  return parts[1] == 'pages' ? '${parts[1]}/${parts[2]}' : parts[1];
}

/// How [counted] differs from [budget], as lines ready to print.
///
/// Split out so the comparison can be tested at all. Over a tree sitting
/// exactly at budget it only ever runs its passing path - so without a test of
/// its own, the branch that fails the build never executes.
({List<String> over, List<String> under}) budgetDrift(
  Map<String, int> counted,
  Map<String, int> budget,
) {
  final over = <String>[];
  final under = <String>[];
  for (final area in ({...budget.keys, ...counted.keys}.toList()..sort())) {
    final now = counted[area] ?? 0;
    final allowed = budget[area] ?? 0;
    if (now > allowed) over.add('$area: $now, up from $allowed');
    if (now < allowed) under.add('$area: $now, down from $allowed');
  }
  return (over: over, under: under);
}

/// Walks every Dart file under `lib/`, counting what [linesIn] finds.
///
/// Returns the per-area totals and, for a failure message, where each counted
/// site is.
({Map<String, int> counted, Map<String, List<String>> sites}) countAcrossLib(
  List<int> Function(CompilationUnit unit, String path) linesIn,
) {
  final files = dartFilesUnderLib();
  // A guard that counts nothing passes every budget. The wrong working
  // directory, a pathspec that stops matching, a submodule layout change - all
  // of them empty this list, and without this the build stays green having
  // looked at nothing at all.
  expect(
    files,
    hasLength(greaterThan(100)),
    reason: 'expected the whole of lib/, got ${files.length} files',
  );

  final counted = <String, int>{};
  final sites = <String, List<String>>{};
  for (final path in files) {
    final lines = linesIn(
      parseUnit(File(path).readAsStringSync(), path: path),
      path,
    );
    if (lines.isEmpty) continue;
    final area = areaOf(path);
    counted.update(area, (n) => n + lines.length, ifAbsent: () => lines.length);
    sites
        .putIfAbsent(area, () => <String>[])
        .addAll(lines.map((line) => '$path:$line'));
  }
  return (counted: counted, sites: sites);
}

/// Asserts [counted] is at or under [budget], and says where if it is not.
///
/// An area that has *shrunk* is printed rather than failed. An expected count
/// checked into the tree races on merge: two branches that each remove a site
/// in the same area write the same lower number, both pass their own run, and
/// main lands below what the file claims. That cuts both ways - two additions
/// merge to a false failure - but a number gone stale low is a nag where one
/// gone stale high lets debt back in, so only the upward case fails.
void expectWithinBudget({
  required Map<String, int> counted,
  required Map<String, int> budget,
  required Map<String, List<String>> sites,
  required String budgetFile,
  required String why,
}) {
  final drift = budgetDrift(counted, budget);

  if (drift.under.isNotEmpty) {
    // ignore: avoid_print
    print('Lower the budget in $budgetFile:\n  ${drift.under.join('\n  ')}');
  }

  // Only the areas that broke. Listing all of them buries the one line that
  // matters under a dozen that were already there and already green.
  final offending = [
    for (final line in drift.over) ...[
      '  $line',
      ...?sites[line.split(':').first]?.map((site) => '    $site'),
    ],
  ];

  expect(drift.over, isEmpty, reason: '$why\n${offending.join('\n')}');
}
