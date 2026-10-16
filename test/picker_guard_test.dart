// The ninth ratchet, and the third whose budget is zero everywhere.
//
// QUNLEASHED-K: the file browser's "Upload files" called
// `FilePicker.platform.pickFiles` with no `try` around it, from a
// `ListTile.onTap` that did not await the future either. Android's picker
// answered `unknown_path` - the chosen item's provider handed back no stream,
// so `FilePickerDelegate` failed the whole pick rather than returning a file
// with a null path - and `file_picker_io.dart` rethrows a `PlatformException`
// for that. With no `try` at the call site and no listener on the future, the
// rejection reached the zone: `PlatformDispatcher.onError`, reported fatal,
// app gone, behind a picker the user was still looking at.
//
// Three more sites had the same shape the day this went in, and the pixel
// editor's was the instructive one: its three export entry points each have a
// `try`, and each awaited `_pickDestination()` one line *above* it.
//
// A guard rather than a budget, because this one has no legacy to drain: all
// four sites moved in the same change, so zero is both the current count and
// the target.
//
// **What it holds is the `try`, not the handling.** That the catch says
// something useful is not expressible here - `test/bare_catch_budget_test.dart`
// is what notices a catch that keeps nothing, and the `caught` budget is what
// keeps the record from becoming noise. This holds the door the incident came
// through, which is a picker call whose rejection has nowhere to land.
//
// An AST walk and not a regex, per ADR 0004: whether a call sits inside a
// `try` is a question about nesting, and the one site that made this worth
// writing was a call *next to* a `try` in a method that reads, line-wise,
// exactly like one inside it.
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

/// Whether [node] sits in the body of a `try`, in the same function.
///
/// A `catch` or `finally` clause is deliberately not one: a picker call there
/// is as unguarded as one with no `try` in sight, and it reads as covered.
///
/// A closure boundary ends the walk. A `try` outside a function expression
/// does not catch what the body throws when somebody calls it later, and the
/// honest answer to "is this one of ours?" for a picker inside a callback is
/// yes.
///
/// The blind spot it accepts: a picker wrapped one level down, in a helper
/// that every caller awaits inside a `try`. That is a real way to be safe and
/// this counts it anyway - which is the stricter direction, and the reason
/// zero is reachable is that all seven sites under `lib/` catch for
/// themselves.
bool isInsideTryBody(AstNode node) {
  AstNode child = node;
  for (AstNode? parent = node.parent; parent != null; parent = parent.parent) {
    if (parent is TryStatement && parent.body == child) return true;
    if (parent is FunctionExpression) return false;
    child = parent;
  }
  return false;
}

/// Where [unit] calls the picker without a `try`, or nothing.
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
    if (isPickerCall(node) && !isInsideTryBody(node)) {
      lines.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    super.visitMethodInvocation(node);
  }
}

void main() {
  test('every picker call sits inside a try', () {
    final found = countAcrossLib(unguardedPickersIn);
    expectWithinBudget(
      counted: found.counted,
      budget: const <String, int>{},
      sites: found.sites,
      budgetFile: 'test/picker_guard_test.dart',
      why:
          'A picker rejects - Android answers unknown_path when it cannot '
          'resolve what the user chose - and these are reached from taps that '
          'do not await, so an uncaught rejection is a fatal error and the app '
          'dies behind the dialog (QUNLEASHED-K). Wrap the call, record the '
          'failure at LogService.caught, and show commonPickFailed.',
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
      // The folder pick and the save dialog reject the same way, and two of
      // the four sites this went in with were folder picks.
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

    test('inside a try, which is the whole point', () {
      expect(
        linesIn(
          'f() async { try { await FilePicker.platform.pickFiles(); }'
          ' catch (e) {} }',
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

    test('not a comment, and not another API that picks something', () {
      expect(linesIn('// FilePicker.platform.pickFiles()\nf() {}'), isEmpty);
      expect(linesIn('f() async => picker.pickFiles();'), isEmpty);
      expect(linesIn('f() async => FilePicker.pickFiles();'), isEmpty);
    });
  });
}
