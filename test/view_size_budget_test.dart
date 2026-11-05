// A ratchet on tests that size their window where `MediaQuery` cannot see it.
//
// `tester.binding.setSurfaceSize(size)` stores a `_surfaceSize` that feeds
// `createViewConfigurationFor`, and so the render view's constraints. But
// `MediaQuery` is built from `View.of(context)` - the view's own
// `physicalSize` over its `devicePixelRatio` - and nothing on that path
// consults it. So a case that asks for 500x900 lays its tree out at 500x900
// while `MediaQuery.sizeOf` goes on answering the binding's default 800x600.
//
// Eleven files were sized other than they said when #414 was filed, and the
// one that mattered had been lying for a release: `FlipperRootScaffold.isWide`
// is `MediaQuery.sizeOf`, 800 by 600 is wide, and every case in
// `shell_rebuild_test.dart` ran on the desktop rail - the three named for a
// narrow window and the one named for a layout flip included, where both
// sizes read as wide and no flip ever happened. One of its assertions was
// wrong under the real narrow layout. #410 fixed that file; #414 was the rest
// of the repo, and this is what stops a twelfth.
//
// Counted, in a test file:
//
//  * any call to `setSurfaceSize`, which is never the right one here. The
//    framework points at `TestFlutterView.physicalSize` too - "Instead of
//    this method, consider setting [TestFlutterView.physicalSize], which
//    works for any view" - but for multi-view reasons of its own, with a
//    `TODO` to deprecate it. The `MediaQuery` argument above is this
//    project's, not the framework's.
//  * an **assignment** to `physicalSize`, `devicePixelRatio` or
//    `physicalConstraints`. Those are the right properties, and they are
//    counted anyway for the second half of the trap: the binding's default
//    ratio is 3, so a `physicalSize` of 500 on its own is a 167 dp window.
//    All four files that had the idiom before #414 had copied all three
//    lines, and for three of them the ratio line is the difference between
//    the window they asked for and a third of it. `sizeView` in
//    `test/view_size.dart` is those three lines.
//
//    `physicalConstraints` is in that list because it reproduces #414
//    exactly: the `physicalSize` setter writes both, the
//    `physicalConstraints` setter writes only itself, and
//    `MediaQueryData.fromView` reads `physicalSize`. So the render view would
//    move and the query would not - the original defect, in the spelling the
//    framework's own doc points at.
//
// A *read* of any of them is not counted, because reading one is how a case
// asserts about the window it was given.
//
// What it cannot see:
//
//  * **a test that never sizes its window and means to.** Dozens pump at the
//    default 800x600, which is a legal wide window, and nothing in the source
//    tells a deliberate default from a forgotten one.
//  * **a tear-off.** `addTearDown(tester.binding.setSurfaceSize)` counts as
//    nothing, and that is one `() =>` away from the idiom #414 deleted
//    sixteen times. Resolving a tear-off is not worth it; knowing it is the
//    near miss is.
//  * **an untracked file is counted**, because `gitVisibleFiles` passes
//    `--others` - deliberately, so a rule applies to a file before it is
//    added. The side effect is that the obvious way to answer a `MediaQuery`
//    question - a throwaway probe test that calls `setSurfaceSize` - turns
//    this red, and raising the budget is not what such a file wants. Delete
//    the probe.
//
// ADR 0004 is why this is a test and not a lint. No lint could carry the
// first bullet: `setSurfaceSize` is a perfectly ordinary framework method,
// and what is wrong with it is a fact about this project's widgets.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';
import 'view_size.dart';

/// Where each file stood when the ratchet went in. One entry, and it is the
/// helper every other file goes through.
/// Keyed by file name, which holds only while `test/` is flat.
///
/// `areaOf` buckets a path of fewer than three segments under its last
/// segment, and all 229 files here are directly under `test/`. The first
/// `test/<dir>/` ever added would bucket by that directory instead and
/// quietly merge files into one number - so a key with no `.dart` on the end
/// is the sign that happened.
const Map<String, int> kBudget = {
  // `sizeView`'s own two assignments, which are the whole point of it: the
  // pair has to be written together, so it is written once.
  'view_size.dart': 2,
};

/// Collects the sites that size a window outside [kBudget]'s one file.
class _ViewSizeVisitor extends RecursiveAstVisitor<void> {
  _ViewSizeVisitor(this.unit);

  static const String _surface = 'setSurfaceSize';
  static const Set<String> _properties = {
    'physicalSize',
    'devicePixelRatio',
    // The header has why this third one belongs: it moves the render view and
    // leaves the query where it was, which is #414 itself.
    'physicalConstraints',
  };

  final CompilationUnit unit;
  final List<int> lines = [];

  void _record(int offset) =>
      lines.add(unit.lineInfo.getLocation(offset).lineNumber);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == _surface) _record(node.offset);
    super.visitMethodInvocation(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    // The left side only, so `a.b = c.physicalSize` is a read and not a site.
    final target = node.leftHandSide;
    final name = switch (target) {
      PropertyAccess(:final propertyName) => propertyName.name,
      PrefixedIdentifier(:final identifier) => identifier.name,
      _ => null,
    };
    if (name != null && _properties.contains(name)) _record(node.offset);
    super.visitAssignmentExpression(node);
  }
}

/// The lines of the counted sites in [unit], in source order.
List<int> viewSizeLines(CompilationUnit unit) {
  final visitor = _ViewSizeVisitor(unit);
  unit.accept(visitor);
  return visitor.lines;
}

/// Parses [source] and counts, for the rule's own tests.
List<int> linesIn(String source) => viewSizeLines(parseUnit(source));

void main() {
  // **The count cannot see this, which is why it is here.** A budget that has
  // gone *down* is printed rather than failed - `expectWithinBudget` says why,
  // and it is right: an expected count checked into a tree races on merge. So
  // `sizeView` losing one of its two lines reads as an area that shrank, and
  // every file in the suite would quietly render in a window a third of the
  // size it asked for. Measured: deleting the `devicePixelRatio` line passes
  // the sweep below.
  //
  // What catches it is asking the query, which is the whole thing the other
  // spelling gets wrong.
  testWidgets('the helper moves the query it is for', (tester) async {
    const asked = Size(500, 900);
    sizeView(tester, asked);

    Size? seen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            seen = MediaQuery.sizeOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      seen,
      asked,
      reason:
          'MediaQuery is not where the helper put the window - at the '
          "binding's default ratio of 3 this reads a third of it",
    );
    expect(
      tester.view.physicalSize,
      asked,
      reason: 'the view itself did not move either, so nothing was sized',
    );
  });

  group('the rule', () {
    test('counts the surface size, however it is reached', () {
      expect(
        linesIn('f() async { await tester.binding.setSurfaceSize(s); }'),
        hasLength(1),
      );
      expect(linesIn('f() { binding.setSurfaceSize(null); }'), hasLength(1));
      expect(linesIn('f() { setSurfaceSize(s); }'), hasLength(1));
    });

    // The spelling a reader of the framework's own `physicalSize` doc would
    // reach for, and the one that reproduces #414 rather than fixing it.
    test('counts the one that moves the view and not the query', () {
      expect(
        linesIn('f() { tester.view.physicalConstraints = c; }'),
        hasLength(1),
      );
    });

    // What somebody hand-writing the pair reaches for. Both halves are sites.
    test('counts a cascade, once per assignment', () {
      expect(
        linesIn('f() { tester.view..physicalSize = s..devicePixelRatio = 1; }'),
        hasLength(2),
      );
    });

    test('counts an assignment to either property', () {
      expect(linesIn('f() { tester.view.physicalSize = s; }'), hasLength(1));
      expect(
        linesIn('f() { tester.view.devicePixelRatio = 1; }'),
        hasLength(1),
      );
      // Two segments rather than three, which the analyzer gives as a
      // `PrefixedIdentifier` instead of a `PropertyAccess` - the shape a file
      // that reads the view into a local produces.
      expect(linesIn('f() { view.physicalSize = s; }'), hasLength(1));
    });

    test('is not a read of one', () {
      expect(linesIn('f() { final s = tester.view.physicalSize; }'), isEmpty);
      expect(linesIn('f() { g(tester.view.devicePixelRatio); }'), isEmpty);
      expect(linesIn('f() { x = y.physicalSize; }'), isEmpty);
    });

    test('is not the helper every file is supposed to call', () {
      expect(linesIn('f() { sizeView(tester, s); }'), isEmpty);
    });

    test('is not something that merely mentions it', () {
      expect(linesIn('f() { log("setSurfaceSize"); }'), isEmpty);
      expect(linesIn('// tester.view.physicalSize = s;'), isEmpty);
    });

    // Both properties exist on other objects, and an assignment to one of
    // those is counted too. That is deliberate rather than a false positive:
    // the only property of that name a test has any business writing is the
    // view's, and a ratchet that tried to prove the receiver was a view would
    // have to resolve types it does not load.
    test('does not try to prove the receiver is a view', () {
      expect(linesIn('f() { image.physicalSize = s; }'), hasLength(1));
    });

    test('finds it wherever it is nested', () {
      expect(
        linesIn('f() { g(onTap: () => tester.view.physicalSize = s); }'),
        hasLength(1),
      );
    });

    test('reports the line the site is on', () {
      expect(linesIn('f() {\n  g();\n  tester.view.physicalSize = s;\n}'), [3]);
    });
  });

  test('no test file sizes its window outside the helper', () {
    final result = countAcross(
      dartFilesUnderTest(),
      (unit, _) => viewSizeLines(unit),
      expected: 'the whole of test/',
      atLeast: 100,
    );

    expectWithinBudget(
      counted: result.counted,
      budget: kBudget,
      sites: result.sites,
      budgetFile: 'test/view_size_budget_test.dart',
      why:
          'setSurfaceSize and physicalConstraints do not move MediaQuery, and '
          'physicalSize without '
          'devicePixelRatio is a window a third of the size it says: either '
          'way the tree is laid out at one size while MediaQuery.sizeOf '
          'answers another, and anything reading the query runs the wrong '
          'layout with nothing to say so.\n'
          'Call sizeView(tester, size) from test/view_size.dart instead, '
          'whose doc has the mechanism.\n'
          'If a case genuinely has to reach the view itself, say why in a '
          'comment and raise kBudget in test/view_size_budget_test.dart.',
    );
  });
}
