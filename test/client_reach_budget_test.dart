// A ratchet on code that reaches for the device client instead of being given
// one.
//
// `FlipperOneClient()` is a global factory in flipperlib; `FlipperOneClient()
// .get()` hands back the one live client from anywhere, with nothing in the
// signature of the calling class to say it depends on the device at all. ADR
// 0002 is the decision that new code takes its dependencies as parameters, and
// this number is that decision's scoreboard: it should fall, and it must not
// rise.
//
// The count is what makes two other decisions come out the way they do. ADR
// 0007 refuses a repository layer partly because these sites would become a
// third owner of the device during any gradual migration, and ADR 0004 chooses
// a ratchet over a `custom_lint` import rule because the import rule catches
// five files of which two are correct injection, and misses this entirely.
//
// What it cannot see:
//
//  * A client obtained once and stored - `late final _client =
//    FlipperOneClient().get();` counts once however many methods use it,
//    which is right for a scoreboard and wrong as a measure of coupling.
//  * A client passed down from one of these sites. The site is counted where
//    it is reached for; everything below it is invisible, and is also the
//    pattern ADR 0002 wants.
//  * A `FlipperClient` obtained some other way. There is no other way today,
//    which is the point of ADR 0002's alternative: give flipperlib a
//    non-global seam and these sites become a visible parameter rather than a
//    number to count.
//  * A test double. `test/` is not walked at all - only `lib/`.
//
// And one that makes it a proxy rather than a measure: a site removed by
// threading the client through six constructors and a site removed by making
// the widget stop touching the device both lower it by one, and only the
// second is the improvement ADR 0002 is after.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// What each area held when the ratchet went in. Lower one when a site goes.
///
/// Per area rather than one total, for the same reason as the log budget:
/// offsetting changes hide in a single number, and a failure can say where.
///
/// Each entry says what kind of site it is, because a number cannot. Someone
/// editing this map to get CI green reads the line they are changing.
const Map<String, int> kBudget = {
  // Composition roots. These two are where a global *should* be resolved
  // once, and they are the sites ADR 0002 expects to survive - they are how
  // everything below could be given a client instead of reaching for one.
  'app': 1,
  'main.dart': 1,
  // The connection picker and the appbar's connection indicator. Both are
  // widgets that talk to the device directly.
  'components': 2,
  // Controllers, mostly - the layer that would take a client as a constructor
  // parameter with no new abstraction at all.
  'pages/tools': 9,
  // Three controllers. Was 4 - `browser/widgets/storage_card.dart` takes a
  // client parameter now, passed by the one page that builds it, which is
  // what let it have a test at all.
  'pages/archive': 3,
  // The controller, and only as a fallback: `DeviceController` takes a client
  // parameter now and reaches for the global when nobody passes one. Was 2 -
  // the widget ADR 0004 named as the real smell an import lint would have
  // missed, `widgets/firmware_card.dart`, reads it off `DeviceScope` instead
  // and no longer imports flipperlib at all.
  'pages/devices': 1,
  'pages/apps': 1,
  'pages/flibler': 1,
  // Long-lived services that outlive any one page. They want a client handed
  // to them at construction by the same root that builds them.
  'services': 3,
};

const String kAdr =
    'https://github.com/DarkFlippers/qUnleashed/blob/main/docs/adr/'
    '0002-dependencies-are-passed-in.md';

/// Collects `FlipperOneClient()` call sites.
///
/// Both node kinds, because which one the parser produces depends on things
/// this test has no view of. Unresolved, `FlipperOneClient()` is a
/// [MethodInvocation] with no target; write `const` or `new` in front of it
/// and it is an [InstanceCreationExpression] instead. Counting only the first
/// would let `const FlipperOneClient()` through silently.
class _ClientReachVisitor extends RecursiveAstVisitor<void> {
  _ClientReachVisitor(this.unit);

  static const String _factory = 'FlipperOneClient';

  final CompilationUnit unit;
  final List<int> lines = [];

  void _record(int offset) =>
      lines.add(unit.lineInfo.getLocation(offset).lineNumber);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // A bare call, or one behind an import prefix. Unresolved, those are the
    // same shape as a method named `FlipperOneClient` on some object - which
    // would be a class name on an instance method, so the ambiguity is
    // theoretical and counting it is the safe way to be wrong.
    final target = node.target;
    if (node.methodName.name == _factory &&
        (target == null || target is SimpleIdentifier)) {
      _record(node.offset);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // `FlipperOneClient()` and `fl.FlipperOneClient()` both land here as the
    // type's own name; a prefixed import must not zero out a file.
    if (node.constructorName.type.name.lexeme == _factory) {
      _record(node.offset);
    }
    super.visitInstanceCreationExpression(node);
  }
}

/// The lines of the counted sites in [unit], in source order.
List<int> clientReachLines(CompilationUnit unit) {
  final visitor = _ClientReachVisitor(unit);
  unit.accept(visitor);
  return visitor.lines;
}

/// Parses [source] and counts, for the rule's own tests.
List<int> linesIn(String source) => clientReachLines(parseUnit(source));

void main() {
  group('the rule', () {
    test('counts the factory however it is written', () {
      expect(linesIn('void f() { FlipperOneClient().get(); }'), hasLength(1));
      expect(
        linesIn('void f() { final c = new FlipperOneClient(); }'),
        hasLength(1),
      );
      expect(
        linesIn('class A { final c = const FlipperOneClient(); }'),
        hasLength(1),
      );
      // A prefixed import would otherwise zero out the file that used it.
      expect(
        linesIn('void f() { fl.FlipperOneClient().get(); }'),
        hasLength(1),
      );
    });

    test('counts a stored client once, not once per use', () {
      expect(
        linesIn(
          'class A { final c = FlipperOneClient().get();'
          ' void f() { c.x(); } void g() { c.y(); } }',
        ),
        hasLength(1),
      );
    });

    test('is the factory, not anything that merely mentions it', () {
      expect(linesIn('void f() { other.FlipperOneClient; }'), isEmpty);
      expect(linesIn('void f() { FlipperTwoClient().get(); }'), isEmpty);
      expect(linesIn('void f() { log("FlipperOneClient()"); }'), isEmpty);
    });

    test('finds it wherever it is nested', () {
      expect(
        linesIn('void f() { h(onTap: () => FlipperOneClient().get()); }'),
        hasLength(1),
      );
      expect(
        linesIn('class A { void f() { if (x) { FlipperOneClient(); } } }'),
        hasLength(1),
      );
    });

    test('reports the line the site is on', () {
      expect(linesIn('void f() {\n  g();\n  FlipperOneClient().get();\n}'), [
        3,
      ]);
    });
  });

  test('no area reaches for the device client more than its budget', () {
    final result = countAcrossLib((unit, _) => clientReachLines(unit));

    expectWithinBudget(
      counted: result.counted,
      budget: kBudget,
      sites: result.sites,
      budgetFile: 'test/client_reach_budget_test.dart',
      why:
          'a class that calls FlipperOneClient() depends on the device without '
          'saying so in its signature, and cannot be built in a test without '
          'one.\n'
          'Take a FlipperClient as a constructor parameter instead, and let '
          'whoever builds this pass the one it already has.\n'
          'If it genuinely is a composition root, raise kBudget in '
          'test/client_reach_budget_test.dart and say why.\n'
          'See $kAdr',
    );
  });
}
