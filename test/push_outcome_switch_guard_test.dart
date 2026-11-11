// A guard on the one promise `outcomeOf` makes that nothing else can keep.
//
// Its doc comment says: "There is deliberately no `default`: the next status
// the plugin adds should break the build, the way this one did." That is the
// whole reason the method exists in this shape - `firebase_messaging` 16.7.1
// added `AuthorizationStatus.deniedPermanently` and the non-exhaustive switch
// expression is what stopped the build and forced a decision about it.
//
// The promise is one edit away from being void, and no other gate notices:
// append `_ => PermissionOutcome.unknown` and `flutter analyze` is clean, the
// whole suite is green - `push_denied_cause_test.dart` included, because it
// compares the table it declares against `AuthorizationStatus.values` and
// never looks at the switch - and the format gate is clean. The next status
// would then fold into `unknown`, which draws no notice, so a user who
// refused notifications would be told nothing and offered nothing.
//
// Turning a switch *statement* with a `default` back into the body would do
// the same, so that is checked too: only a switch expression over enum
// constants is exhaustive by the language's own rules, which is the mechanism
// the comment is relying on.
//
// This is cheap to delete if the design changes. What it must not do is
// outlive the comment silently.
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

const _source = 'lib/services/notifications/push_service.dart';
const _method = 'outcomeOf';

class _Finder extends RecursiveAstVisitor<void> {
  MethodDeclaration? method;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == _method) method = node;
    super.visitMethodDeclaration(node);
  }
}

class _Switches extends RecursiveAstVisitor<void> {
  final expressions = <SwitchExpression>[];
  final statements = <SwitchStatement>[];
  final wildcards = <DartPattern>[];

  @override
  void visitSwitchExpression(SwitchExpression node) {
    expressions.add(node);
    for (final member in node.cases) {
      final pattern = member.guardedPattern.pattern;
      if (pattern is WildcardPattern) wildcards.add(pattern);
    }
    super.visitSwitchExpression(node);
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    statements.add(node);
    super.visitSwitchStatement(node);
  }
}

void main() {
  late _Switches switches;

  setUpAll(() {
    final file = File(_source);
    expect(
      file.existsSync(),
      isTrue,
      reason: '$_source has moved - point this guard at it or delete both',
    );
    final finder = _Finder();
    parseUnit(file.readAsStringSync(), path: _source).accept(finder);

    // Without this the guard would pass by finding nothing at all, which is
    // how a renamed method turns a gate into decoration.
    expect(
      finder.method,
      isNotNull,
      reason:
          '`$_method` not found in $_source. If it was renamed, rename it '
          'here; if it is gone, delete this guard with it.',
    );

    switches = _Switches();
    finder.method!.accept(switches);
  });

  test('$_method still maps the enum with a switch expression', () {
    expect(
      switches.expressions,
      hasLength(1),
      reason:
          '`$_method` should hold exactly one switch expression over '
          '`AuthorizationStatus`; a different shape is not exhaustive by '
          'construction and the comment on it says it is.',
    );
  });

  test('no switch statement crept in to carry a `default`', () {
    expect(
      switches.statements,
      isEmpty,
      reason:
          'a switch statement in `$_method` can hold a `default`, and then a '
          'status added by the plugin compiles instead of breaking the build.',
    );
  });

  test('no arm matches anything the plugin has not declared', () {
    expect(
      switches.wildcards.map((p) => p.toSource()),
      isEmpty,
      reason:
          'a `_` arm makes the switch exhaustive for every future value, so '
          'the next `AuthorizationStatus` would fold into whatever that arm '
          'returns, silently. Add the arm and its row in '
          '`push_denied_cause_test.dart` instead.',
    );
  });
}
