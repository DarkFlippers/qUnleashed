// A ceiling on `LogService.caught`, the level ADR 0013 §5 adds.
//
// Unlike every other budget here, this number is meant to *rise* - once, as
// §5's re-ruling of the `info`-in-a-catch sites lands, and not after. It counts
// something the project wants a bounded amount of rather than less of, which is
// why the failure message asks a different question.
//
// It exists because `caught` is a legitimate way to lower
// `log_level_budget_test.dart`: moving a genuine failure off `info` makes that
// failure survive a release build. Moving *commentary* lowers it by exactly as
// much and puts noise in a 500-entry buffer whose purpose is to still hold a
// failure's context when someone goes looking. CLAUDE.md lists the deletion
// version of that trade as an anti-pattern; this is the same trade with a
// different lever, and without a number nothing would notice.
//
// The rule a new entry passes is the one on `LogService.caught`: an operation
// did not do what was asked.
//
// Blind spots, shared with every per-file syntactic ratchet here: a `caught`
// behind a one-line wrapper, or inside an `onError:` closure rather than a
// catch clause. #103 holds those.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// What each area may record at `caught`.
///
/// §5's re-ruling has landed, which is the one rise this ratchet was ever
/// meant to have. 23 of the 42 `LogService.info`-inside-a-catch sites moved;
/// the other 19 stayed, each on a volume argument its own comment makes.
///
/// `services` is 6: the two `build_identity.dart` sites and the two in
/// `telemetry.dart` that were here before, plus a launcher refusing a
/// home-widget pin and an HTTP request the network responder could not carry.
/// The relay reply beside that second one runs per frame and stayed at `info`,
/// which is the distinction the level is for.
///
/// `pages/archive` is 16 — every `list`, `read`, `write`, `delete`, `mkdir`,
/// `rename` and `appStart` the user asked for, plus `refresh`, `sync` and
/// `syncCategory`. Two sites in that area did **not** move: the per-node
/// `list` of a whole-SD walk, and the per-file `md5 check`, which §5 excludes
/// by name because the per-sync summary at `warn` already covers it (#194).
///
/// `pages/tools` is 5: the IR library's download, delete and search, and the
/// pixel editor's load and send. The two Dolphin walks stayed — one entry per
/// folder wants a tally at the caller, not a level here.
///
/// `pages/apps` is absent on purpose. All six of its sites are one-per-app
/// loops or a cancel the user asked for, so none of them moved.
const Map<String, int> kBudget = {
  'services': 6,
  'pages/archive': 16,
  'pages/tools': 5,
};

const String kAdr = 'docs/adr/0013-observability-with-sentry.md';

/// Collects `LogService.caught(...)` calls, wherever they are.
///
/// Not restricted to a catch clause, unlike the log budget's visitor. `caught`
/// is *for* a catch, so a call outside one is a misuse this should count rather
/// than overlook - and the analyzer is what decides, for the reason that file
/// gives: `on Type {` is also how Dart spells an extension target.
class _CaughtVisitor extends RecursiveAstVisitor<void> {
  _CaughtVisitor(this.unit);

  final CompilationUnit unit;
  final List<int> lines = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'caught' && isLogServiceCall(node)) {
      lines.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    super.visitMethodInvocation(node);
  }
}

/// The lines of the counted calls in [unit], in source order.
List<int> caughtLinesIn(CompilationUnit unit) {
  final visitor = _CaughtVisitor(unit);
  unit.accept(visitor);
  return visitor.lines;
}

/// Parses [source] and counts, for the rule's own tests.
List<int> caughtLines(String source, {String? path}) =>
    caughtLinesIn(parseUnit(source, path: path));

void main() {
  group('the rule', () {
    test('counts a caught call inside a catch', () {
      expect(
        caughtLines(
          "void f() { try { g(); } catch (e) { LogService.caught('x'); } }",
        ),
        hasLength(1),
      );
    });

    // Counted anyway, and deliberately: `caught` outside a catch is a level
    // used for something it is not for, which is what the ceiling is about.
    test('counts one outside a catch too', () {
      expect(caughtLines("void f() { LogService.caught('x'); }"), hasLength(1));
    });

    test('is only LogService.caught, by whatever name it was imported', () {
      expect(
        caughtLines("void f() { log.LogService.caught('x'); }"),
        hasLength(1),
      );
      expect(caughtLines("void f() { Other.caught('x'); }"), isEmpty);
      expect(caughtLines("void f() { caught('x'); }"), isEmpty);
    });

    test('is not another level', () {
      expect(caughtLines("void f() { LogService.warn('x'); }"), isEmpty);
      expect(caughtLines("void f() { LogService.info('x'); }"), isEmpty);
    });

    test('reports the line the call is on', () {
      expect(caughtLines("void f() {\n  g();\n  LogService.caught('x');\n}"), [
        3,
      ]);
    });
  });

  test('no area records more caught failures than its budget', () {
    final result = countAcrossLib((unit, _) => caughtLinesIn(unit));

    expectWithinBudget(
      counted: result.counted,
      budget: kBudget,
      sites: result.sites,
      budgetFile: 'test/caught_budget_test.dart',
      why:
          'LogService.caught is kept in every build, so a commentary line put '
          'here is noise in front of whoever reads a bug report - and it '
          'lowers log_level_budget_test.dart by exactly as much as a real '
          'failure would.\n'
          'If an operation did not do what was asked, raise kBudget in '
          'test/caught_budget_test.dart and say which operation. If it is '
          'commentary, it belongs at info.\n'
          'See $kAdr',
    );
  });
}
