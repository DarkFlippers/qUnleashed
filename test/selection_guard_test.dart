// A guard on pages that keep their own multi-select. Budget zero everywhere.
//
// #375, and QUNLEASHED-P is what the duplication cost - one `setState` on a
// disposed `State`, six call sites of the same shape, and a guard that had to
// go into four files. `ListSelection.exitSelection` tells that story where the
// guard lives. Four archive pages wrote the same `Set<String>`, the same three
// methods and a select-all each spelled its own way: the category list, the
// deleted and favourites lists, and the file browser.
//
// So the thing worth holding is not the guard - `list_selection_test.dart` and
// `archive_bulk_outlives_page_test.dart` hold that between them - but the
// *sharing*. A fifth page that wrote its own selection would pass every other
// test in this suite: no budget moves, both of those files still pass, and the
// new page's exit would be unguarded exactly where nothing looks.
//
// **What it keys off is the row's own parameter.** Every selection surface in
// the app is built from one of the three row widgets that take
// `selectionMode` - `filelist/table.dart`, `browser/widgets/file_table.dart`
// and `browser/widgets/file_row.dart` - so a page that shows a selection
// passes that argument, and a page that passes it has to take the state from
// `ListSelection`. All ten of those arguments in `lib/` are passed by the four
// pages today.
//
// The blind spot is a page whose rows learn about a selection some other way:
// a positional argument, a differently named one, or a fourth row widget. It
// is empty today and a fourth row widget would be the thing to look at.
//
// A forwarder is not an owner: a widget that passes `selectionMode:
// widget.selectionMode` down to its own child is handing on what its parent
// gave it. **No widget in `lib/` does that yet** - the three row widgets
// consume the parameter and pass it to nothing - so that exclusion is
// pre-emptive, and the shape it describes is the one a row split in two would
// take.
//
// An AST walk and not a grep, per ADR 0004: both halves of the question -
// which class an argument sits in, and what that class mixes in - are about
// nesting, and the word appears in prose in three files including this one.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// The mixin every multi-select in `lib/` takes its state from.
const String kSelectionMixin = 'ListSelection';

/// The argument the three row widgets take, and the token this whole rule
/// reads.
///
/// Named once because it is the rule's weak point: renaming this parameter
/// across `lib/` would leave the count at zero for ever, and the second test
/// below is the control that fails when it stops being passed at all.
const String kSelectionArgument = 'selectionMode';

/// Whether [node] hands a selection to a widget rather than passing on one it
/// was given.
///
/// `widget.selectionMode` is the forwarding shape and the only one excluded:
/// anything else - a field, a local, a getter off the mixin - is a class that
/// decided what the answer is.
bool ownsSelectionArgument(NamedArgument node) {
  if (node.name.lexeme != kSelectionArgument) return false;
  // The deprecated accessor, for the reason `ratchet.dart`'s `namedArgument`
  // gives: `argumentExpression2` is `@experimental` and CI makes that fatal.
  final value = node.argumentExpression;
  if (value is PrefixedIdentifier) return value.prefix.name != 'widget';
  if (value is PropertyAccess) {
    final target = value.target;
    return !(target is SimpleIdentifier && target.name == 'widget');
  }
  return true;
}

/// Whether [clause] mixes [kSelectionMixin] in.
bool takesSharedSelection(WithClause? clause) =>
    mixinsNamed(clause, kSelectionMixin).isNotEmpty;

/// Whether [node] reads the mixin's own `selectionMode` getter, in a class
/// that has the mixin to read it from.
///
/// The one spelling forgiven, and the reason the forgiveness is per-argument
/// rather than per-class: a page can take the shared selection for one list
/// and still keep a hand-written `bool` for a second one, and the class-wide
/// version of this let the whole file through on the strength of the `with`
/// clause. Both halves are needed - the bare name alone would forgive a page
/// that called its own field `selectionMode`, and the `with` clause alone
/// forgives the second list.
///
/// A `mixin` cannot have a `with` clause, so a hand-written selection hoisted
/// into one is never forgiven here, which is the point.
bool _readsSharedGetter(NamedArgument node) {
  final value = node.argumentExpression;
  if (value is! SimpleIdentifier || value.name != kSelectionArgument) {
    return false;
  }
  final owner = node.thisOrAncestorOfType<ClassDeclaration>();
  return owner != null && takesSharedSelection(owner.withClause);
}

/// Collects what each declaration in [unit] does about a selection.
///
/// Every declaration, not only classes. A `MixinDeclaration` is not a
/// `ClassDeclaration`, and the first version of this file walked only the
/// latter - so a page that hoisted its hand-written selection into a one-page
/// mixin, an `extension on State<P>` or a top-level row builder passed the
/// guard that exists to stop exactly that. Hoisting it into a mixin is the
/// most natural way somebody "shares" a selection without finding this one.
class _SelectionVisitor extends RecursiveAstVisitor<void> {
  _SelectionVisitor(this.unit);

  final CompilationUnit unit;

  /// Lines where something hands out a selection without taking the state from
  /// the mixin.
  final List<int> unshared = [];

  /// Lines of the classes that mix it in, and of every [kSelectionArgument]
  /// passed at all - the two halves of the vacuity guard.
  ///
  /// Both are needed and they fail differently. A rule whose subject has left
  /// `lib/` passes over anything, and the subject can leave in two ways: the
  /// pages stop mixing the mixin in, or the row widgets stop taking the
  /// argument this rule reads. The second is the one a rename causes, and
  /// counting only [sharing] would not see it.
  final List<int> sharing = [];
  final List<int> arguments = [];

  void _takeSharing(WithClause? clause, Token keyword) {
    if (!takesSharedSelection(clause)) return;
    // The keyword, not the declaration's own offset: an `AnnotatedNode` starts
    // at its doc comment, so a page that grows a `///` would have the failure
    // cite the comment's line.
    sharing.add(unit.lineInfo.getLocation(keyword.offset).lineNumber);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _takeSharing(node.withClause, node.classKeyword);
    super.visitClassDeclaration(node);
  }

  /// `class A = B with ListSelection;` is the same decision in the other
  /// spelling, which `mixinsNamed`'s own doc warns about and the
  /// visible-surface census learned the hard way.
  @override
  void visitClassTypeAlias(ClassTypeAlias node) {
    _takeSharing(node.withClause, node.typedefKeyword);
    super.visitClassTypeAlias(node);
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    if (node.name.lexeme == kSelectionArgument) {
      arguments.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    if (ownsSelectionArgument(node) && !_readsSharedGetter(node)) {
      unshared.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    super.visitNamedArgument(node);
  }
}

/// Where [unit] shows a selection without sharing the state behind it.
///
/// [path] is unused; the signature is [countAcrossLib]'s. Nothing is exempt,
/// including `components/selection.dart`: the mixin passes no arguments, so an
/// exemption would cover nothing while hiding the one file a second selection
/// shape would most likely be written in.
List<int> unsharedSelectionsIn(CompilationUnit unit, String path) {
  final visitor = _SelectionVisitor(unit);
  unit.visitChildren(visitor);
  return visitor.unshared;
}

void main() {
  // One walk for both rules. `countAcrossLib` lists and parses every file
  // under `lib/` - 1.5s here - and the visitor fills all three of its lists on
  // the same visit, so a second walk would re-derive what the first one had in
  // hand. `picker_guard_test.dart` keeps a rule on its own walk for a reason
  // that does not apply here: it has two budgets, and merging would trade one
  // number in a budget failure for three. This file has one budget.
  late ({Map<String, int> counted, Map<String, List<String>> sites}) found;
  late int sharing;
  late int arguments;

  setUpAll(() {
    var shared = 0;
    var passed = 0;
    found = countAcrossLib((unit, path) {
      final visitor = _SelectionVisitor(unit);
      unit.visitChildren(visitor);
      shared += visitor.sharing.length;
      passed += visitor.arguments.length;
      return visitor.unshared;
    });
    sharing = shared;
    arguments = passed;
  });

  test('every selection on screen is the shared one', () {
    expectWithinBudget(
      counted: found.counted,
      budget: const <String, int>{},
      sites: found.sites,
      budgetFile: 'test/selection_guard_test.dart',
      why:
          'Four archive pages kept their own copy of the selection flag, the '
          'selected set and the exit, and QUNLEASHED-P had to be fixed in all '
          'four - one setState on a disposed State, with the guard needed one '
          'statement away from a mounted check that was already there, and a '
          'fifth site that had none. Mix in ListSelection from '
          'components/selection.dart: it holds the flag, the set, the '
          'invariant that ties them together and the guard, and the pages keep '
          'setState and own nothing (ADR 0001).',
    );
  });

  test('and the rule above still has a subject, on both its tokens', () {
    expect(
      sharing,
      greaterThanOrEqualTo(4),
      reason:
          'expected the four archive pages to mix $kSelectionMixin in, found '
          '$sharing - a rule whose subject has left lib/ passes over anything',
    );
    // The half a rename would take out, and the reason this test reads two
    // numbers. The rule above counts `$kSelectionArgument` arguments, not
    // mixin clauses - so spelling that parameter `selecting:` across `lib/`
    // would leave it at zero for ever while the check above stayed green. Ten
    // today, all of them in the four pages.
    expect(
      arguments,
      greaterThanOrEqualTo(10),
      reason:
          'expected the row widgets to still take $kSelectionArgument, found '
          '$arguments passed - renaming it makes the rule above a no-op',
    );
  });

  group('what counts as a page keeping its own selection', () {
    List<int> linesIn(String source) =>
        unsharedSelectionsIn(parseUnit(source), 'lib/pages/x.dart');

    test('the shape that was written four times', () {
      expect(
        linesIn(
          'class S extends State<P> {\n'
          '  bool _selectionMode = false;\n'
          '  Widget build(c) => Row(selectionMode: _selectionMode);\n'
          '}',
        ),
        hasLength(1),
      );
    });

    test('the same page taking the state from the mixin', () {
      expect(
        linesIn(
          'class S extends State<P> with ListSelection<P> {\n'
          '  Widget build(c) => Row(selectionMode: selectionMode);\n'
          '}',
        ),
        isEmpty,
      );
    });

    test('a mixin among others still counts as taking it', () {
      expect(
        linesIn(
          'class S extends State<P>\n'
          '    with SingleTickerProviderStateMixin, ListSelection<P> {\n'
          '  Widget build(c) => Row(selectionMode: selectionMode);\n'
          '}',
        ),
        isEmpty,
      );
    });

    // Nothing in `lib/` forwards the parameter today; this is the shape a row
    // split in two would take, and a forwarder has no selection to guard.
    test('a widget passing on what its parent gave it', () {
      expect(
        linesIn(
          'class S extends State<Row> {\n'
          '  Widget build(c) => Cell(selectionMode: widget.selectionMode);\n'
          '}',
        ),
        isEmpty,
      );
      expect(
        linesIn(
          'class R extends StatelessWidget {\n'
          '  final bool selectionMode;\n'
          '  Widget build(c) => Cell(selectionMode: selectionMode);\n'
          '}',
        ),
        // A `StatelessWidget` cannot mix the state in - it has no `setState`
        // and nothing to be mounted - and the bare name is forgiven only
        // inside a class that has the mixin, so this one is counted: the
        // rule's blind spot in the safe direction. Zero is still reachable
        // because no widget in `lib/` forwards it that way today, and the fix
        // when one does is the shape above - take it as a parameter and pass
        // `widget.selectionMode`.
        hasLength(1),
      );
    });

    // The four shapes a review drove out of the first version of this rule,
    // which asked only `visitClassDeclaration` and forgave a whole class for
    // its `with` clause. Each one read as compliant while holding a
    // hand-written flag, a set and an unguarded exit.
    test('the copy hoisted into a mixin of its own', () {
      // The likeliest next copy: this is what "sharing" looks like to
      // somebody who did not find `ListSelection`. A `mixin` cannot have a
      // `with` clause, so it can never be the shared one.
      expect(
        linesIn(
          'mixin _MySelection<T extends StatefulWidget> on State<T> {\n'
          '  bool _selectionMode = false;\n'
          '  final Set<String> _selected = {};\n'
          '  Widget row() => Row(selectionMode: _selectionMode);\n'
          '}',
        ),
        hasLength(1),
      );
    });

    test('and into an extension, or a function with no class at all', () {
      expect(
        linesIn(
          'extension Rows on State<P> {\n'
          '  Widget row(bool mode) => Row(selectionMode: mode);\n'
          '}',
        ),
        hasLength(1),
      );
      expect(
        linesIn(
          'bool _selectionMode = false;\n'
          'Widget buildRow() => Row(selectionMode: _selectionMode);',
        ),
        hasLength(1),
      );
    });

    test('a second selection beside the shared one is still its own', () {
      // The half-migrated page: it takes the mixin for one list and keeps a
      // hand-written flag for another. Forgiving the class for its `with`
      // clause dropped both.
      expect(
        linesIn(
          'class S extends State<P> with ListSelection<P> {\n'
          '  bool _otherMode = false;\n'
          '  Widget build(c) => Column(children: [\n'
          '    Row(selectionMode: selectionMode),\n'
          '    Row(selectionMode: _otherMode),\n'
          '  ]);\n'
          '}',
        ),
        hasLength(1),
      );
    });

    test('a field called selectionMode is not the mixin reading its own', () {
      // The bare name is forgiven only where the mixin is in scope to supply
      // it; a page that names its own flag that way is not sharing anything.
      expect(
        linesIn(
          'class S extends State<P> {\n'
          '  bool selectionMode = false;\n'
          '  Widget build(c) => Row(selectionMode: selectionMode);\n'
          '}',
        ),
        hasLength(1),
      );
    });

    test('a row that only declares the parameter, and passes nothing', () {
      expect(
        linesIn(
          'class R extends StatelessWidget {\n'
          '  final bool selectionMode;\n'
          '  Widget build(c) => selectionMode ? A() : B();\n'
          '}',
        ),
        isEmpty,
      );
    });

    test('a different argument of the same name is not one of these', () {
      expect(
        linesIn(
          'class S extends State<P> {\n'
          '  Widget build(c) => Row(selected: _selected);\n'
          '}',
        ),
        isEmpty,
      );
    });
  });

  group('what counts as taking the shared selection', () {
    /// The `sharing` half of the walk above, which the vacuity guard reads.
    int sharingIn(String source) {
      final unit = parseUnit(source);
      final visitor = _SelectionVisitor(unit);
      unit.visitChildren(visitor);
      return visitor.sharing.length;
    }

    test('the clause, whatever else is in it', () {
      expect(
        sharingIn(
          'class A extends State<P> with ListSelection<P> {}\n'
          'class B extends State<Q> with Other {}',
        ),
        1,
      );
    });

    test('and the other spelling of the same decision', () {
      // `class A = B with M;` is a `ClassTypeAlias`, which a visitor that
      // overrides only `visitClassDeclaration` never sees - the mistake
      // `mixinsNamed`'s doc in `ratchet.dart` warns about.
      expect(sharingIn('class A = B with ListSelection;'), 1);
    });
  });
}

// Mutations run, each checked against the single case named: dropping the
// `widget` check in `ownsSelectionArgument` fails the forwarder case; dropping
// its name check counts every named argument, which fails "a different
// argument of the same name" and the count over `lib/` and nothing else here;
// `ratchet.dart`'s `mixinsNamed` narrowed to the first mixin type fails "a
// mixin among others", and dropping its `ClassTypeAlias` override here fails
// "the other spelling"; dropping the `with`-clause half of
// `_readsSharedGetter` fails "a field called selectionMode"; going back to
// collecting only from `visitClassDeclaration` fails the mixin, extension and
// top-level cases; and forgiving a whole sharing class fails "a second
// selection beside the shared one".
//
// The control itself is mutated too: spelling [kSelectionArgument]
// `selecting` - a stand-in for that parameter being renamed across `lib/` -
// leaves the budget rule green at zero and fails the second test. That is the
// one way this rule can rot without anybody touching a page.
