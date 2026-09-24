// A ratchet on asynchronous work started from `build` or `didUpdateWidget`.
//
// This is the rule ADR 0007 draws instead of a repository layer, and #136 is
// why. `FirmwareCard.didUpdateWidget` called `ensureDirectory` unconditionally
// while `DeviceScope` rebuilt on a five-second battery poll: twelve requests a
// minute, forever, against a server that was not answering. Nothing about the
// call was wrong except where it was written.
//
// Both methods run whenever the framework decides to, as often as it decides
// to, and neither is a place to start work that costs something. `initState`
// and a listener are, which is what #136 was fixed with - not a new layer.
//
// The two methods are held to different standards, because they are given
// different things to work with:
//
//  * `didUpdateWidget` gets the old widget, so it can ask whether the thing it
//    would fetch has actually changed. That guard is the whole difference
//    between the three sites in the tree today and the one that caused #136,
//    so it is the rule: a call guarded by a condition mentioning the old
//    widget is not counted at all. Budget zero, and it means zero.
//  * `build` gets no such thing. Whatever guards a site there guards it
//    against stored state this test cannot see, so every site is counted and
//    the budget carries the ones that exist.
//
// What it cannot see:
//
//  * Anything asynchronous declared in another file. The set of "starts async
//    work" is built per file, from declarations that are `async`/`async*` or
//    return a `Future`/`Stream` - so `_load()` next to its own declaration is
//    caught and `SomeService.load()` from three files away is not. Catching
//    that needs type resolution, which means analysing the whole app on every
//    run rather than parsing it.
//  * A getter. `widget.thing.pending` may well be a `Future`, and a property
//    access is not an invocation.
//  * Work started from a closure - a callback, a builder, an `onTap`. Those
//    run on an event, not on every rebuild, which is the whole point, so
//    closures are stepped over deliberately.
//  * A guard on `didUpdateWidget` that is correct without naming the old
//    widget - comparing against a stored field, say. It would be counted.
//    None exists today; the answer if one arrives is to say so here.
//
// And one that makes it a proxy rather than a measure: moving the call into a
// private method that `build` calls is still a call from `build`, but moving
// it behind a getter is not, and neither changes what happens at runtime.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// What each area held when the ratchet went in.
///
/// Every entry is a `build`. `didUpdateWidget` is at zero across the whole
/// tree and is expected to stay there - the three sites that exist are each
/// guarded against the old widget, which is what the rule asks for, so they do
/// not appear here.
const Map<String, int> kBudget = {
  // `icon.dart` asks a raster cache to resolve an icon from `build`, guarded
  // by a key comparison against the last one it resolved. The guard is real;
  // it is just not one this test can read. Rendering an icon is also the one
  // job the widget has, which is what makes it different from #136 - there is
  // no other place the work could be started from.
  'components': 1,
};

const String kAdr =
    'https://github.com/DarkFlippers/qUnleashed/blob/main/docs/adr/'
    '0007-no-repository-layer.md';

/// Names declared in one file that start asynchronous work.
///
/// Per file and syntactic on purpose: see the header for what that misses and
/// why resolving it properly is not worth a whole-app analysis on every run.
class _AsyncDeclarations extends RecursiveAstVisitor<void> {
  final Set<String> names = {};

  void _take(String name, TypeAnnotation? returnType, FunctionBody body) {
    final declared = returnType?.toSource() ?? '';
    if (body.isAsynchronous ||
        declared.startsWith('Future') ||
        declared.startsWith('Stream')) {
      names.add(name);
    }
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _take(node.name.lexeme, node.returnType, node.body);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _take(node.name.lexeme, node.returnType, node.functionExpression.body);
    super.visitFunctionDeclaration(node);
  }
}

/// Collects async work started from a widget's `build` or `didUpdateWidget`.
class _RebuildWorkVisitor extends RecursiveAstVisitor<void> {
  _RebuildWorkVisitor(this.unit, this.asyncNames);

  final CompilationUnit unit;
  final Set<String> asyncNames;
  final List<int> lines = [];

  /// The method being walked, or null outside one.
  MethodDeclaration? _method;

  /// The old-widget parameter, when inside `didUpdateWidget`.
  String? _oldWidget;

  /// Depth of function literals, so a callback's body is not the rebuild path.
  int _closure = 0;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    // `Widget build(BuildContext)` and nothing else called build: the app has
    // several `Future<...> build(...)` methods that assemble firmware, and
    // those are not widgets rebuilding.
    final isWidgetBuild =
        name == 'build' &&
        (node.returnType?.toSource() ?? '').endsWith('Widget');
    if (!isWidgetBuild && name != 'didUpdateWidget') {
      super.visitMethodDeclaration(node);
      return;
    }

    _method = node;
    _closure = 0;
    _oldWidget = name == 'didUpdateWidget'
        ? node.parameters?.parameters.firstOrNull?.name?.lexeme
        : null;
    super.visitMethodDeclaration(node);
    _method = null;
    _oldWidget = null;
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    _closure += 1;
    super.visitFunctionExpression(node);
    _closure -= 1;
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    // `build` cannot be async, so this is `didUpdateWidget` - and an await
    // there is the same work with the rebuild blocked on it.
    if (_method != null && _closure == 0 && !_isGuarded(node)) {
      lines.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    super.visitAwaitExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (_method != null &&
        _closure == 0 &&
        (asyncNames.contains(name) || name == 'unawaited') &&
        !_isGuarded(node)) {
      lines.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    super.visitMethodInvocation(node);
  }

  /// Whether [node] sits under a condition that mentions the old widget.
  ///
  /// Only in `didUpdateWidget`; `build` has no old widget, so nothing there is
  /// ever excused. The walk stops at the method so a guard in an enclosing
  /// method cannot excuse anything.
  bool _isGuarded(AstNode node) {
    final parameter = _oldWidget;
    if (parameter == null) return false;
    for (AstNode? at = node; at != null && at != _method; at = at.parent) {
      final condition = switch (at.parent) {
        final IfStatement s when s.expression != at => s.expression,
        final ConditionalExpression e when e.condition != at => e.condition,
        _ => null,
      };
      if (condition != null && _mentions(condition, parameter)) return true;
    }
    return false;
  }

  static bool _mentions(Expression condition, String parameter) {
    final found = _IdentifierSearch(parameter);
    condition.accept(found);
    return found.hit;
  }
}

class _IdentifierSearch extends RecursiveAstVisitor<void> {
  _IdentifierSearch(this.wanted);

  final String wanted;
  bool hit = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == wanted) hit = true;
    super.visitSimpleIdentifier(node);
  }
}

/// The lines of the counted sites in [unit], in source order.
List<int> rebuildWorkLines(CompilationUnit unit) {
  final declarations = _AsyncDeclarations();
  unit.accept(declarations);
  final visitor = _RebuildWorkVisitor(unit, declarations.names);
  unit.accept(visitor);
  return visitor.lines;
}

/// Parses [source] and counts, for the rule's own tests.
List<int> linesIn(String source) => rebuildWorkLines(parseUnit(source));

/// A `State` subclass wrapping [body], since the rule only looks at methods.
String state(String body) => 'class S extends State<W> { $body }';

void main() {
  group('what counts as starting work', () {
    test('is a call to something async declared in the same file', () {
      expect(
        linesIn(
          state(
            'Future<void> _load() async {} '
            'Widget build(BuildContext c) { _load(); return X(); }',
          ),
        ),
        hasLength(1),
      );
      expect(
        linesIn(
          state(
            'void _paint() {} '
            'Widget build(BuildContext c) { _paint(); return X(); }',
          ),
        ),
        isEmpty,
        reason: 'a synchronous helper is not what this is about',
      );
    });

    test('is async by body as well as by return type', () {
      expect(
        linesIn(
          state(
            'void _fire() async {} '
            'Widget build(BuildContext c) { _fire(); return X(); }',
          ),
        ),
        hasLength(1),
        reason: 'a fire-and-forget async void is the worst version of this',
      );
      expect(
        linesIn(
          state(
            'Stream<int> _watch() async* {} '
            'Widget build(BuildContext c) { _watch(); return X(); }',
          ),
        ),
        hasLength(1),
      );
    });

    test('is unawaited(), whatever it wraps', () {
      expect(
        linesIn(state('Widget build(BuildContext c) { unawaited(g()); }')),
        hasLength(1),
      );
    });

    test('is not a call to something declared elsewhere', () {
      expect(
        linesIn(state('Widget build(BuildContext c) { Service.load(); }')),
        isEmpty,
        reason: 'the documented blind spot - it needs type resolution',
      );
    });
  });

  group('where it counts', () {
    test('is a widget build, not every method called build', () {
      expect(
        linesIn(
          'class R { Future<void> _step() async {} '
          'Future<void> build() async { _step(); } }',
        ),
        isEmpty,
        reason: 'app_build_router and remote_build_service both have one',
      );
      expect(
        linesIn(
          state(
            'Future<void> _step() async {} '
            'Widget build(BuildContext c) { _step(); return X(); }',
          ),
        ),
        hasLength(1),
      );
    });

    test('is not initState, which is where this work belongs', () {
      expect(
        linesIn(
          state('Future<void> _load() async {} void initState() { _load(); }'),
        ),
        isEmpty,
      );
    });

    test('is not inside a closure, which runs on an event', () {
      expect(
        linesIn(
          state(
            'Future<void> _load() async {} '
            'Widget build(BuildContext c) => B(onTap: () => _load());',
          ),
        ),
        isEmpty,
      );
      expect(
        linesIn(
          state(
            'Future<void> _load() async {} '
            'Widget build(BuildContext c) { _load(); '
            'return B(onTap: () => _load()); }',
          ),
        ),
        hasLength(1),
        reason: 'the direct call still counts; the callback does not',
      );
    });

    test('resumes counting after a closure has closed', () {
      // Pins that the depth counter comes back down.
      expect(
        linesIn(
          state(
            'Future<void> _load() async {} '
            'Widget build(BuildContext c) { B(onTap: () => _load()); '
            '_load(); return X(); }',
          ),
        ),
        hasLength(1),
      );
    });
  });

  group('the guard on didUpdateWidget', () {
    const decl = 'Future<void> _load() async {} ';

    test('excuses a call under a condition that reads the old widget', () {
      expect(
        linesIn(
          state(
            '${decl}void didUpdateWidget(W old) { '
            'if (old.url != widget.url) _load(); }',
          ),
        ),
        isEmpty,
      );
      expect(
        linesIn(
          state(
            '${decl}void didUpdateWidget(W oldWidget) { '
            'if (widget.active && !oldWidget.active) { _load(); } }',
          ),
        ),
        isEmpty,
        reason: 'the shape flipper_screen_animation.dart actually has',
      );
      expect(
        linesIn(
          state(
            '${decl}void didUpdateWidget(W old) { '
            'old.alias != widget.alias ? _load() : null; }',
          ),
        ),
        isEmpty,
        reason: 'a conditional expression guards as well as an if does',
      );
    });

    test('does not excuse an unguarded call - the shape that caused #136', () {
      expect(
        linesIn(state('${decl}void didUpdateWidget(W old) { _load(); }')),
        hasLength(1),
      );
    });

    test('does not excuse a condition that never looks at the old widget', () {
      expect(
        linesIn(
          state(
            '${decl}void didUpdateWidget(W old) { '
            'if (widget.enabled) _load(); }',
          ),
        ),
        hasLength(1),
        reason: 'true on every rebuild is the same as no guard at all',
      );
    });

    test('does not excuse the condition calling it itself', () {
      expect(
        linesIn(
          state(
            '${decl}Future<bool> _stale(W o) async => true; '
            'void didUpdateWidget(W old) { if (_stale(old)) _load(); }',
          ),
        ),
        hasLength(1),
        reason: 'the work in the condition runs on every rebuild',
      );
    });

    test('has no counterpart in build, which gets no old widget', () {
      expect(
        linesIn(
          state(
            '${decl}Widget build(BuildContext c) { '
            'if (old.url != widget.url) _load(); return X(); }',
          ),
        ),
        hasLength(1),
      );
    });

    test('is the enclosing condition, not one in the method above', () {
      expect(
        linesIn(
          state(
            '${decl}void f(W old) { if (old.x) g(); } '
            'void didUpdateWidget(W old) { _load(); }',
          ),
        ),
        hasLength(1),
      );
    });

    test('counts an await the same way it counts a call', () {
      expect(
        linesIn(
          'class S extends State<W> { void didUpdateWidget(W old) async '
          '{ await g(); } }',
        ),
        hasLength(1),
      );
      expect(
        linesIn(
          'class S extends State<W> { void didUpdateWidget(W old) async '
          '{ if (old.x != widget.x) await g(); } }',
        ),
        isEmpty,
      );
    });
  });

  test('no area starts work on rebuild more than its budget', () {
    final result = countAcrossLib((unit, _) => rebuildWorkLines(unit));

    expectWithinBudget(
      counted: result.counted,
      budget: kBudget,
      sites: result.sites,
      budgetFile: 'test/build_io_budget_test.dart',
      why:
          'build and didUpdateWidget run whenever the framework decides to, '
          'as often as it decides to. #136 was twelve requests a minute '
          'forever, from one unguarded call in didUpdateWidget.\n'
          'Start the work in initState, or from a listener, and in '
          'didUpdateWidget guard it on the old widget actually having '
          'changed.\n'
          'See $kAdr',
    );
  });
}
