// Every `CategoryToolbar` offers a sort, and none is built without one.
//
// A guard rather than a budget, with an empty map like the other guards here:
// #314 made the last two callers pass one, so zero is both the current count
// and the target.
//
// It exists because the thing it holds is a single argument at a call site,
// and dropping it is invisible. `CategoryToolbar`'s `sort` is nullable - that
// nullability is how a table with nothing to sort says so - and the sort
// button is the *only* way to a folder sort below 460 logical pixels of table
// width, where `appsTableColumns` drops the folder column and its tappable
// header with it. So an apps-manager page that stopped passing it would hand
// every phone in portrait #122's original complaint back, with every unit
// test on the comparator still green: the ordering would be right and
// unreachable.
//
// Pumping those pages instead is not available: `AppsManagerPage` reaches
// `AppsBackend.instance` and primes a device and an update registry in
// `initState`, and the install page wants the ATP catalog. That is the trade
// this file makes.
//
// **What it cannot see:**
//
//  * A `sort` argument that is inert at runtime - an empty `opts` list, or a
//    `key` nothing offers. It reads syntax, not behaviour.
//  * A null arriving any way other than the two it knows: a literal, and
//    either branch of a conditional. `sort: _maybeSort()` passes, and so does
//    a control built from a field that happens to be null.
//  * A toolbar reached through a wrapper widget rather than built here.
//  * Whether the button's sheet sorts anything, which is
//    `apps_folder_sort_test.dart`'s and `archive_sort_button_test.dart`'s
//    half.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// Toolbars built with no `sort`, or with one that can be null.
class _ToolbarVisitor extends RecursiveAstVisitor<void> {
  _ToolbarVisitor(this.unit);

  final CompilationUnit unit;
  final List<int> lines = [];

  /// `CategoryToolbar(...)` parses as an invocation in an unresolved AST, and
  /// as a creation expression when written with `new` - so both arms, the way
  /// `client_reach_budget_test.dart` takes both for its own constructor.
  @override
  void visitMethodInvocation(MethodInvocation node) {
    // No receiver, like that file's own check: `x.CategoryToolbar(...)` is a
    // method on something else, whatever it is called.
    if (node.methodName.name == 'CategoryToolbar' &&
        node.target == null &&
        !_hasSort(node.argumentList)) {
      lines.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'CategoryToolbar' &&
        !_hasSort(node.argumentList)) {
      lines.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    super.visitInstanceCreationExpression(node);
  }

  /// Whether [arguments] hands the toolbar a sort that cannot be null.
  ///
  /// A conditional with a `null` branch counts as no sort, and that is the
  /// shape worth catching rather than a detail: `sort: wide ? null : control`
  /// is the tidy-up a reader reaches for once they notice the button
  /// duplicates a column header - and it is exactly the button that comes and
  /// goes with the window that `toolbar.dart` argues against, with phones on
  /// the losing side.
  ///
  /// `argumentExpression` and not `argumentExpression2`: the second is the one
  /// the analyzer is moving to and is `@experimental`, which `flutter analyze`
  /// reports and CI treats as fatal. The first carries `@ToBeDeprecated`,
  /// which reports nothing yet.
  static bool _hasSort(ArgumentList arguments) => arguments.arguments.any(
    (argument) =>
        argument is NamedArgument &&
        argument.name.lexeme == 'sort' &&
        !_canBeNull(argument.argumentExpression),
  );

  static bool _canBeNull(Expression expression) {
    if (expression is NullLiteral) return true;
    if (expression is ConditionalExpression) {
      return _canBeNull(expression.thenExpression) ||
          _canBeNull(expression.elseExpression);
    }
    return false;
  }
}

/// The lines of the offending call sites in [unit], in source order.
List<int> _toolbarsWithoutSortIn(CompilationUnit unit, String path) {
  final visitor = _ToolbarVisitor(unit);
  unit.accept(visitor);
  return visitor.lines;
}

/// Parses [source] and counts, for the rule's own tests.
List<int> toolbarsWithoutSort(String source) =>
    _toolbarsWithoutSortIn(parseUnit(source, path: 'lib/x.dart'), 'lib/x.dart');

void main() {
  group('the rule', () {
    test('counts a toolbar built with no sort at all', () {
      expect(
        toolbarsWithoutSort('Widget f() => CategoryToolbar(query: q);'),
        hasLength(1),
      );
    });

    test('counts one handed a literal null', () {
      // Which is how the two apps tables used to leave the button off, before
      // the argument was simply absent.
      expect(
        toolbarsWithoutSort('Widget f() => CategoryToolbar(sort: null);'),
        hasLength(1),
      );
    });

    test('counts one a width can turn off', () {
      // The regression this is really for: right ordering, unreachable on the
      // surface that needs it.
      expect(
        toolbarsWithoutSort(
          'Widget f() => CategoryToolbar(sort: wide ? null : ctrl);',
        ),
        hasLength(1),
      );
      expect(
        toolbarsWithoutSort(
          'Widget f() => CategoryToolbar(sort: wide ? ctrl : null);',
        ),
        hasLength(1),
      );
    });

    test('passes one handed a control, however it is built', () {
      expect(
        toolbarsWithoutSort('Widget f() => CategoryToolbar(sort: s);'),
        isEmpty,
      );
      expect(
        toolbarsWithoutSort(
          'Widget f() => CategoryToolbar(sort: _sort.control(_onSort));',
        ),
        isEmpty,
      );
      expect(
        toolbarsWithoutSort(
          'Widget f() => CategoryToolbar(sort: (key: k, asc: a, opts: o, '
          'onSort: f));',
        ),
        isEmpty,
      );
      expect(
        toolbarsWithoutSort(
          'Widget f() => CategoryToolbar(sort: wide ? wideCtrl : narrowCtrl);',
        ),
        isEmpty,
        reason: 'a conditional is fine as long as neither arm is null',
      );
    });

    test('is not another widget, or a method of that name on something', () {
      expect(
        toolbarsWithoutSort('Widget f() => AppsTable(items: i);'),
        isEmpty,
      );
      expect(
        toolbarsWithoutSort('Widget f() => builder.CategoryToolbar(q);'),
        isEmpty,
      );
    });

    test('reports the line the call is on', () {
      expect(
        toolbarsWithoutSort('Widget f() =>\n\n  CategoryToolbar(query: q);'),
        [3],
      );
    });
  });

  test('no area builds a toolbar without a sort', () {
    final found = countAcrossLib(_toolbarsWithoutSortIn);
    expectWithinBudget(
      counted: found.counted,
      budget: const <String, int>{},
      sites: found.sites,
      budgetFile: 'test/toolbar_sort_guard_test.dart',
      why:
          'Below 460 logical pixels of table width the folder column and its '
          'header are gone, so this button is the only way to a folder sort '
          '(#122, #314). Pass sort: - AppsSortState.control builds it for the '
          'apps tables - or, if this table really has nothing to sort, say so '
          'here and raise the number.',
    );
  });
}
