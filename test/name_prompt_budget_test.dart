// A ratchet on prompts that ask for a string by hand.
//
// #266 found eight copies of one AlertDialog/TextField/two-TextButton
// skeleton and extracted `QNameDialog`; #277 found that three of those copies
// wrote a user-named file to the Flipper with no rule at all - as did the
// inline rename, which is a field in a row rather than one of the eight. The dialog now carries
// the rule as a value, so a caller cannot forget it - but nothing stopped a
// ninth hand-rolled prompt from being written beside it, and per ADR 0004 the
// answer to "we want less of this" is a number, not a sentence in a comment.
//
// What is left is not a defect. Three of the four ask for numbers, a URL and a
// set of keys rather than a name, so they want a shared *text* prompt rather
// than this one; the fourth asks for a name through a rule of its own that
// collapses runs of `_`, and names a folder on the host rather than a file on
// the device. Each is named below, and the number must not rise.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// What each area held when this went in. Lower one when a prompt moves to
/// `QNameDialog` or to whatever shared text prompt replaces these.
const Map<String, int> kBudget = {
  // One helper in the hex editor, serving four prompts: an offset, a fill
  // byte, a `count x byte` expression and a run of text to insert. None of
  // them is a file name.
  'pages/archive': 1,
  // Two helpers, serving a Flibler index URL and the map's keys, tile URL
  // template, subdomain list and max zoom. None of them is a file name
  // either.
  'pages/option': 2,
  // The paint editor's name, whose rule collapses runs of `_` - a rule of its
  // own, not a copy of the device's.
  'pages/tools': 1,
};

const String kAdr = 'docs/adr/0004-ratchet-not-lint.md';

/// The one prompt that is allowed to call `showDialog<String>`: the shared one.
const Set<String> kExempt = {'components/dialogs/name.dart'};

/// Collects `showDialog<String>(...)` calls.
///
/// By the type argument, which is what makes a dialog a *prompt* rather than a
/// confirmation: `showDialog<bool>` is `QConfirmDialog`'s business and
/// `showDialog<void>` is every sheet in the app. A comment mentioning the name
/// does not match, which a `grep` would.
class _PromptVisitor extends RecursiveAstVisitor<void> {
  _PromptVisitor(this.lineFor);

  final int Function(int offset) lineFor;
  final List<int> lines = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final args = node.typeArguments?.arguments;
    if (node.methodName.name == 'showDialog' &&
        args != null &&
        args.length == 1 &&
        args.single.toSource() == 'String') {
      lines.add(lineFor(node.offset));
    }
    super.visitMethodInvocation(node);
  }
}

List<int> _promptsIn(CompilationUnit unit, String path) {
  if (isExempt(path, kExempt)) return const [];
  final visitor = _PromptVisitor(
    (offset) => unit.lineInfo.getLocation(offset).lineNumber,
  );
  unit.visitChildren(visitor);
  return visitor.lines;
}

void main() {
  test('no area asks for a string by hand more often than its budget', () {
    final counted = countAcrossLib(_promptsIn);

    expectWithinBudget(
      counted: counted.counted,
      budget: kBudget,
      sites: counted.sites,
      budgetFile: 'test/name_prompt_budget_test.dart',
      why:
          'A prompt that asks for a name belongs in QNameDialog, which carries '
          'the rule the Flipper enforces (#277); one that asks for something '
          'else wants a shared text prompt (#278).\n'
          'See $kAdr',
    );
  });

  // The visitor, against the shapes it has to tell apart - a census that
  // matches nothing is green.
  test('counts a prompt that asks for a string', () {
    final unit = parseUnit('''
      Future<String?> f(BuildContext c) =>
          showDialog<String>(context: c, builder: (_) => const X());
    ''');
    expect(_promptsIn(unit, 'lib/pages/x.dart'), hasLength(1));
  });

  test('does not count a confirmation or a sheet', () {
    final unit = parseUnit('''
      void f(BuildContext c) {
        showDialog<bool>(context: c, builder: (_) => const X());
        showDialog<void>(context: c, builder: (_) => const X());
        showModalBottomSheet<String>(context: c, builder: (_) => const X());
      }
    ''');
    expect(_promptsIn(unit, 'lib/pages/x.dart'), isEmpty);
  });

  test('does not count a comment that mentions one', () {
    final unit = parseUnit('''
      /// Replaces a hand-rolled showDialog<String> prompt.
      void f() {}
    ''');
    expect(_promptsIn(unit, 'lib/pages/x.dart'), isEmpty);
  });

  test('does not count the shared prompt itself', () {
    final unit = parseUnit('''
      Future<String?> f(BuildContext c) =>
          showDialog<String>(context: c, builder: (_) => const X());
    ''');
    expect(_promptsIn(unit, 'lib/components/dialogs/name.dart'), isEmpty);
  });
}
