// A ceiling on `LogService.caught`, the level ADR 0013 §5 adds.
//
// The sixth ratchet, and the only one whose number is meant to *rise* - once,
// as §5's re-ruling of the 48 `info`-in-a-catch sites lands, and not after.
// Every other budget in `test/` counts something the project wants less of;
// this one counts something it wants a bounded amount of, which is why the
// failure message below asks a different question.
//
// It exists because `caught` opens a way to lower another ratchet by making
// the code worse, and that way is the mirror image of the one
// `bare_catch_budget_test.dart` closed. `log_level_budget_test.dart` counts
// failures reported only at a level a release build drops. Moving a genuine
// failure from `info` to `caught` lowers it legitimately - the failure now
// survives. Moving *commentary* lowers it exactly as much and puts noise in
// front of whoever reads a bug report, in a 500-entry buffer whose whole
// purpose is to still hold the failure's context when someone goes looking.
// CLAUDE.md lists "deleting a counted LogService.info to make the ratchet go
// green" as an anti-pattern; this is the same trade with a different lever,
// and without a number on it nothing would notice.
//
// The rule a new entry has to pass is the one on `LogService.caught`: an
// operation did not do what was asked. A reading that repeats, a wait whose own
// timeout is the answer, and commentary about something merely absent all stay
// `info`.
//
// What it cannot see, which is the same blind spot every per-file syntactic
// ratchet here has: a `caught` reached through a one-line wrapper, or inside an
// `onError:` closure rather than a catch clause. #103 holds those.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// What each area may record at `caught`.
///
/// Two sites, both in `build_identity.dart`, and both the shape the level is
/// for - an operation that did not do what was asked, where what is left still
/// works:
///
///  * the version could not be read, so every surface says `unknown` and
///    nothing else would ever say why;
///  * the channel define held something `BuildChannel` does not know, so the
///    build reads as `local` when CI meant otherwise.
///
/// §5's re-ruling of #103's 48 sites is what raises these, once.
const Map<String, int> kBudget = {'services': 2};

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
    if (node.methodName.name == 'caught' && _isLogService(node)) {
      lines.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    super.visitMethodInvocation(node);
  }

  /// Whether [node]'s receiver is `LogService`, however it was imported.
  ///
  /// The prefixed form matters for the same reason it does in the log budget:
  /// one `import '.../logging.dart' as log;` would otherwise zero out a whole
  /// file's contribution, and nobody adding that import would connect it to
  /// this test.
  static bool _isLogService(MethodInvocation node) {
    final target = node.target;
    if (target is SimpleIdentifier) return target.name == 'LogService';
    if (target is PrefixedIdentifier) {
      return target.identifier.name == 'LogService';
    }
    return false;
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
