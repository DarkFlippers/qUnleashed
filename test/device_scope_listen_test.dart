// Two rules about reading `DeviceScope`: nothing subscribes for the client,
// and the sites that do subscribe are counted.
//
// `DeviceScope.of` is a listening read. It was also the only one the scope
// offered, so every reader of it got a subscription whether it had any use for
// one or not - and 30 of the 39 sites in `lib/` wanted nothing but `.client`,
// which cannot change. `DeviceController._client` is `final`, and the
// controller is `late final` in `_QUnleashedAppState`, the one state that
// builds a `DeviceScope`. One object, for the run.
//
// The notifier is not quiet. `services/connection/device_info_watch.dart`
// polls on a five-second interval, and the controller merges any non-empty
// patch and notifies without comparing it - so a connected idle Flipper
// rebuilt every dependent up to twelve times a minute. Thirteen of those
// reads were in a `build`, and twelve of the thirteen put the dependency on
// the page's own element and took the page body with it:
// `about/license_page.dart` rebuilt the whole LICENSE page that often for
// content that never changes. The thirteenth sat inside an `AnimatedBuilder`
// that wrapped only the app bar, so it dragged the bar and not the body -
// which is the per-page fix #339 had already applied there.
//
// **A read from a callback is not the cheaper half of this.** #344 guessed
// that the reads in callbacks and route builders "register a dependency that
// lasts until the element's next rebuild", and that is wrong: in
// `widgets/framework.dart` the only things that touch `Element._dependencies`
// are `activate` (which clears it on reuse), `_ensureDeactivated`, `unmount`
// and the two accessors. Nothing clears it on a rebuild. So a listening read
// from a gesture callback is a *standing* dependency for the element's life,
// and `widgets/firmware_card.dart`'s changelog push - the one site that
// reached the client through a local, and so the one the first sweep missed -
// subscribed the device screen's heaviest card to the poll from the first tap
// until the screen went away.
//
// It has cost a crash and not only cycles. In #339 that standing subscription
// was destroying a live text selection in the app detail page's changelog, and
// a selection handle dragged across one of the rebuilds crashed inside
// Flutter's gesture handling, where nothing on the page could catch it
// (QUNLEASHED-F). That was fixed per-page, by moving the read into a child
// widget. #344 is the same defect at the accessor instead, and ADR 0011's
// addendum is the decision.
//
// So `clientOf` exists, and these two rules keep the split:
//
//  * **A guard, budget zero**: no listening read whose only use is `.client`.
//  * **A census, budget nine**: every listening read, per area. Four of the
//    nine left read live state in a `build` and want the dependency; five are
//    callbacks that want the controller and not a subscription, and have no
//    accessor for that yet. The budget below says which each one is, and
//    adding a tenth means editing it and saying so.
//
// The census is what makes the guard hard to walk around. A reader that takes
// the controller into a local and only ever asks it for `.client` satisfies
// the guard - resolving that is dataflow, and these ratchets parse without
// resolving (ADR 0004) - but it still raises the census, and the census
// failure names the file. That is not hypothetical: it is how the
// `firmware_card.dart` site above was found, by a review reading the census
// budget's own justification for it and noticing the justification was false.
//
// What neither rule can see:
//
//  * **A read behind a helper.** `DeviceController deviceOf(BuildContext c) =>
//    DeviceScope.of(c);` is one counted site, and every caller of it gets a
//    real dependency while contributing nothing to either number.
//  * **A typedef.** `typedef Scope = DeviceScope; Scope.of(context).client`
//    gives the target a different name, and [isCallOnClass] compares names.
//  * A client passed down from a counted site. Counted where it is read;
//    invisible below that, which is also the shape ADR 0002 wants.
//  * A `clientOf` read that should have been an `of` read. That direction is
//    staleness rather than churn, and the signature is what prevents it:
//    `clientOf` returns the client, so there is no `info` or `isConnected` on
//    the other end of it to read stale. ADR 0011's addendum says why that is
//    the accessor's return type and not a comment.
//  * `test/`. Only `lib/` is walked, so a fixture may listen however it likes.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// Where a listening read of the scope is still the right call, per area.
///
/// Each entry says what the reads are for, because a number cannot. Someone
/// editing this map to get CI green reads the line they are changing - which
/// is the mechanism that caught the `firmware_card.dart` site, so the wording
/// here is load-bearing and not decoration.
const Map<String, int> kBudget = {
  // `app/shell.dart` picks the tab layout from `connectionState`, in its
  // `build`. One read - and the one place a third accessor would pay, since
  // the dependency it registers makes the `ListenableBuilder` below it narrow
  // nothing. ADR 0011's addendum.
  'app': 1,
  // The device screen is what the poll is *for*, and these eight are not all
  // the same kind of read.
  //
  // Three want the dependency: `page.dart`'s two `build` reads (the info table
  // and the connection state) and `widgets/firmware_update_button.dart`'s
  // `dfuPresent`, also in a `build`.
  //
  // Five are callbacks, where the dependency is standing and useless but
  // there is no accessor that hands over the controller without one -
  // `_onRefresh` (`synchronize()`), `_playAlert`, `_exportDeviceInfo`
  // (`buildExportDump()`), `firmware_update_button`'s DFU-only branch
  // (`setRecovering`), and `_openFullInfo`, which reads `info` once to
  // populate a sheet. They are the argument for `notifierOf` and they stay
  // counted here until it exists.
  //
  // Was 9. `widgets/firmware_card.dart`'s changelog push was counted here
  // under the claim that it "hands the live controller to the changelog
  // route", and it handed `device.client` - a client-only read reaching the
  // client through a local, which is the one shape the guard cannot see. A
  // review found it by reading this comment and checking it. It is `clientOf`
  // now, which is why the number is 8, and why the wording here is
  // load-bearing rather than decoration.
  'pages/devices': 8,
};

/// The name of the scope, spelt once.
const kScope = 'DeviceScope';

/// The file that owns the accessors, and so the one file allowed to subscribe
/// directly.
const kScopeFile = 'lib/pages/devices/device_scope.dart';

/// Whether [node] is `context.dependOnInheritedWidgetOfExactType<DeviceScope>`.
///
/// Counted as well as `DeviceScope.of`, so that the rules are about
/// subscribing to the scope rather than about one spelling of it. Without
/// this, the whole census is bypassed by the line the accessor itself is made
/// of.
///
/// **A bare call with no type arguments counts too**, whatever scope it is
/// really for. Dart infers the type argument from the assignment context, so
/// `final DeviceScope? s = context.dependOnInheritedWidgetOfExactType();`
/// leaves `typeArguments` null - and a rule that read only the explicit form
/// was bypassed in one line with no new import, by the very shape this
/// predicate exists to catch. Resolving the inference is beyond a parse, so
/// the honest rule is that an unspelt type argument fails and names the file.
/// There are none in `lib/` today; all six sites spell theirs.
bool _isDirectDependOn(MethodInvocation node) {
  if (node.methodName.name != 'dependOnInheritedWidgetOfExactType') {
    return false;
  }
  final arguments = node.typeArguments?.arguments;
  if (arguments == null) return true;
  return arguments.any(
    (type) => type is NamedType && type.name.lexeme == kScope,
  );
}

/// Whether [node] is the scope's listening accessor, however it was imported.
bool _isListeningRead(MethodInvocation node) =>
    node.methodName.name == 'of' && isCallOnClass(node, kScope);

/// Every listening read in a unit, and which of them want only `.client`.
///
/// One visit for both rules: the second list is a subset of the first, and the
/// question they ask is about the same nodes.
class _ScopeReadVisitor extends RecursiveAstVisitor<void> {
  _ScopeReadVisitor(this.unit);

  final CompilationUnit unit;

  final List<int> listening = [];
  final List<int> clientOnly = [];

  int _lineOf(int offset) => unit.lineInfo.getLocation(offset).lineNumber;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_isListeningRead(node) || _isDirectDependOn(node)) {
      listening.add(_lineOf(node.offset));
      if (_wantsOnlyClient(node)) clientOnly.add(_lineOf(node.offset));
    }
    super.visitMethodInvocation(node);
  }

  /// Whether the read is immediately asked for `.client` and nothing else.
  ///
  /// `DeviceScope.of(context).client` parses as a [PropertyAccess] over the
  /// invocation, so the parent is the whole question. A null-aware access is
  /// the same read - `of` cannot return null, but a reader that wrote `?.` is
  /// making the same mistake and should get the same message.
  bool _wantsOnlyClient(MethodInvocation node) {
    final parent = node.parent;
    return parent is PropertyAccess && parent.propertyName.name == 'client';
  }
}

/// The listening reads in [unit], split into every one and the client-only
/// ones.
({List<int> listening, List<int> clientOnly}) scopeReadsIn(
  CompilationUnit unit,
) {
  final visitor = _ScopeReadVisitor(unit);
  unit.visitChildren(visitor);
  return (listening: visitor.listening, clientOnly: visitor.clientOnly);
}

/// The client-only reads in [path], tallying *every* listening read into
/// [tally] on the way past.
///
/// Top-level, taking the tally as a parameter, rather than a closure inside
/// `setUpAll`. The guard's budget is empty, and a rule that counts zero over
/// real `lib/` can have no vacuity check of its own - so while this lived in
/// the closure, replacing its result with `const []` left the guard counting
/// nothing forever and **all eleven cases still passed**. The nine cases below
/// exercised the visitor and never the wiring that feeds it to
/// [countAcrossLib]. Out here, both halves - the subset that is returned and
/// the exemption that short-circuits it - are reachable from a case.
List<int> scopeReadsFor(CompilationUnit unit, String path, AreaTally tally) {
  // The accessor's own `dependOnInheritedWidgetOfExactType` is the one
  // subscription that is not a page's, and it is the whole point of the file.
  // Exempt from both rules rather than one, so the exemption cannot mean two
  // things.
  if (isExempt(path, const {kScopeFile})) return const <int>[];

  final found = scopeReadsIn(unit);
  tally.add(path, found.listening);
  return found.clientOnly;
}

void main() {
  // One walk for both rules. `countAcrossLib` runs `git ls-files` and parses
  // every file under `lib/`, and both numbers fall out of the same visit.
  late AreaTally listening;
  late ({Map<String, int> counted, Map<String, List<String>> sites}) clientOnly;

  setUpAll(() {
    final tally = AreaTally();
    clientOnly = countAcrossLib(
      (unit, path) => scopeReadsFor(unit, path, tally),
    );
    listening = tally;
  });

  test('nothing subscribes to the scope just to get the client', () {
    expectWithinBudget(
      counted: clientOnly.counted,
      budget: const <String, int>{},
      sites: clientOnly.sites,
      budgetFile: 'test/device_scope_listen_test.dart',
      why:
          'DeviceScope.of registers a dependency, and the client it hands '
          'back cannot change - DeviceController._client is final and the '
          'controller is late final in the one state that builds a scope. So '
          'the reader rebuilds on every device-info poll, twelve times a '
          'minute with a Flipper connected, for a value that is the same '
          'object every time. Nothing clears a dependency on a rebuild, so '
          'this is standing wherever it is read, not only in a build; in #339 '
          'it was a crash. Call DeviceScope.clientOf(context) instead - it '
          'reads the same widget without depending on it. ADR 0011.',
    );
  });

  test('and the sites that do subscribe are the ones that read live state', () {
    // The vacuity guard, in the two forms that cannot go stale. A checked-in
    // exact count can: `ratchet.dart` argues against one in so many words, and
    // the first draft of this case asserted `greaterThanOrEqualTo(10)` - so
    // converting the `firmware_card.dart` site, a strict improvement, failed
    // here with a message claiming the walk had found nothing. Shrinkage is
    // reported by `expectWithinBudget` as a nag, which is this repo's
    // deliberate asymmetry.
    expect(
      listening.total,
      greaterThan(0),
      reason: 'a walk that counts nothing passes every budget',
    );
    for (final area in kBudget.keys) {
      expect(
        listening.counted[area],
        isNotNull,
        reason:
            'no listening read found in $area at all - either the budget '
            'entry is stale and should go, or the walk stopped seeing it',
      );
    }
    expectWithinBudget(
      counted: listening.counted,
      budget: kBudget,
      sites: listening.sites,
      budgetFile: 'test/device_scope_listen_test.dart',
      why:
          'A new DeviceScope.of read subscribes its whole element to a '
          'notifier that fires every five seconds while a Flipper is '
          'connected, and it keeps that subscription until the element goes - '
          'a rebuild does not clear it. That is right for a reader of '
          'isConnected, info, dfuPresent or connectionState, and wrong for '
          'anything else - use DeviceScope.clientOf for the client. If the '
          'read really does want live state, raise the number above and say '
          'what it reads.',
    );
  });

  group('what counts as a listening read', () {
    ({List<int> listening, List<int> clientOnly}) found(String source) =>
        scopeReadsIn(parseUnit(source));

    test('the shape that this change removed', () {
      final reads = found('''
        Widget build(BuildContext context) =>
            QPageAppBar(client: DeviceScope.of(context).client);
      ''');
      expect(reads.listening, [2]);
      expect(reads.clientOnly, [2]);
    });

    test('the accessor that replaced it is not a read at all', () {
      final reads = found('''
        Widget build(BuildContext context) =>
            QPageAppBar(client: DeviceScope.clientOf(context));
      ''');
      expect(reads.listening, isEmpty);
      expect(reads.clientOnly, isEmpty);
    });

    test('a live-state read is counted, and is not client-only', () {
      final reads = found('''
        void f(BuildContext context) {
          if (DeviceScope.of(context).isConnected) return;
        }
      ''');
      expect(reads.listening, [2]);
      expect(
        reads.clientOnly,
        isEmpty,
        reason: 'this one has a reason to subscribe',
      );
    });

    test('a prefixed import, which a bare name check would miss', () {
      final reads = found('''
        void f(BuildContext context) {
          final c = scope.DeviceScope.of(context).client;
        }
      ''');
      expect(reads.listening, [2]);
      expect(reads.clientOnly, [2]);
    });

    test('the raw subscription the accessor is made of', () {
      final reads = found('''
        void f(BuildContext context) {
          context.dependOnInheritedWidgetOfExactType<DeviceScope>();
        }
      ''');
      expect(reads.listening, [
        2,
      ], reason: 'or the census is bypassed by one import of framework.dart');
    });

    test('and the same with the type argument left to inference', () {
      final reads = found('''
        void f(BuildContext context) {
          final DeviceScope? s = context.dependOnInheritedWidgetOfExactType();
        }
      ''');
      expect(
        reads.listening,
        [2],
        reason:
            'typeArguments is null here, so a rule reading only the explicit '
            'form is bypassed in one line - it counts, and the site spells '
            'the type or says why',
      );
    });

    test('the non-listening raw read is not one', () {
      final reads = found('''
        void f(BuildContext context) {
          context.getInheritedWidgetOfExactType<DeviceScope>();
        }
      ''');
      expect(reads.listening, isEmpty);
    });

    test('a subscription to some other scope is not this rule', () {
      final reads = found('''
        void f(BuildContext context) {
          context.dependOnInheritedWidgetOfExactType<PermissionScope>();
          PermissionScope.of(context).client;
        }
      ''');
      expect(reads.listening, isEmpty);
      expect(reads.clientOnly, isEmpty);
    });

    test(
      'a read taken into a local is invisible, which the census catches',
      () {
        final reads = found('''
        void f(BuildContext context) {
          final device = DeviceScope.of(context);
          g(device.client);
        }
      ''');
        expect(
          reads.clientOnly,
          isEmpty,
          reason: 'the guard cannot see this - resolving it is dataflow',
        );
        expect(
          reads.listening,
          [2],
          reason:
              'and this is the shape the census found in firmware_card.dart',
        );
      },
    );

    test('not a comment, and not another method on the scope', () {
      final reads = found('''
        // DeviceScope.of(context).client
        void f(BuildContext context) {
          DeviceScope.maybeOf(context);
        }
      ''');
      expect(reads.listening, isEmpty);
      expect(reads.clientOnly, isEmpty);
    });
  });

  group('what the walk is handed', () {
    const source = '''
      Widget build(BuildContext context) =>
          QPageAppBar(client: DeviceScope.of(context).client);
    ''';

    test('a page contributes to the guard and to the census', () {
      final tally = AreaTally();
      final lines = scopeReadsFor(
        parseUnit(source),
        'lib/pages/about/license_page.dart',
        tally,
      );
      expect(lines, [2], reason: 'the guard is fed the client-only subset');
      expect(tally.counted, {'pages/about': 1});
      expect(tally.sites, {
        'pages/about': ['lib/pages/about/license_page.dart:2'],
      });
    });

    test('and the scope file contributes to neither', () {
      final tally = AreaTally();
      final lines = scopeReadsFor(parseUnit(source), kScopeFile, tally);
      expect(lines, isEmpty);
      expect(
        tally.counted,
        isEmpty,
        reason: 'the exemption covers both rules, not just the guard',
      );
    });
  });
}
