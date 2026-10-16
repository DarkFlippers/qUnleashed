// A guard on picker calls whose rejection has nowhere to land. Budget zero
// everywhere.
//
// No ordinal. The last three ratchets each claimed one and each was wrong -
// `picker_bytes_guard_test.dart` says "the eighth" and is the eleventh,
// `ratchet.dart` still says "Seven of them now" over twelve - because nothing
// checks a number that is only ever read by a human. The checkable claim is the
// one in `main`: `budget: const <String, int>{}`.
//
// QUNLEASHED-K: the file browser's "Upload files" called
// `FilePicker.platform.pickFiles` with no `try` around it, from a
// `ListTile.onTap` that did not await the future either. Android's picker
// answered `unknown_path` - the chosen item's provider handed back no stream,
// so `FilePickerDelegate` failed the whole pick rather than returning a file
// with a null path - and `_getPath` in `file_picker_io.dart` rethrows a
// `PlatformException` for that. With no `try` at the call site and no listener
// on the future, the rejection reached the zone: `PlatformDispatcher.onError`,
// reported fatal, app gone, behind a picker the user was still looking at.
//
// Three more sites had the same shape the day this went in - all three of them
// folder picks - and the pixel editor's was the instructive one: its three
// export entry points each have a `try`, and each awaited `_pickDestination()`
// one line *above* it.
//
// A guard rather than a budget, because this one has no legacy to drain. Ten
// `FilePicker.platform` calls sit under `lib/`, in seven files; six already
// caught for themselves and the four that did not moved in the same change, so
// zero is both the current count and the target.
//
// **It holds the three things that put a listener on the rejection**, because
// any one of them missing is the incident again:
//
//  1. the call is awaited, so the enclosing `try` is on the stack when the
//     future rejects;
//  2. it is lexically inside a `try` body, in the same function;
//  3. that `try` has a clause that catches everything;
//  4. and that clause does not `rethrow`.
//
// Every one of those was a false negative in the first version of this file,
// which asked only (2). Reviews drove them out from a probe: `.then(g)` in a
// non-`async` body, `unawaited(...)`, a `finally` with no catch, and `on
// FormatException catch` each read as guarded while a `PlatformException` went
// straight to the zone - and the first of those is what a refactor to a `void`
// tap handler produces, which is how the incident was reached in the first
// place. The `finally` case is the codebase's own idiom one method over
// (`firmware_update_button.dart:201`), so it was the likeliest next write.
// (4) is the cheap half of a coverage gap: no test mounts the pixel editor, so
// a `rethrow` in `_pickDestination` would reinstate the crash on three export
// paths with a green suite.
//
// **What it still does not hold is the handling.** That the catch says or keeps
// anything is not expressible here - `test/bare_catch_budget_test.dart`
// notices a catch that keeps nothing, and `test/caught_budget_test.dart` keeps
// the record from becoming noise. `test/unguarded_pick_test.dart` is what
// asserts a real site's catch produces a line and a sentence.
//
// An AST walk and not a regex, per ADR 0004: all three conditions are
// questions about nesting, and the site that made this worth writing was a call
// *next to* a `try` in a method that reads, line-wise, exactly like one inside
// it.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// Whether [node] is a call on `FilePicker.platform`, however it was imported.
///
/// The prefixed form is why this is a predicate rather than a name check: one
/// `import 'package:file_picker/file_picker.dart' as fp;` would take a whole
/// file out of the count, and nobody adding that import would connect it to a
/// ratchet.
bool isPickerCall(MethodInvocation node) {
  final target = node.target;
  if (target is PrefixedIdentifier) {
    return target.identifier.name == 'platform' &&
        target.prefix.name == 'FilePicker';
  }
  if (target is PropertyAccess) {
    final inner = target.target;
    return target.propertyName.name == 'platform' &&
        inner is PrefixedIdentifier &&
        inner.identifier.name == 'FilePicker';
  }
  return false;
}

/// Whether [node] is the expression of an `await`.
///
/// Condition (1). Without it the `try` around the call is off the stack by the
/// time the future rejects, so `.then(g)` and `unawaited(...)` inside a `try`
/// read as guarded and are not. `await` through a parenthesis or a cascade is
/// not a spelling any site uses, and treating it as unguarded is the stricter
/// direction.
bool isAwaited(AstNode node) {
  final parent = node.parent;
  return parent is AwaitExpression && parent.expression == node;
}

/// Whether [clause] catches every error, rather than one type.
///
/// Condition (3). `on PlatformException catch (e)` would be enough for today's
/// Android path and for nothing else: the Linux picker throws a bare
/// `Exception` when no `zenity` is on the path, Windows a `WindowsException`,
/// and a missing plugin a `MissingPluginException`. Those have no common
/// supertype worth naming, so the only clause that can be shown to cover a
/// picker is the unqualified one.
bool catchesEverything(CatchClause clause) =>
    clause.exceptionType == null && !rethrows(clause.body);

/// Whether [body] hands the error straight back out again.
///
/// Condition (4), and the one a review asked for by name. `_pickDestination`
/// in the pixel editor returns a value into three callers that each read null
/// as "cancelled", so its contract is "report, then answer null" - and a
/// `rethrow` there reads as correct, because every one of those callers has a
/// `try` of its own one line below. It would put the crash back on all three
/// export paths, and nothing else in the suite would notice: the `try` is
/// still there, the budgets do not move, and no test mounts that page.
///
/// A `rethrow` in a *nested* catch inside the clause counts too, which is a
/// false positive. It is the stricter direction and no site has one.
bool rethrows(AstNode body) {
  final visitor = _RethrowVisitor();
  body.accept(visitor);
  return visitor.found;
}

class _RethrowVisitor extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitRethrowExpression(RethrowExpression node) => found = true;
}

/// Whether [node] sits in the body of a `try` that catches, in the same
/// function.
///
/// Conditions (2) and (3). A `catch` or `finally` clause is deliberately not a
/// body: a picker call there is as unguarded as one with no `try` in sight, and
/// it reads as covered. A `try` whose only clause is a `finally` is likewise
/// not a guard - it runs the clause and lets the error past, which
/// `bare_catch_budget_test.dart` states as "a finally catches nothing, so it
/// loses nothing".
///
/// A closure boundary ends the walk. A `try` outside a function expression does
/// not catch what the body throws when somebody calls it later, and the honest
/// answer to "is this one of ours?" for a picker inside a callback is yes. A
/// `try` *inside* the closure still guards, because the walk reaches it first.
///
/// Two blind spots remain, both false negatives, and neither is empty by
/// accident:
///
///  * **A picker reached through a local.** `final p = FilePicker.platform;`
///    then `await p.pickFiles()` is invisible to [isPickerCall], with or
///    without a `try`. Resolving it needs types, and this runs on the parsed
///    unit; the unit test below pins the current answer so the gap is at least
///    written down.
///  * **A picker wrapped one level down**, in a helper that every caller awaits
///    inside a `try`. That is a real way to be safe and this counts it anyway,
///    which is the stricter direction. Zero is reachable because all ten sites
///    under `lib/` catch for themselves.
bool isInsideTryBody(AstNode node) {
  AstNode child = node;
  for (AstNode? parent = node.parent; parent != null; parent = parent.parent) {
    if (parent is TryStatement && parent.body == child) {
      return parent.catchClauses.any(catchesEverything);
    }
    if (parent is FunctionExpression) return false;
    child = parent;
  }
  return false;
}

/// Where [unit] calls the picker with no listener on the rejection, or nothing.
///
/// [path] is unused; the signature is [countAcrossLib]'s.
List<int> unguardedPickersIn(CompilationUnit unit, String path) {
  final visitor = _PickerGuardVisitor(unit);
  unit.accept(visitor);
  return visitor.lines;
}

class _PickerGuardVisitor extends RecursiveAstVisitor<void> {
  _PickerGuardVisitor(this.unit);

  final CompilationUnit unit;
  final List<int> lines = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (isPickerCall(node) && !(isAwaited(node) && isInsideTryBody(node))) {
      lines.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    super.visitMethodInvocation(node);
  }
}

void main() {
  test('every picker call is awaited inside a try that catches', () {
    final found = countAcrossLib(unguardedPickersIn);
    expectWithinBudget(
      counted: found.counted,
      budget: const <String, int>{},
      sites: found.sites,
      budgetFile: 'test/picker_guard_test.dart',
      why:
          'A picker rejects - unknown_path on an Android file pick, a missing '
          'zenity on Linux, a missing plugin anywhere - and these are reached '
          'from taps that do not await, so an uncaught rejection is a fatal '
          'error and the app dies behind the dialog (QUNLEASHED-K). Await the '
          'call inside a try whose catch is unqualified, record the failure at '
          'LogService.caught, and show commonPickFailed. A .then, an '
          'unawaited, a finally with no catch and a narrow `on` clause each '
          'leave the rejection exactly where the incident left it.',
    );
  });

  group('what counts as an unguarded picker', () {
    List<int> linesIn(String source) =>
        unguardedPickersIn(parseUnit(source), 'lib/pages/x.dart');

    test('the shape that shipped the bug', () {
      expect(
        linesIn('f() async => FilePicker.platform.pickFiles();'),
        hasLength(1),
      );
    });

    test('every method on the picker, not just the one that crashed', () {
      // Three of the four sites this went in with were folder picks, and the
      // rule covers every method rather than the one that crashed because
      // where each can reject differs by platform: `saveFile` rejects the way
      // `pickFiles` does, while `getDirectoryPath` on Android and iOS swallows
      // its own `PlatformException` and answers null - so what reaches a
      // folder pick's catch is a desktop failure or a missing plugin.
      expect(
        linesIn('f() async => FilePicker.platform.getDirectoryPath();'),
        hasLength(1),
      );
      expect(
        linesIn('f() async => FilePicker.platform.saveFile();'),
        hasLength(1),
      );
    });

    test('a prefixed import, which a name check would miss', () {
      expect(
        linesIn('f() async => fp.FilePicker.platform.pickFiles();'),
        hasLength(1),
      );
    });

    test('awaited inside a try that catches, which is the whole point', () {
      expect(
        linesIn(
          'f() async { try { await FilePicker.platform.pickFiles(); }'
          ' catch (e) {} }',
        ),
        isEmpty,
      );
    });

    // The four shapes a review drove out of the first version of this file,
    // which asked only "is it lexically inside a try". Each read as guarded
    // while a PlatformException went straight to the zone.
    test('not awaited is not guarded, whatever wraps it', () {
      // `.then` in a non-async body is what a refactor to a `void` tap
      // handler produces - which is how the incident was reached.
      expect(
        linesIn(
          'f() { try { FilePicker.platform.pickFiles().then(g); }'
          ' catch (e) {} }',
        ),
        hasLength(1),
      );
      expect(
        linesIn(
          'f() { try { unawaited(FilePicker.platform.pickFiles()); }'
          ' catch (e) {} }',
        ),
        hasLength(1),
      );
    });

    test('a try with no catch is not a guard', () {
      // A finally runs its clause and lets the error past. It is also the
      // idiom one method over in firmware_update_button.dart, which releases a
      // flag this way - so it was the likeliest next write.
      expect(
        linesIn(
          'f() async { try { await FilePicker.platform.pickFiles(); }'
          ' finally { g(); } }',
        ),
        hasLength(1),
      );
    });

    test('a catch that rethrows is not a guard', () {
      expect(
        linesIn(
          'f() async { try { await FilePicker.platform.getDirectoryPath(); }'
          ' catch (e) { report(e); rethrow; } }',
        ),
        hasLength(1),
      );
    });

    test('a narrow on clause does not cover a picker', () {
      // The platforms throw four unrelated types, so only the unqualified
      // clause can be shown to catch one.
      expect(
        linesIn(
          'f() async { try { await FilePicker.platform.pickFiles(); }'
          ' on FormatException catch (e) {} }',
        ),
        hasLength(1),
      );
      // Narrow first and catch-all second is the plotter's shape, and counts.
      expect(
        linesIn(
          'f() async { try { await FilePicker.platform.pickFiles(); }'
          ' on FormatException catch (e) {} catch (e) {} }',
        ),
        isEmpty,
      );
    });

    test('a catch or a finally clause is not a guard', () {
      // It reads as covered and is not: a throw from here leaves the same way
      // as one with no try in sight.
      expect(
        linesIn(
          'f() async { try {} catch (e)'
          ' { await FilePicker.platform.pickFiles(); } }',
        ),
        hasLength(1),
      );
      expect(
        linesIn(
          'f() async { try {} finally'
          ' { await FilePicker.platform.pickFiles(); } }',
        ),
        hasLength(1),
      );
    });

    test('a closure inside a try is not covered by it', () {
      // The body runs when somebody calls it, which can be long after the try
      // returned - and the onTap that shipped the bug is exactly this.
      expect(
        linesIn(
          'f() { try { g(() => FilePicker.platform.pickFiles()); }'
          ' catch (e) {} }',
        ),
        hasLength(1),
      );
    });

    test('a nested try still guards', () {
      expect(
        linesIn(
          'f() async { if (x) { try { for (final y in z)'
          ' { await FilePicker.platform.pickFiles(); } } catch (e) {} } }',
        ),
        isEmpty,
      );
    });

    test('a try inside the closure does guard', () {
      // The walk reaches it before the function boundary, which is the right
      // answer: that try is on the stack when the body runs.
      expect(
        linesIn(
          'f() { g(() async { try { await FilePicker.platform.pickFiles(); }'
          ' catch (e) {} }); }',
        ),
        isEmpty,
      );
    });

    test('not a comment, and not another API that picks something', () {
      expect(linesIn('// FilePicker.platform.pickFiles()\nf() {}'), isEmpty);
      expect(linesIn('f() async => FilePicker.pickFiles();'), isEmpty);
    });

    test('a picker reached through a local is invisible, guarded or not', () {
      // Pinned, not endorsed: this is the first blind spot named on
      // `isInsideTryBody`, and resolving it needs types this does not have.
      // Asserted in both directions so the gap cannot be mistaken for a rule
      // about where the call sits.
      expect(linesIn('f() async => p.pickFiles();'), isEmpty);
      expect(
        linesIn(
          'f() async { final p = FilePicker.platform;'
          ' await p.pickFiles(); }',
        ),
        isEmpty,
      );
    });
  });
}
