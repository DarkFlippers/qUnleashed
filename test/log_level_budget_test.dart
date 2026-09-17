// A ratchet on failures logged where a release build cannot see them.
//
// LogService.info is `keep: false`, so nothing sent there reaches the Settings
// -> Log screen in any build; and infoOn const-folds to false in an ordinary
// release build, so the call usually compiles away. LogService.info's own doc
// has the full account, including why a talking build is no better. Where one
// of these is the last word on a failure, the failure reports nowhere a reader
// of a bug report can see. #103 holds the triage.
//
// Counting is the point, not forbidding. Whether a site is commentary or the
// last word turns on what its caller does next, which no rule can see: #103
// extrapolates roughly 45-50 of the 117 as real debt and the rest as already
// reported somewhere. So this stops the backlog growing while #103 waits, and
// makes each slice of it a budget rather than an intention.
//
// What it cannot see. None of these are in lib/ today; the first two are what
// someone reaches for when the ratchet is inconvenient:
//
//  * A one-line wrapper - `void _log(m) => LogService.info(m)` called from a
//    catch. Undetectable without following the call graph.
//  * `finally { LogService.info(...) }`, the same failure in the block next
//    door. Counting it would change what the number means, so it does not.
//  * A cascade, `LogService..info(...)`, whose invocation has no target, and a
//    tear-off passed as `onError:`, which is not an invocation at all.
//
// And two that make the number a proxy rather than a measure:
//
//  * A bare `catch (_) {}` - the same failure with less evidence, and lib/ has
//    43 of them. Deleting a counted log leaves one of those and lowers the
//    number, so the cheapest way to go green is to make the code worse.
//  * A correct fix can move the number either way, because what replaces a
//    counted site depends on the shape of the fix.
//
// In all of these the budget is what is wrong, and moving it with a word about
// why is the answer.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// What each area held when the ratchet went in. Lower one when a slice lands.
///
/// Per area rather than one total for two reasons: offsetting changes hide in a
/// single number - services down three while apps goes up three is no change at
/// all - and a failure can say where. Offsetting still hides *within* an area,
/// which is the price of six buckets rather than 319.
///
/// The areas are also not the same kind of debt. #103 sampled eight of the 35
/// `pages/archive` sites and found a second surface on all eight, so it expects
/// most of that 35 to need no change, where `lib/services` sampled the other
/// way round. The 35 has not been read through, so treat that as the
/// expectation it is rather than a finding.
const Map<String, int> kBudget = {
  'services': 37,
  'pages/archive': 35,
  'pages/apps': 18,
  'pages/tools': 17,
  'pages/devices': 7,
  'components': 3,
};

const String kIssue = 'https://github.com/DarkFlippers/qUnleashed/issues/103';

/// Collects `LogService.info(...)` calls that sit inside a catch clause.
///
/// The analyzer decides what a catch clause is, which is why this parses. Dart
/// spells an extension target and a mixin constraint `on Type {`, exactly like
/// a bare catch clause. A text scan can be made to agree on today's tree - two
/// were, before this existed - but it agrees by accident, and the accident does
/// not survive the next `extension ... on ... {` that happens to log.
class _CatchSiteVisitor extends RecursiveAstVisitor<void> {
  _CatchSiteVisitor(this.unit);

  final CompilationUnit unit;
  final List<int> lines = [];
  int _depth = 0;

  @override
  void visitCatchClause(CatchClause node) {
    _depth += 1;
    super.visitCatchClause(node);
    _depth -= 1;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_depth > 0 && node.methodName.name == 'info' && _isLogService(node)) {
      lines.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    super.visitMethodInvocation(node);
  }

  /// Whether [node]'s receiver is `LogService`, however it was imported.
  ///
  /// The prefixed form matters: one `import '.../logging.dart' as log;` would
  /// otherwise zero out a whole file's contribution, and nobody adding that
  /// import would connect it to this test.
  static bool _isLogService(MethodInvocation node) {
    final target = node.target;
    if (target is SimpleIdentifier) return target.name == 'LogService';
    if (target is PrefixedIdentifier) {
      return target.identifier.name == 'LogService';
    }
    return false;
  }
}

/// The lines of the counted calls in [source], in source order.
///
/// A file that does not parse would otherwise count zero without saying so, and
/// zero lands in the under-budget branch below - which tells the reader to
/// lower the budget, baking the undercount in for good. The realistic trigger
/// is not a broken file but version skew: this parses with the pub `analyzer`
/// while `flutter analyze` uses the SDK's own, so syntax newer than the pinned
/// major would leave the analyzer green and this silently miscounting.
List<int> catchSiteLines(String source, {String? path}) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  expect(
    parsed.errors,
    isEmpty,
    reason:
        'could not parse ${path ?? 'the source'}. If the file itself is fine, '
        'the analyzer pinned in pubspec.yaml is probably older than the '
        'language version the SDK now accepts.',
  );
  final visitor = _CatchSiteVisitor(parsed.unit);
  parsed.unit.accept(visitor);
  return visitor.lines;
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
/// how the formatting check on this very file came to be missed.
List<String> _dartFilesUnderLib() {
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
/// `lib/pages` is split a level deeper because that is where the sites are:
/// three of the six buckets and 70 of the 117. A file sitting directly in
/// `lib/` becomes its own bucket named for the file, which is honest -
/// `lib/main.dart` is not part of any area, and if it ever grows one of these
/// it should have to be declared rather than absorbed into a neighbour. A file
/// directly under `lib/pages/` would get its own bucket the same way; there are
/// none today.
String _areaOf(String path) {
  final parts = path.split('/');
  if (parts.length < 3) return parts.last;
  return parts[1] == 'pages' ? '${parts[1]}/${parts[2]}' : parts[1];
}

/// How [counted] differs from [budget], as lines ready to print.
///
/// Split out so the comparison can be tested at all. Over the real tree it only
/// ever runs its passing path, since the tree sits exactly at budget - so
/// without a test of its own, the branch that fails the build never executes.
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

void main() {
  group('the rule', () {
    test(
      'is what the parser calls a catch clause, not what text looks like',
      () {
        // `on Type {` is also an extension target and a mixin constraint.
        expect(
          catchSiteLines(
            "extension E on S { void f() { LogService.info(''); } }",
          ),
          isEmpty,
        );
        expect(
          catchSiteLines("mixin M on B { void f() { LogService.info(''); } }"),
          isEmpty,
        );
        expect(
          catchSiteLines(
            "void f() { try { g(); } catch (e) { LogService.info(''); } }",
          ),
          hasLength(1),
        );
        expect(
          catchSiteLines(
            "void f() { try { g(); } on E { LogService.info(''); } }",
          ),
          hasLength(1),
        );
      },
    );

    test('is only LogService.info, by whatever name it was imported', () {
      expect(
        catchSiteLines(
          "void f() { try { g(); } catch (e) { LogService.error(''); } }",
        ),
        isEmpty,
      );
      expect(
        catchSiteLines(
          "void f() { try { g(); } catch (e) { other.info(''); } }",
        ),
        isEmpty,
      );
      expect(
        catchSiteLines(
          "void f() { try { g(); } catch (e) { LogService.information(''); } }",
        ),
        isEmpty,
      );
      // A prefixed import would otherwise zero out the file that used it.
      expect(
        catchSiteLines(
          "void f() { try { g(); } catch (e) { log.LogService.info(''); } }",
        ),
        hasLength(1),
      );
    });

    test('follows the catch block wherever the call is nested', () {
      // The shape ir_content_page.dart:84 actually has: a catch inside a
      // closure passed as an argument. Without descending into every
      // expression this site is lost and the count silently drops.
      expect(
        catchSiteLines(
          "void f() { h(onTap: () { try { g(); } "
          "catch (e) { LogService.info(''); } }); }",
        ),
        hasLength(1),
      );
      expect(
        catchSiteLines(
          "void f() { try { g(); } catch (e) { run(() { LogService.info(''); }); } }",
        ),
        hasLength(1),
      );
      expect(
        catchSiteLines(
          "void f() { try { g(); } catch (e) { try { h(); } "
          "catch (x) { LogService.info(''); } } }",
        ),
        hasLength(1),
      );
    });

    test('stops counting once the catch block has closed', () {
      // Pins that the depth counter comes back down. Nothing else here has a
      // statement after a catch clause, so a leak would go unnoticed.
      expect(
        catchSiteLines(
          "void f() { try { g(); } catch (e) { h(); } LogService.info(''); }",
        ),
        isEmpty,
      );
      expect(
        catchSiteLines(
          "void f() { try { LogService.info(''); } finally { h(); } }",
        ),
        isEmpty,
      );
      expect(
        catchSiteLines(
          "void f() { try { g(); } finally { LogService.info(''); } }",
        ),
        isEmpty,
        reason: 'finally is the same failure next door, deliberately uncounted',
      );
    });

    test('reports the line the call is on', () {
      expect(
        catchSiteLines(
          'void f() {\n  try { g(); }\n  catch (e) {\n'
          "    LogService.info('');\n  }\n}",
        ),
        [4],
      );
    });
  });

  group('the budget comparison', () {
    test('says nothing when every area is exactly at budget', () {
      final drift = budgetDrift({'a': 2}, {'a': 2});
      expect(drift.over, isEmpty);
      expect(drift.under, isEmpty);
    });

    test('reports an area that has grown, and one that has shrunk', () {
      final drift = budgetDrift({'a': 3, 'b': 1}, {'a': 2, 'b': 2});
      expect(drift.over, ['a: 3, up from 2']);
      expect(drift.under, ['b: 1, down from 2']);
    });

    test('an area nobody declared starts at zero, so its first site fails', () {
      final drift = budgetDrift({'brand/new': 1}, const {});
      expect(drift.over, ['brand/new: 1, up from 0']);
    });

    test('an area that has emptied out is reported, not forgotten', () {
      final drift = budgetDrift(const {}, {'gone': 4});
      expect(drift.under, ['gone: 0, down from 4']);
    });
  });

  test(
    'no area logs more failures below the surviving levels than its budget',
    () {
      final files = _dartFilesUnderLib();
      // A guard that counts nothing passes every budget. The wrong working
      // directory, a pathspec that stops matching, a submodule layout change -
      // all of them empty this list, and without this the build stays green
      // having looked at nothing at all.
      expect(
        files,
        hasLength(greaterThan(100)),
        reason: 'expected the whole of lib/, got ${files.length} files',
      );

      final counted = <String, int>{};
      final sites = <String, List<String>>{};
      for (final path in files) {
        final lines = catchSiteLines(File(path).readAsStringSync(), path: path);
        if (lines.isEmpty) continue;
        final area = _areaOf(path);
        counted.update(
          area,
          (n) => n + lines.length,
          ifAbsent: () => lines.length,
        );
        sites
            .putIfAbsent(area, () => <String>[])
            .addAll(lines.map((line) => '$path:$line'));
      }

      final drift = budgetDrift(counted, kBudget);

      if (drift.under.isNotEmpty) {
        // Printed rather than failed. An expected count checked into the tree
        // races on merge: two branches that each remove a site in the same area
        // write the same lower number, both pass their own run, and main lands
        // below what the file claims. That cuts both ways - two additions merge
        // to a false failure - but a number gone stale low is a nag where one
        // gone stale high lets debt back in, so only the upward case fails.
        // ignore: avoid_print
        print(
          'Lower kBudget in test/log_level_budget_test.dart:\n'
          '  ${drift.under.join('\n  ')}\n'
          'See $kIssue',
        );
      }

      // Only the areas that broke. Listing all of them buries the one line that
      // matters under a hundred that were already there and already green.
      final offending = [
        for (final line in drift.over) ...[
          '  $line',
          ...?sites[line.split(':').first]?.map((site) => '    $site'),
        ],
      ];

      expect(
        drift.over,
        isEmpty,
        reason:
            'LogService.info is not kept, and in an ordinary release build the '
            'call compiles away - so a failure logged only there reports nowhere '
            'a reader of a bug report can see.\n'
            '${offending.join('\n')}\n'
            'If the new call is the last word on a failure, use warn or error. '
            'If something else already reports it, raise kBudget in '
            'test/log_level_budget_test.dart and say why.\n'
            'See $kIssue',
      );
    },
  );
}
