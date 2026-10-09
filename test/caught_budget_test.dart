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
/// Three sites, all in `lib/services`, and all the shape the level is for - an
/// operation that did not do what was asked, where what is left still works:
///
///  * the version could not be read, so every surface says `unknown` and
///    nothing else would ever say why;
///  * the channel define held something `BuildChannel` does not know, so the
///    build reads as `local` when CI meant otherwise;
///  * reporting is not running, because no DSN was compiled in or the switch
///    is off. The only site of the three that is a *refusal* rather than a
///    fault, and it earns the level for the same reason: both causes are
///    ordinary - every local build has no DSN - so nobody is to be alerted,
///    and a dev build that was supposed to be reporting and is silent has
///    nowhere else to say so.
///
/// §5's re-ruling of #103's 48 sites is what raises these, once.
const Map<String, int> kBudget = {'services': 3};

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
