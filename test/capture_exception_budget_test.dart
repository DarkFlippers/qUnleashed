// A ceiling on `Sentry.captureException`, the call that decides whether a
// handled failure uploads a session replay.
//
// No ordinal, for the reason `picker_guard_test.dart` gives: the last several
// ratchets each claimed one and each was wrong, because nothing checks a
// number only a human reads.
//
// ADR 0013 §6 turns on a fact about the SDK: `ReplayEventProcessor` keys on an
// event with a non-empty `exceptions` list. It flushes the replay buffer on
// both platforms, and on iOS it also converts the session to a recorded one,
// so the rest of the run keeps uploading. Nothing downstream can decline -
// event processors run before `beforeSend`, so a filter there uploads the
// replay and then drops the event. #333 moved `_reportGuarded` off that call
// for exactly that reason, and the issue's own warning is why this file
// exists: "the next `guarded()` failure to fire on iOS re-opens the same
// behaviour, and nothing in CI will notice, because the symptom is replay
// quota in the Sentry console." A count is what notices.
//
// One is allowed, and it is `_reportUnknownConnect`: one issue per platform
// connect string the classifier has not learned, bounded by the number of
// distinct strings, and the one handled failure where seeing what the user did
// *is* the finding. A second site wants the same argument made in writing,
// which is what raising this number costs.
//
// **What it cannot see**, which ADR 0004 asks a new ratchet to state:
//
//  * A hub reached any way other than the `Sentry` facade - one held in a
//    field, `Hub.current`, an injected client. Nothing in the app holds one,
//    and `sentry_import_guard_test.dart` is what keeps the SDK's types out of
//    files where one could be held unnoticed.
//  * A feedback event, which `ReplayEventProcessor` also fires on. The app
//    sends none.
//  * The submodules. `countAcrossLib` lists `lib/` through `git ls-files`,
//    which does not descend into `lib/modules/flipperlib` or
//    `lib/modules/dartufbt` - neither of which depends on `sentry` at all.
//  * The count moving rather than rising: the budget is per area and
//    `areaOf` collapses all of `lib/services/`, so handing the one allowance
//    from `_reportUnknownConnect` to some other site keeps it at one.
//
// The last two blind spots and the `throwable:` shape below are covered by
// `guarded_replay_test.dart` instead, which asserts the shape of the event the
// `guarded` sink actually produces. The count is the cheap half of the pair,
// not the whole of it.
//
// Scope is `lib/` only. A `captureException` in `test/` uploads nothing from
// anyone's device - the dependency there ships in no binary and reaches no
// user, which is `sentry_import_guard_test.dart`'s argument for its own scope.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// What each area may send that carries an `exceptions` list.
///
/// `services` is 1: `Telemetry._reportUnknownConnect`. No other reporting path
/// sends an exception event at all - kept log lines become Sentry Logs,
/// breadcrumbs and HTTP exchanges become breadcrumbs, a known connect kind
/// becomes a metric, and the `guarded` sink sends an event with a message.
/// None of those carries an `exceptions` list.
///
/// An uncaught error is not counted here and cannot be: it reaches Sentry
/// through the SDK's own handlers, and a native crash through neither of them.
/// That is the other place a replay is wanted.
const Map<String, int> kBudget = {'services': 1};

const String kAdr = 'docs/adr/0013-observability-with-sentry.md';

/// Collects the two ways an event gets an `exceptions` list.
///
/// `Sentry.captureException(...)`, by whatever name the SDK was imported
/// under and through whatever the call hangs off - the target is not checked
/// at all, because nothing else in this app has a method by that name and a
/// class that grew one would be a deliberate choice worth a line here.
///
/// And `SentryEvent(throwable: ...)`, which is the one that reads like an
/// improvement: putting the type back in the issue header is one named
/// argument away from the code `_reportGuarded` now has, and `_prepareEvent`
/// builds the whole `exceptions` list out of it before any processor runs. So
/// `captureEvent` is not inherently safe, and a ratchet that counted only the
/// method name would have said it was.
class _CaptureVisitor extends RecursiveAstVisitor<void> {
  _CaptureVisitor(this.unit);

  final CompilationUnit unit;
  final List<int> lines = [];

  void _add(int offset) =>
      lines.add(unit.lineInfo.getLocation(offset).lineNumber);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'captureException') _add(node.offset);
    // `SentryEvent(...)` with no `new` parses as an invocation here, because
    // an unresolved AST cannot tell a constructor from a function - which is
    // also the form the code uses, so this is the arm that matters.
    if (node.methodName.name == 'SentryEvent' && _throws(node.argumentList)) {
      _add(node.offset);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'SentryEvent' &&
        _throws(node.argumentList)) {
      _add(node.offset);
    }
    super.visitInstanceCreationExpression(node);
  }

  /// Whether [arguments] hands the event a `throwable`.
  static bool _throws(ArgumentList arguments) =>
      namedArgument(arguments, 'throwable') != null;
}

/// The lines of the counted sites in [unit], in source order.
List<int> _captureLinesIn(CompilationUnit unit, String path) {
  final visitor = _CaptureVisitor(unit);
  unit.accept(visitor);
  return visitor.lines;
}

/// Parses [source] and counts, for the rule's own tests.
List<int> captureLines(String source) =>
    _captureLinesIn(parseUnit(source, path: 'lib/x.dart'), 'lib/x.dart');

void main() {
  group('the rule', () {
    test('counts a captureException call', () {
      expect(
        captureLines('void f() { Sentry.captureException(e); }'),
        hasLength(1),
      );
    });

    test('counts one reached through anything at all', () {
      // `Sentry.currentHub` and a prefixed import are both public API and both
      // sit inside the folder the import guard allows, so neither is a shape
      // this may miss.
      expect(
        captureLines('void f() { Sentry.currentHub.captureException(e); }'),
        hasLength(1),
      );
      expect(
        captureLines('void f() { sentry.Sentry.captureException(e); }'),
        hasLength(1),
      );
      expect(
        captureLines('void f() { _hub.captureException(e); }'),
        hasLength(1),
      );
    });

    test('counts a SentryEvent built with a throwable, new or not', () {
      // Which produces an exceptions list the SDK fills in, so it uploads a
      // replay exactly as `captureException` would.
      expect(
        captureLines(
          'void f() { Sentry.captureEvent(SentryEvent(message: m, '
          'throwable: e)); }',
        ),
        hasLength(1),
      );
      expect(
        captureLines(
          'void f() { Sentry.captureEvent(new SentryEvent(throwable: e)); }',
        ),
        hasLength(1),
      );
    });

    test('is not a message event, which is what the fix sends', () {
      expect(
        captureLines(
          'void f() { Sentry.captureEvent(SentryEvent(message: m), '
          'stackTrace: s); }',
        ),
        isEmpty,
      );
      expect(captureLines('void f() { Sentry.captureMessage("x"); }'), isEmpty);
    });

    test('is not another method whose name merely contains it', () {
      expect(captureLines('void f() { logCaptureExceptionCount(); }'), isEmpty);
    });

    test('reports the line the site is on', () {
      expect(captureLines('void f() {\n\n  Sentry.captureException(e);\n}'), [
        3,
      ]);
    });
  });

  test('no area sends more exception events than its budget', () {
    final found = countAcrossLib(_captureLinesIn);
    expectWithinBudget(
      counted: found.counted,
      budget: kBudget,
      sites: found.sites,
      budgetFile: 'test/capture_exception_budget_test.dart',
      why:
          'An event with an exceptions list flushes the session replay buffer, '
          'and on iOS keeps the session recording ($kAdr §6); no filter '
          'downstream can undo it. Send a handled failure as '
          'Sentry.captureEvent with a message and a stackTrace - frames and '
          'grouping survive, the replay does not. If this site really wants a '
          'replay, raise the number here and say why.',
    );
  });
}
