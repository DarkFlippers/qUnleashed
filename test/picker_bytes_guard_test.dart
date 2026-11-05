// The eighth ratchet, and the second whose budget is zero everywhere.
//
// QUNLEASHED-E: a user picked a 116 MB file in an importer that called
// `pickFiles(withData: true)`. On Android that makes the plugin load the whole
// file into a Java `byte[]` and then hand it back across the method channel,
// where `StandardMessageCodec` grows its buffer by doubling - so encoding the
// reply asked for one contiguous 232 MB allocation against the 256 MB that
// device allowed a process heap. The app died with an uncaught
// `OutOfMemoryError` on the main thread, where no Dart `try` can see it.
//
// A guard rather than a budget, because like the Sentry import this one has no
// legacy to drain: both call sites moved in the same change, so zero is the
// current count and the target.
//
// **What it holds is the argument, not the read.** A picked file is read in
// Dart, where the size can be checked first and the allocation is Dart's own;
// the platform is never asked to carry the bytes. The second half of that rule
// - that the read is capped - is not expressible here, because
// `io.File(path).readAsBytes()` is the same call whether or not a cap ran
// first, and some twenty sites under `lib/` read a file legitimately. The cap
// lives in `readPickedFile` and is held by `test/picked_file_test.dart`; this
// holds the door the incident came through.
//
// An AST visitor and not a regex, per ADR 0004: `withData: shouldLoad`,
// `withData : true` and a `withData` inside a comment are three different
// answers that a line-wise pattern gets wrong in three different ways. The
// first version of this guard *was* a regex, and its first run reported the
// doc comment that explains the rule.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// The arguments that make the platform, rather than Dart, carry the bytes.
///
/// `withReadStream` is here as well as `withData` because it is the same
/// mistake wearing a chunked coat: the plugin still pumps the file through the
/// channel, and nothing on this side has checked a size first.
const Set<String> byteCarryingArguments = {'withData', 'withReadStream'};

/// Whether [argument] asks the picker for the bytes.
///
/// Only the literal `false` is accepted. A variable, a const read or a
/// conditional might be false today, but the guard cannot say so and the
/// honest answer to "is this one of ours?" is no.
bool asksForBytes(Expression argument) =>
    argument is! BooleanLiteral || argument.value;

/// Where [unit] asks a picker to carry the bytes, or nothing.
List<int> pickerBytesIn(CompilationUnit unit, String path) {
  final visitor = _PickerBytesVisitor(unit);
  unit.accept(visitor);
  return visitor.lines;
}

class _PickerBytesVisitor extends RecursiveAstVisitor<void> {
  _PickerBytesVisitor(this.unit);

  final CompilationUnit unit;
  final List<int> lines = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'pickFiles') {
      for (final argument in node.argumentList.arguments) {
        if (argument is NamedArgument &&
            byteCarryingArguments.contains(argument.name.lexeme) &&
            asksForBytes(argument.argumentExpression)) {
          lines.add(unit.lineInfo.getLocation(argument.offset).lineNumber);
        }
      }
    }
    super.visitMethodInvocation(node);
  }
}

void main() {
  test('no picker asks the platform to carry the bytes', () {
    final found = countAcrossLib(pickerBytesIn);
    expectWithinBudget(
      counted: found.counted,
      budget: const <String, int>{},
      sites: found.sites,
      budgetFile: 'test/picker_bytes_guard_test.dart',
      why:
          'withData: true hands the whole file across the method channel and '
          'killed the app on a 116 MB pick (QUNLEASHED-E). Pick without it '
          'and read the path with readPickedFile, which checks the size '
          'first.',
    );
  });

  group('what counts as asking for the bytes', () {
    List<int> linesIn(String source) =>
        pickerBytesIn(parseUnit(source), 'lib/pages/x.dart');

    test('the literal that shipped the bug', () {
      expect(linesIn('f() => p.pickFiles(withData: true);'), hasLength(1));
    });

    test('a chunked read, which is the same mistake', () {
      expect(
        linesIn('f() => p.pickFiles(withReadStream: true);'),
        hasLength(1),
      );
    });

    test('anything that is not the literal false', () {
      // The spellings a regex on `withData:\s*true` misses, and the reason
      // this is a visitor. None of them can be shown to be safe from here.
      expect(linesIn('f() => p.pickFiles(withData: wanted);'), hasLength(1));
      expect(linesIn('f() => p.pickFiles(withData: kIsWeb);'), hasLength(1));
      expect(
        linesIn('f() => p.pickFiles(withData: a ? true : false);'),
        hasLength(1),
      );
    });

    test('not the literal false, and not leaving the argument out', () {
      expect(linesIn('f() => p.pickFiles(withData: false);'), isEmpty);
      expect(linesIn("f() => p.pickFiles(type: FileType.any);"), isEmpty);
    });

    test('not a comment, and not another call that takes the same name', () {
      // The regex this replaced reported its own doc comment, and would have
      // reported any unrelated API with an argument of the same name.
      expect(linesIn('// pickFiles(withData: true)\nf() {}'), isEmpty);
      expect(linesIn('f() => encode(withData: true);'), isEmpty);
    });
  });
}
