// The machinery the ratchets share.
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
//
// Seven of them now, and they do not all mean the same thing. Four -
// `bare_catch`, `build_io`, `client_reach` and `log_level` - count legacy that
// a sweep is draining. `unawaited` was the first whose budget went in before
// its sweep rather than after, deliberately, so the figure could not climb
// while the sweep ran; that sweep is done. `caught` is the only one meant to
// *rise*, once, as ADR 0013 §5's re-ruling lands. And
// `sentry_import_guard_test.dart` has no legacy at all: its budget is empty
// everywhere, because the dependency arrived with the folder allowed to hold
// it.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';

// The file list moved to its own library so a test that wants only that does
// not pull in `package:analyzer` with it. Imported for this file's own use and
// re-exported, so every ratchet keeps importing this file exactly as before.
import 'source_files.dart';

export 'source_files.dart';

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

/// Whether [path] is one of [exempt], matched on the path's tail.
///
/// Shared because two ratchets exempt a file - the push census spares the
/// helper that owns pushing, the prompt census the dialog that owns prompting -
/// and `ratchet.dart`'s charter is how a file list is obtained and how a path
/// becomes an area. Both copies also normalised `\` to `/` first, which
/// cannot matter: `countAcrossLib` takes its paths from `git ls-files`, which
/// emits forward slashes on Windows too, and `areaOf` has always assumed that
/// by splitting on one.
bool isExempt(String path, Set<String> exempt) => exempt.any(path.endsWith);

/// Whether [node] is a call on `LogService`, however it was imported.
///
/// Shared because two ratchets ask it and a third would — the log-level budget
/// and the `caught` budget had byte-identical copies. The prefixed form is why
/// it is worth sharing: one `import '.../logging.dart' as log;` would zero out
/// a whole file's contribution to whichever copy had not been taught about it,
/// and nobody adding that import would connect it to a ratchet.
///
/// The visitors stay with their own tests, as this file's header says. They
/// differ — one tracks catch depth and one does not — and only the predicate
/// is common.
bool isLogServiceCall(MethodInvocation node) {
  final target = node.target;
  if (target is SimpleIdentifier) return target.name == 'LogService';
  if (target is PrefixedIdentifier) {
    return target.identifier.name == 'LogService';
  }
  return false;
}

/// The argument called [name] in [arguments], or null if it is not passed.
///
/// Shared on the same grounds as [isLogServiceCall], and by then four ratchets
/// had spelt it out: the bytes argument of a pick, the `throwable:` of a Sentry
/// event, a toolbar's `sort:`, and a folder pick's `what:`.
///
/// The reason it is worth a function is the accessor rather than the loop.
/// `NamedArgument.argumentExpression` carries `@ToBeDeprecated` and
/// `argumentExpression2` - the one that replaces it - is `@experimental`,
/// which `flutter analyze` makes fatal in CI, so the copies had to agree on
/// using the deprecated spelling *and* on why. With one copy, the migration
/// is one edit here and the argument is written once.
NamedArgument? namedArgument(ArgumentList arguments, String name) {
  for (final argument in arguments.arguments) {
    if (argument is NamedArgument && argument.name.lexeme == name) {
      return argument;
    }
  }
  return null;
}
