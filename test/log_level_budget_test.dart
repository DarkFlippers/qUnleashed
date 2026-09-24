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
// last word turns on what its caller does next, which no rule can see: of
// the 117 #103 measured, it extrapolated roughly 45-50 as real debt and the
// rest as already reported somewhere. So this stops the backlog growing
// while #103 waits, and makes each slice of it a budget rather than an
// intention.
//
// What it cannot see. The first is in lib/ and predates this; the rest are
// what someone reaches for when the ratchet is inconvenient:
//
//  * A one-line wrapper - `void _log(m) => LogService.info(m)` called from a
//    catch. Undetectable without following the call graph.
//    lib/pages/devices/firmware/installer.dart:25 is one, and #119 is the
//    failure that goes through it.
//  * `finally { LogService.info(...) }`, the same failure in the block next
//    door. Counting it would change what the number means, so it does not.
//  * A cascade, `LogService..info(...)`, whose invocation has no target.
//  * A closure passed as `onError:`. An invocation, but with no catch clause
//    around it, which is the thing being counted. lib/ has three, one of them
//    in an area declared empty below: device.dart's info stream, and two in
//    pages/archive.
//  * A failure reported from an `if` or a plain statement rather than a catch -
//    a `ServiceRequestFailure` branch, a `return null` guard. The slices have
//    raised several of those; they simply do not move this number.
//
// And two that make the number a proxy rather than a measure:
//
//  * A bare `catch (_) {}` - the same failure with less evidence, and lib/ has
//    43 of them. Deleting a counted log leaves one of those and lowers the
//    number, so the cheapest way to go green is to make the code worse. And
//    nothing catches it going the other way either: no test asserts that a
//    site a slice promoted still reaches history. #117.
//  * A correct fix can move the number either way, because what replaces a
//    counted site depends on the shape of the fix.
//
// In all of these the budget is what is wrong, and moving it with a word about
// why is the answer.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// What each area held when the ratchet went in. Lower one when a slice lands.
///
/// Per area rather than one total for two reasons: offsetting changes hide in a
/// single number - services down three while apps goes up three is no change at
/// all - and a failure can say where. Offsetting still hides *within* an area,
/// which is the price of six buckets rather than 319.
///
/// The areas are also not the same kind of debt, and a number cannot say which
/// is which - so each entry that differs says so itself. Someone editing this
/// map to get CI green reads the line they are changing, not this paragraph.
const Map<String, int> kBudget = {
  // Read through site by site; a new one wants justifying against the rule in
  // [LogService.info] rather than absorbing into the figure.
  //
  // 24 until the connection work in #127 rewrote the area around it - aaf1650
  // took three out and 5af8518 put two back, and the run has been printing
  // "down from 24" ever since. Lowered here rather than left: a budget above
  // what the tree holds lets two sites back in silently, which is the one
  // direction this is meant to stop.
  'services': 22,
  // Part-triaged. What remains mostly writes its error into a controller field
  // the widgets read only in states the failure itself prevents, so its second
  // surface mostly is not one - a UI defect, #110. A ceiling, not a verdict.
  'pages/archive': 30,
  // Read through. The six left are the per-item loops, which want recording
  // once per batch rather than a level here - the same deferral archive made.
  // The failures raised out of it want a failed state too: #112.
  'pages/apps': 6,
  // At budget, not done. What is left is rendered - the settings dialog for
  // download and delete, the page's error view for a failed search, the
  // pixel-draw page for two of its four - or is a per-item walk. The two
  // controllers disagree about when an error reaches anyone (#114), and the
  // area's bare catches are invisible here by construction.
  'pages/tools': 7,
  // Empty of what this counts. Both sites the slice meant to keep turned out
  // to rest on a flipperlib record that does not cover them - the alert's
  // firmware-status path, and the two StateErrors establishLocked never sees.
  // What silence is left is out of reach by construction: an onError closure
  // in the same file, a one-line wrapper (#119), and bare catches (#118).
  'pages/devices': 0,
  // Empty. All three were the connection picker; #120 has the surface they
  // want, which that file already imports for its connect path.
  'components': 0,
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

/// The lines of the counted calls in [unit], in source order.
List<int> catchSiteLinesIn(CompilationUnit unit) {
  final visitor = _CatchSiteVisitor(unit);
  unit.accept(visitor);
  return visitor.lines;
}

/// Parses [source] and counts, for the rule's own tests.
List<int> catchSiteLines(String source, {String? path}) =>
    catchSiteLinesIn(parseUnit(source, path: path));

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

  test('no area logs more failures below the surviving levels than its budget', () {
    final result = countAcrossLib((unit, _) => catchSiteLinesIn(unit));

    expectWithinBudget(
      counted: result.counted,
      budget: kBudget,
      sites: result.sites,
      budgetFile: 'test/log_level_budget_test.dart',
      why:
          'LogService.info is not kept, and in an ordinary release build the '
          'call compiles away - so a failure logged only there reports nowhere '
          'a reader of a bug report can see.\n'
          'If the new call is the last word on a failure, use warn or error. '
          'If something else already reports it, raise kBudget in '
          'test/log_level_budget_test.dart and say why.\n'
          'See $kIssue',
    );
  });
}
