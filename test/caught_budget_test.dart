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
/// `services` is 9: the two `build_identity.dart` sites and the two in
/// `telemetry.dart` that were here before, plus a launcher refusing a
/// home-widget pin and an HTTP request the network responder could not carry.
/// The relay reply beside that second one runs per frame and stayed at `info`,
/// which is the distinction the level is for.
///
/// It rose to 9 for the two in `remote_build_service.dart`'s
/// `_ensureClientId`: a preferences store that will not open, and one that
/// refuses the write. Both are an operation that did not do what was asked -
/// the id was not remembered for the next launch - and both are deliberately
/// not `warn`, which is what `persistSetting` would have logged. The id is
/// returned either way and serves the session, so there is nothing for anyone
/// to do about it; the cost is a fresh id next launch. Once per process, since
/// the field is set on the way out whatever happened. #313.
///
/// The seventh is the replay switch's restart in `telemetry.dart`, and it is
/// not a failure at all - it is the one line that makes a deliberate gap in
/// reporting visible. 9.30.1 has no app-facing pause API, so applying a
/// replay rate means taking the SDK down and bringing it back, and in that
/// window all four sinks are off and the native handler is down. A crash lost
/// there is indistinguishable from no crash, so the gap is named once, at
/// `caught`, and shows up in the timeline of the next report. Once per tap on
/// one switch, which is as bounded as this level gets.
///
/// Two sites in `pages/archive` did **not** move: the per-node `list` of a
/// whole-SD walk, and the per-file `md5 check`, which §5 excludes by name
/// because the per-sync summary at `warn` already covers it (#194).
///
/// `pages/tools` is 5: the IR library's download, delete and search, and the
/// pixel editor's load and send. The two Dolphin walks stayed — one entry per
/// folder wants a tally at the caller, not a level here.
///
/// `pages/apps` is 1 and `pages/archive` 17 for the same operation: a launch
/// refused because one of the same app is already in flight (#244). The tap
/// did nothing, and the page deliberately shows nothing for it - so without a
/// line kept in every build, a tap that was swallowed cannot be told from one
/// that was never delivered, which is the question a bug report about a dead
/// button asks. Its six other `pages/apps` sites are one-per-app loops or a
/// cancel the user asked for, and none of them moved.
///
/// `pages/archive` also counts every `list`, `write`, `delete`, `mkdir`,
/// `rename` and `appStart` the user asked for, plus `refresh`, `sync` and
/// `syncCategory`. The per-file `read` inside a sync is **no longer one of
/// them** - §5's table carries the amendment and the reason, which is that
/// that one site produced 94% of the project's entire log volume and the burst
/// evicted error events out of the SDK's cache. A `read` the user asked for by
/// opening one file is still counted.
///
/// It rose to 18 for the line that records a whole scope reading as deleted.
/// That is not a failure at all: an absent directory is now treated as the
/// empty listing it is, which is right, and the consequence is that every
/// local key under it is marked `deleted` - #109's outcome, reinstated
/// deliberately for one status code. The argument rests on
/// `ERROR_STORAGE_NOT_EXIST` meaning the firmware looked, and these codes are
/// a firmware contract this repo does not own while the app ships against
/// forks. One line, in a build that does not print, is the difference between
/// diagnosing a fork that answers the wrong code and guessing at it. Once per
/// walk, and only when keys actually moved.
const Map<String, int> kBudget = {
  'services': 9,
  'pages/archive': 18,
  'pages/tools': 5,
  'pages/apps': 1,
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
