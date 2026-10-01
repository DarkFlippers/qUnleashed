// A ratchet on futures nobody awaits and nobody handles.
//
// `unawaited(f())` says "I have decided not to await this". In Dart that is the
// same statement as "I have decided this cannot fail": the future still
// rejects, and with no listener the rejection goes to the zone. #89's uncaught
// handlers do put it in `LogService.history`, but as `[uncaught]` with nothing
// saying which operation it was - so a bug report has a stack and no subject.
//
// Worse, it is also how a failure escapes the catch that was written for it.
// `unawaited(x())` inside a `try` is outside that `try` as far as the error is
// concerned, because the body has already returned by the time x rejects. #23
// names the shape; #17 was the same thing spelled `return <Future>;`.
//
// The counted shape is a bare one: `unawaited(` whose argument carries no
// handler of its own. Two arguments are not counted, because both name a
// handler at the call site:
//
//  * `guarded('what', task)` - `lib/services/guarded.dart`, which logs at
//    error with the operation's name on it and never rejects.
//  * anything ending in `.catchError(...)` or `.onError(...)`.
//
// This budget is a floor, not a verdict. The other three ratchets went in
// after their area had been read through; this one goes in before. #23's first
// box is that triage, and these numbers are only where the tree stood when the
// ratchet arrived - so the figure can fall while the sweep happens and cannot
// quietly climb while it does not. Do not read an area's number as a set of
// sites somebody has judged fine.
//
// What it cannot see:
//
//  * A future dropped with no `unawaited()` at all.
//    `UNAWAITED_RETURN_IN_TRY_BLOCK` is already an analyzer warning and CI
//    treats warnings as fatal, so the `return <Future>;` form of #17 is
//    covered there rather than here.
//  * Whether the callee guards itself internally. Several do, and they are
//    counted anyway - the point of counting at the call site is that a reader
//    can tell without opening the callee.
//  * `.then(onError:)`, a handler attached later, or a `Completer` nobody
//    completes with an error.
//
// ADR 0004 is why this is a test rather than a lint. The lint that looks like
// it would fit, `unawaited_futures`, flags the opposite thing: it wants
// `unawaited()` added where a future is dropped, and says nothing about
// whether the one inside it has a handler. #23's second box turns that on once
// this number is down.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// Where each area stood when the ratchet went in. Lower one when a site goes.
///
/// Untriaged, unlike the other three budget maps - see the header. The one
/// thing these numbers do say is that nothing may be added without a reader
/// deciding it belongs.
const Map<String, int> kBudget = {
  // Untriaged. These are where the tree stood.
  'pages/apps': 34,
  'pages/archive': 23,
  'pages/tools': 18,
  // Read through. Was 10, and nine were a settings page starting a load in
  // `initState` or a tap persisting a choice - no caller, so `guarded` is the
  // whole fix. The one left is `storage.dart`'s `_sizeArea`, which already
  // catches everything it can throw and logs at error with the area's name:
  // better than what wrapping the call site would say, and a second layer
  // there could never fire.
  'pages/option': 1,
  // Read through, and none of the three should change.
  //
  // `icon.dart` and `remote_image.dart` both `unawaited(_map.remove(key))` in
  // a `finally`, and what `remove` hands back is *this very future* - awaiting
  // it could not return, and attaching a handler to it would log every failed
  // rasterize a second time, next to the `rethrow` that is the real report.
  // Both comments already say so.
  //
  // `notification.dart` forwards an AnimationController. A plain TickerFuture
  // completes normally when its ticker is cancelled; only `.orCancel` rejects,
  // and this is not that.
  'components': 3,
  // Read through. Was 3: `_saveLastFolder` and `_rememberSource` are named
  // through `guarded` now, the second because it sits inside a `try` whose
  // catch could never have seen it. What is left is
  // `project/page.dart`'s `openRoute`, which #23 calls deliberate and is: the
  // only throw in `openRoute` is the synchronous StateError for an
  // unregistered route, which the surrounding try does catch, and the pushed
  // route's future resolves when it is popped.
  'pages/flibler': 1,
  // Read through, and empty. Was 24, and the whole of it went the same way:
  // every one was a stream callback, a platform-channel handler or a timer,
  // so there was never a caller to hand a failure back to - which is the case
  // `guarded` exists for. The two that needed more than a wrapper are in
  // `emulate/service.dart`: the APP_CLOSED wait now attaches its handler at
  // creation rather than across `_safeExit`, and the connection subscription
  // is read into a local before the field is cleared.
  'services': 0,
  // Read through, and empty. Was 4: two `UpdateSettingsStore.remember` calls
  // whose store does catch its own write but said nothing at the call site,
  // the `_restore()` in the constructor, and the subscription teardown in
  // `installer.dart` - whose comment explains why it is not awaited and is
  // kept, with the failure now carrying the operation's name.
  'pages/devices': 0,
};

const String kAdr =
    'https://github.com/DarkFlippers/qUnleashed/blob/main/docs/adr/'
    '0008-swallowed-errors.md';

/// Collects `unawaited(...)` calls whose argument carries no handler.
class _UnawaitedVisitor extends RecursiveAstVisitor<void> {
  _UnawaitedVisitor(this.unit);

  static const String _name = 'unawaited';
  static const String _guarded = 'guarded';
  static const Set<String> _handlers = {'catchError', 'onError'};

  final CompilationUnit unit;
  final List<int> lines = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // A bare call or one behind an import prefix, the same allowance the other
    // ratchets make: `unawaited` comes from dart:async, and a file may import
    // it prefixed.
    final target = node.target;
    if (node.methodName.name == _name &&
        (target == null || target is SimpleIdentifier) &&
        node.argumentList.arguments.length == 1 &&
        !_handled(node.argumentList.arguments.single.argumentExpression)) {
      lines.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    super.visitMethodInvocation(node);
  }

  /// Whether [argument] names what happens on failure.
  ///
  /// Only the outermost expression is read. `guarded(...).then(...)` would not
  /// count as handled, which is right: `then` on something that never rejects
  /// is fine, but that shape hides whatever is innermost and a ratchet should
  /// not guess.
  static bool _handled(Expression argument) {
    final inner = argument.unParenthesized;
    if (inner is! MethodInvocation) return false;
    if (inner.methodName.name == _guarded && inner.target == null) return true;
    return _handlers.contains(inner.methodName.name) && inner.target != null;
  }
}

/// The lines of the counted sites in [unit], in source order.
List<int> unawaitedLines(CompilationUnit unit) {
  final visitor = _UnawaitedVisitor(unit);
  unit.accept(visitor);
  return visitor.lines;
}

/// Parses [source] and counts, for the rule's own tests.
List<int> linesIn(String source) => unawaitedLines(parseUnit(source));

void main() {
  group('the rule', () {
    test('counts a future dropped with no handler', () {
      expect(linesIn('void f() { unawaited(g()); }'), hasLength(1));
      expect(linesIn('void f() { unawaited(a.b.c()); }'), hasLength(1));
    });

    // A future held in a variable is the shape that hides the most: the
    // rejection can land between the two statements.
    test('counts one it cannot see inside', () {
      expect(
        linesIn('void f() { final x = g(); unawaited(x); }'),
        hasLength(1),
      );
    });

    test('is not one that names what happens on failure', () {
      expect(linesIn("void f() { unawaited(guarded('x', g)); }"), isEmpty);
      expect(linesIn('void f() { unawaited(g().catchError(h)); }'), isEmpty);
      expect(linesIn('void f() { unawaited(g().onError(h)); }'), isEmpty);
    });

    // `guarded` is this project's own function, so a method of that name on
    // something else is not it.
    test('is not a method that merely shares the name', () {
      expect(
        linesIn('void f() { unawaited(other.guarded(g)); }'),
        hasLength(1),
      );
    });

    // `catchError` the other way round: a bare call to something of that name
    // is not a handler attached to a future.
    test('wants the handler attached to something', () {
      expect(linesIn('void f() { unawaited(catchError(g)); }'), hasLength(1));
    });

    test('reads through parentheses', () {
      expect(linesIn("void f() { unawaited((guarded('x', g))); }"), isEmpty);
    });

    test('is the call, not anything that mentions it', () {
      expect(linesIn('void f() { log("unawaited(x)"); }'), isEmpty);
      expect(linesIn('void f() { final unawaited = 1; }'), isEmpty);
    });

    // Two arguments is not this function, and counting it would be a guess.
    test('is the one-argument form', () {
      expect(linesIn('void f() { unawaited(g(), h()); }'), isEmpty);
    });

    test('finds it wherever it is nested', () {
      expect(
        linesIn('void f() { h(onTap: () => unawaited(g())); }'),
        hasLength(1),
      );
      expect(
        linesIn('class A { void f() { if (x) { unawaited(g()); } } }'),
        hasLength(1),
      );
    });

    test('reports the line the call is on', () {
      expect(linesIn('void f() {\n  g();\n  unawaited(h());\n}'), [3]);
    });
  });

  test('no area drops more unhandled futures than its budget', () {
    final result = countAcrossLib((unit, _) => unawaitedLines(unit));

    expectWithinBudget(
      counted: result.counted,
      budget: kBudget,
      sites: result.sites,
      budgetFile: 'test/unawaited_budget_test.dart',
      why:
          'a future nobody awaits still rejects, and with no handler the '
          'rejection reaches the zone - so it arrives in the log as an '
          'unlabelled [uncaught], and a catch written around the call site '
          'never sees it.\n'
          'Wrap it in guarded with the operation it was doing, so the failure '
          'has a name, or attach a catchError that says what happens instead.\n'
          'If the callee genuinely handles its own and the call site should say '
          'so, say that in a comment and raise kBudget in '
          'test/unawaited_budget_test.dart.\n'
          'See $kAdr',
    );
  });
}
