// A ratchet on tap handlers that push a page without asking whether their own
// page is still on top.
//
// #244 is one gesture running an action twice. Half of its sites were handlers
// whose whole effect is a `Navigator.push`: tap a card twice and two identical
// pages stack, both to be dismissed, and where the pushed page fetches in
// `initState` it fetches twice. `pushPage` in `components/navigation.dart` is
// the guarded form, and this counts what still bypasses it.
//
// Why a count of the *mechanism* rather than a check for the guard. The first
// version of this was a list of the files the fix had touched, asserting each
// still contained its guard. That notices a guard being deleted and cannot
// notice a site that never had one - and there were three of those left in
// `lib/` when it went green, two of them in a file the same commit edited. A
// budget over `Navigator…push` has no such blind spot: a new unguarded push
// raises a number.
//
// What it cannot see, and why it is a scoreboard rather than a rule:
//
//  * A push that is guarded somewhere else. `_opening` in the file manager
//    guards the push inside `_launchFap` from its caller; `_resolveTap` guards
//    one in a closure it returns. Both are correct and both count here.
//  * A guard that is not code: popping before acting (every `ActionItem`),
//    `onDoubleTap` declared beside `onTap` (the paint gallery card),
//    `onPressed: null` while busy, `openRoute(..., replace: true)`.
//  * `openRoute`, which is a push too. It is excluded by file, because ADR
//    0013 owns that path and its callers include ones that legitimately push
//    while a sheet of their own is being dismissed.
//  * Whether the page being pushed does anything expensive on open. A second
//    copy of a page that only renders is a nuisance; a second copy of one that
//    fetches is the bug. The count cannot tell them apart.
//
// So an entry here is not a defect. It is a site nobody has looked at through
// #244's lens, and the number must not rise without one being looked at.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// What each area held when this went in. Lower one when a site moves to
/// `pushPage` or gains a guard of its own.
const Map<String, int> kBudget = {
  // The shell's own route, pushed by the app rather than by a tap.
  'app': 1,
  // Diagnostics, from the About list.
  'pages/about': 1,
  // The catalog's full-screen screenshot viewer, opened from a carousel that
  // is not a card list.
  'pages/apps': 1,
  // Four in `key_actions_sheet.dart`, which are the exonerated shape: the
  // sheet's tiles pop before they act, so Flutter's reversing route absorbs a
  // second click. One in `browser/page.dart`, guarded by `_opening` at the
  // caller. One in `editor/open.dart`, which needs the `bool` the pop returns.
  'pages/archive': 6,
  // The firmware card's update page.
  'pages/devices': 1,
  // The IR file list, guarded by `_fetching` before the fetch it pushes
  // after, and `_openCliPage`, guarded by the `_resolveTap` closure that
  // calls it.
  'pages/tools': 2,
};

const String kAdr = 'docs/adr/0006-navigation.md';

/// Where a push is allowed to live unguarded: the helper that owns pushing.
const Set<String> kExempt = {'components/navigation.dart'};

/// Collects `Navigator…push`/`pushReplacement` calls.
///
/// By method name on a `Navigator`-shaped target rather than by resolving the
/// type, because `countAcrossLib` parses one file at a time with no element
/// model. `Navigator.of(context).push(...)`, `Navigator.of(context).pushNamed`
/// and the static `Navigator.push(context, ...)` all match; a `push` on a list
/// does not, because the target has to mention Navigator.
class _PushVisitor extends RecursiveAstVisitor<void> {
  _PushVisitor(this.lineFor);

  final int Function(int offset) lineFor;
  final List<int> lines = [];

  static const _methods = {
    'push',
    'pushNamed',
    'pushReplacement',
    'pushReplacementNamed',
    'pushAndRemoveUntil',
  };

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target?.toSource() ?? '';
    if (_methods.contains(node.methodName.name) &&
        target.contains('Navigator')) {
      lines.add(lineFor(node.offset));
    }
    super.visitMethodInvocation(node);
  }
}

List<int> _pushesIn(CompilationUnit unit, String path) {
  if (kExempt.any(path.replaceAll(r'\', '/').endsWith)) return const [];
  final visitor = _PushVisitor(
    (offset) => unit.lineInfo.getLocation(offset).lineNumber,
  );
  unit.visitChildren(visitor);
  return visitor.lines;
}

void main() {
  test('no area pushes more pages unguarded than its budget', () {
    final counted = countAcrossLib(_pushesIn);

    expectWithinBudget(
      counted: counted.counted,
      budget: kBudget,
      sites: counted.sites,
      budgetFile: 'test/navigator_push_budget_test.dart',
      why:
          'A tap handler whose whole effect is a push needs pushPage, or a '
          'guard of its own: twice is two stacked pages and two of whatever '
          'the pushed page does on open (#244).\n'
          'If this site is guarded some other way, raise the budget and say '
          'which way.\n'
          'See $kAdr',
    );
  });

  // The visitor, against the shapes it has to tell apart. Without these the
  // budget could go green because nothing matched at all.
  test('counts a push through Navigator.of', () {
    final unit = parseUnit('''
      void f(BuildContext c) {
        Navigator.of(c).push(MaterialPageRoute(builder: (_) => const X()));
      }
    ''');
    expect(_pushesIn(unit, 'lib/pages/x.dart'), hasLength(1));
  });

  test('counts the static form, and a replacement', () {
    final unit = parseUnit('''
      void f(BuildContext c) {
        Navigator.push(c, route);
        Navigator.of(c).pushReplacement(route);
      }
    ''');
    expect(_pushesIn(unit, 'lib/pages/x.dart'), hasLength(2));
  });

  test('does not count a push on something that is not a navigator', () {
    final unit = parseUnit('''
      void f(List<int> xs) {
        xs.push(1);
        history.pushNamed('/x');
      }
    ''');
    expect(_pushesIn(unit, 'lib/pages/x.dart'), isEmpty);
  });

  test('does not count the helper that owns pushing', () {
    final unit = parseUnit('''
      void f(BuildContext c) {
        Navigator.of(c).push(route);
      }
    ''');
    expect(_pushesIn(unit, 'lib/components/navigation.dart'), isEmpty);
  });
}
