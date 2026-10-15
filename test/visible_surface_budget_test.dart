// A census of what the app has asked a replay to show.
//
// The other ratchets in this directory count debt. This one counts a
// decision, and it exists because `VisibleSurface` is the only mechanism in
// the app that fails *open*.
//
// `mask<T>()` and `unmask<T>()` are not mirror images. A surface nobody
// thought to mask stays masked, because `maskAllText` is the default and
// catches it; a surface somebody marks visible is shown, and
// `WidgetFilter._process` stops descending on an unmask decision, so the
// whole subtree goes with it - including a `SensitiveSurface` placed inside
// one, which is never reached. ADR 0013 §6.4, and `sensitive_surface.dart`'s
// own file doc, record that enumerating surfaces failed here once already:
// two of seven were found only on a second review pass.
//
// So a fifth marker should be a deliberate act rather than a line in a diff
// nobody reads twice. Raising the number below is that act. What it cannot
// see is the `ButtonStyleButton` rule in `telemetry/options.dart`, which is a
// type rule and has no site in `lib/` to count - that one is pinned by
// `telemetry_lifecycle_test.dart` instead.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// What each area holds. Raise one only with a line saying what was shown.
///
/// `lib/app` - `_BottomTab`, whose four labels are `l10n.nav*` constants and
/// the device label, itself a switch over constants.
/// `lib/components` - `_DeviceSubtitle`, the Flipper's name under the app bar
/// title.
/// `lib/pages/devices` - `FlipperInfoLine`, the label/value row the device
/// info card and the full-info sheet are built from, so the whole `device
/// info` map the firmware answers with. That one is open-ended by nature: the
/// decision was the dump, not a reviewed field list.
const Map<String, int> kBudget = {
  'app': 1,
  'components': 1,
  'pages/devices': 1,
};

const String kAdr = 'docs/adr/0013-observability-with-sentry.md';

/// Collects `with VisibleSurface` clauses.
///
/// The analyzer and not a grep, for the reason every ratchet here gives: the
/// name appears in prose in `sensitive_surface.dart` and in this file, and a
/// text match would count both and then count them differently the day
/// somebody rewraps a comment.
class _MixinVisitor extends RecursiveAstVisitor<void> {
  _MixinVisitor(this.unit);

  final CompilationUnit unit;
  final List<int> lines = [];

  void _check(NamedType? type, int offset) {
    if (type?.name.lexeme == 'VisibleSurface') {
      lines.add(unit.lineInfo.getLocation(offset).lineNumber);
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    for (final type in node.withClause?.mixinTypes ?? const <NamedType>[]) {
      _check(type, node.offset);
    }
    super.visitClassDeclaration(node);
  }
}

List<int> _linesIn(CompilationUnit unit, String path) {
  // `sensitive_surface.dart` declares the mixin and must not count as a use
  // of it. `SensitiveSurfaceBox` lives there too and mixes in the *other*
  // marker, so this is about the declaration site rather than that class.
  if (isExempt(path, const {'components/sensitive_surface.dart'})) return [];
  final visitor = _MixinVisitor(unit);
  unit.visitChildren(visitor);
  return visitor.lines;
}

void main() {
  test('the rule counts a class that mixes the marker in', () {
    final unit = parseUnit('''
mixin VisibleSurface on Widget {}
class A extends StatelessWidget with VisibleSurface {}
class B extends StatelessWidget {}
''');
    final visitor = _MixinVisitor(unit);
    unit.visitChildren(visitor);
    expect(visitor.lines, hasLength(1));
  });

  test('the rule is not the other marker', () {
    final unit = parseUnit('''
class A extends StatelessWidget with SensitiveSurface {}
''');
    final visitor = _MixinVisitor(unit);
    unit.visitChildren(visitor);
    expect(visitor.lines, isEmpty);
  });

  test('no area shows more in a replay than its budget', () {
    final result = countAcrossLib(_linesIn);

    expectWithinBudget(
      counted: result.counted,
      budget: kBudget,
      sites: result.sites,
      budgetFile: 'test/visible_surface_budget_test.dart',
      why:
          'A `VisibleSurface` is a decision to show a widget and everything '
          'under it in a screen recording, and the unmask stops the walk, so '
          'a `SensitiveSurface` inside one is never reached.\n'
          'If the surface was reviewed and may be seen, raise kBudget in '
          'test/visible_surface_budget_test.dart and say what it shows.\n'
          'See $kAdr',
    );
  });
}
