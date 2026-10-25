// Four rules about reading `DeviceScope`, one accessor at a time: nothing
// subscribes for a value that cannot change, nothing reads live state off a
// read that cannot see it change, and both sets of exceptions are counted.
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
// So there are three accessors, and `lib/` splits 30 / 6 / 3 across them:
// `clientOf` (no dependency, hands back the client), `notifierOf` (no
// dependency, hands back the controller) and `of` (the listening read).
//
// Each non-listening accessor gets a guard and a census, because each one
// trades a rebuild for a thing that can go wrong quietly:
//
//  * **`clientOf`, guard at zero**: no listening read whose only use is
//    `.client`. The client cannot change, so the subscription is pure cost.
//  * **`of`, census at three**: every listening read, per area. Three left,
//    all of them reading live state in a `build`, which is what the
//    subscription is for.
//  * **`notifierOf`, guard at zero**: no live state read off its result.
//    It is the accessor with no type to hide behind - `clientOf`'s return
//    type at least keeps `info`, `dfuPresent`, `connectionState` and
//    `deviceLoading` out of reach (not `isConnected`, which is on the client
//    too) - and this hands back the controller, so reading `info` off it in a
//    `build` is a value frozen at whenever something else last rebuilt the
//    reader.
//  * **`notifierOf`, census at six**: every call, per area, so each one is
//    declared and says what it does with the controller.
//
// **A census is what makes a guard hard to walk around**, and that is not
// hypothetical. A reader that takes the controller into a local and only ever
// asks it for `.client` satisfies the `clientOf` guard - resolving that is
// dataflow, and these ratchets parse without resolving (ADR 0004) - but it
// still raises the `of` census. That is exactly how `firmware_card.dart`'s
// changelog push was found: by a review reading the census budget's own
// justification for the site and noticing the justification was false. The
// same hole is in the `notifierOf` guard, and `pages/devices/page.dart`'s
// `_openFullInfo` sits in it - it reads `info` through a local, so the guard
// cannot see it either way. What covers that site is its budget line saying
// it reads once into a pushed sheet, not the guard.
//
// What none of the rules can see:
//
//  * **A read behind a helper.** `DeviceController deviceOf(BuildContext c) =>
//    DeviceScope.of(c);` is one counted site, and every caller of it gets a
//    real dependency while contributing nothing to either number.
//  * **A typedef.** `typedef Scope = DeviceScope; Scope.of(context).client`
//    gives the target a different name, and [isCallOnClass] compares names.
//  * A client passed down from a counted site. Counted where it is read;
//    invisible below that, which is also the shape ADR 0002 wants.
//  * A `clientOf` read that should have been an `of` read. That direction is
//    staleness rather than churn, and the return type is what narrows it:
//    `info`, `dfuPresent`, `connectionState` and `deviceLoading` are not on a
//    client. It does not close the door - `FlipperClient` has its own
//    `isConnected` and `deviceInfoCache` - and ADR 0011's addendum says so
//    rather than claiming the type settles it.
//  * `test/`. Only `lib/` is walked, so a fixture may listen however it likes.
import 'dart:io';

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
const Map<String, int> kListeningBudget = {
  // The device screen is what the poll is *for*. Three reads, all in a
  // `build`, all of them wanting every notification the poll produces:
  // `page.dart`'s info table and its connection state, and
  // `widgets/firmware_update_button.dart`'s `dfuPresent`.
  //
  // Was 9. `widgets/firmware_card.dart`'s changelog push was counted here
  // under the claim that it "hands the live controller to the changelog
  // route", and it handed `device.client` - a client-only read reaching the
  // client through a local, which is the one shape the guard cannot see. A
  // review found it by reading this comment and checking it (#344). Then five
  // more left for `notifierOf`, which is #407 and the budget below.
  //
  // `app` has no entry any more: `shell.dart`'s read was the sixth to go.
  'pages/devices': 3,
};

/// Where the controller is taken without a dependency, per area.
///
/// Every entry says what the site does with the controller, because the whole
/// safety of `notifierOf` is that somebody wrote that down. There is no type
/// stopping the next one reading `info` off it in a `build`.
const Map<String, int> kNotifierBudget = {
  // `shell.dart` hands the controller to a `ListenableBuilder` and reads
  // state off it **only inside that builder**, where the subscription lives:
  // `_deviceLabel` reads `connectionState`, `device`, `deviceLoading` and
  // `deviceInfoConnected`, and the builder re-runs on every notification, so
  // none of them goes stale. What must not happen is a read in
  // `_AppShellState.build` itself - that is the shape this entry exists to
  // keep out, and it is why the budget is 1 and not 0. #407.
  'app': 1,
  // Four callbacks calling a method - `_onRefresh` (`synchronize()`),
  // `_playAlert`, `_exportDeviceInfo` (`buildExportDump()`) and
  // `firmware_update_button`'s DFU-only branch (`setRecovering`) - plus
  // `_openFullInfo`, which takes **one snapshot** of `deviceInfoEntries` and
  // `info` to fill a sheet that is then pushed and static.
  //
  // That fifth one is the awkward case, and the only reason this comment
  // matters rather than decorating: the guard below cannot see it, because it
  // reads through a local, and **nothing executes it either**. Its
  // `onOpenFullInfo` is wired only when `ctrl.isConnected`, and
  // `FakeFlipperClient.connectedDevice` returns null on purpose - a non-null
  // one would put `DeviceController` into `_ensureDataLoading`, which reaches
  // for a `deviceInfoUpdates` the fake does not answer. So a fixture that
  // could open the sheet does not exist yet, and this line is the whole of
  // the site's cover. If the sheet ever stops being a snapshot, it wants
  // `DeviceScope.of` and a test that drives it.
  'pages/devices': 5,
};

/// The name of the scope, spelt once.
const kScope = 'DeviceScope';

/// The non-listening accessor that hands back the whole controller.
const kNotifierRead = 'notifierOf';

/// What `DeviceController` exposes as state rather than as an action.
///
/// Read off a [DeviceScope.notifierOf] result, every one of these is a value
/// frozen at whenever something else last rebuilt the reader. `client` is in
/// the set because `clientOf` is the accessor for it, and taking it off the
/// controller is a longer way round that also gives the next editor the
/// controller to misuse.
///
/// The actions are deliberately absent, and they are the point of the
/// accessor: `synchronize`, `playAlert`, `buildExportDump`, `setRecovering`,
/// `reboot`. They are [MethodInvocation]s rather than property accesses, so
/// the visitor would not see them anyway - this set is what makes the
/// distinction a rule rather than a coincidence of syntax.
const Set<String> kControllerState = {
  'client',
  'device',
  'deviceLoading',
  'deviceInfoConnected',
  'alertPlaying',
  'dfuPresent',
  'recovering',
  'info',
  'isConnected',
  'connectionState',
  'firmwareVersion',
  'buildDate',
  'deviceName',
  'deviceInfoEntries',
};

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

/// Whether [node] is the scope's non-listening controller accessor.
bool _isNotifierRead(MethodInvocation node) =>
    node.methodName.name == kNotifierRead && isCallOnClass(node, kScope);

/// The property this read is immediately asked for, if it is asked for one.
///
/// `DeviceScope.of(context).client` parses as a [PropertyAccess] over the
/// invocation, so the parent is the whole question. A null-aware access is the
/// same read - neither accessor can return null, but a reader that wrote `?.`
/// is making the same mistake and should get the same message. A method call
/// on the result is a [MethodInvocation] parent instead and yields null here,
/// which is what separates `notifierOf(c).synchronize()` from
/// `notifierOf(c).info`.
String? _propertyRead(MethodInvocation node) {
  final parent = node.parent;
  return parent is PropertyAccess ? parent.propertyName.name : null;
}

/// Every scope read in a unit, in the four lists the rules need.
///
/// One visit for all of them: they ask different questions about the same
/// nodes, and `countAcrossLib` is ~400 ms a walk.
class _ScopeReadVisitor extends RecursiveAstVisitor<void> {
  _ScopeReadVisitor(this.unit);

  final CompilationUnit unit;

  /// Every listening read.
  final List<int> listening = [];

  /// The listening reads whose only use is `.client`.
  final List<int> clientOnly = [];

  /// Every `notifierOf` read.
  final List<int> notifier = [];

  /// The `notifierOf` reads that are asked for live state.
  final List<int> notifierState = [];

  int _lineOf(int offset) => unit.lineInfo.getLocation(offset).lineNumber;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final line = _lineOf(node.offset);
    if (_isListeningRead(node) || _isDirectDependOn(node)) {
      listening.add(line);
      if (_propertyRead(node) == 'client') clientOnly.add(line);
    }
    if (_isNotifierRead(node)) {
      notifier.add(line);
      if (kControllerState.contains(_propertyRead(node))) {
        notifierState.add(line);
      }
    }
    super.visitMethodInvocation(node);
  }
}

/// The scope reads in [unit], as the four lists the rules compare.
({
  List<int> listening,
  List<int> clientOnly,
  List<int> notifier,
  List<int> notifierState,
})
scopeReadsIn(CompilationUnit unit) {
  final visitor = _ScopeReadVisitor(unit);
  unit.visitChildren(visitor);
  return (
    listening: visitor.listening,
    clientOnly: visitor.clientOnly,
    notifier: visitor.notifier,
    notifierState: visitor.notifierState,
  );
}

/// The guarded reads in [path], tallying the two censuses into
/// [listeningTally] and [notifierTally] on the way past.
///
/// Top-level, taking the tallies as parameters, rather than a closure inside
/// `setUpAll`. The guards' budgets are empty, and a rule that counts zero over
/// real `lib/` can have no vacuity check of its own - so while this lived in
/// the closure, replacing its result with `const []` left the guard counting
/// nothing forever and **all eleven cases still passed**. The cases below
/// exercised the visitor and never the wiring that feeds it to
/// [countAcrossLib]. Out here, every half is reachable from a case.
///
/// The two guards share one returned list because `expectWithinBudget` takes
/// one map and both budgets are zero: a site in either is a failure naming the
/// file, and the `why` names both accessors. They are told apart by the cases
/// over this function, which assert the lists separately.
List<int> scopeReadsFor(
  CompilationUnit unit,
  String path,
  AreaTally listeningTally,
  AreaTally notifierTally,
) {
  // The accessor's own `dependOnInheritedWidgetOfExactType` is the one
  // subscription that is not a page's, and it is the whole point of the file.
  // Exempt from every rule rather than one, so the exemption cannot mean four
  // things.
  if (isExempt(path, const {kScopeFile})) return const <int>[];

  final found = scopeReadsIn(unit);
  listeningTally.add(path, found.listening);
  notifierTally.add(path, found.notifier);
  return [...found.clientOnly, ...found.notifierState];
}

void main() {
  // One walk for all four rules. `countAcrossLib` runs `git ls-files` and
  // parses every file under `lib/`, and every number falls out of one visit.
  late AreaTally listening;
  late AreaTally notifier;
  late ({Map<String, int> counted, Map<String, List<String>> sites}) guarded;

  setUpAll(() {
    final listeningTally = AreaTally();
    final notifierTally = AreaTally();
    guarded = countAcrossLib(
      (unit, path) => scopeReadsFor(unit, path, listeningTally, notifierTally),
    );
    listening = listeningTally;
    notifier = notifierTally;
  });

  /// Asserts [tally] is at or under [budget], having found anything at all.
  ///
  /// The vacuity half is two checks that cannot go stale, and that matters:
  /// an exact count can, which `ratchet.dart` argues in so many words. The
  /// first draft of the listening census asserted `greaterThanOrEqualTo(10)`,
  /// so converting the `firmware_card.dart` site - a strict improvement -
  /// failed with a message claiming the walk had found nothing. Shrinkage is
  /// `expectWithinBudget`'s printed nag, which is this repo's deliberate
  /// asymmetry.
  void expectCensus(AreaTally tally, Map<String, int> budget, String why) {
    expect(
      tally.total,
      greaterThan(0),
      reason: 'a walk that counts nothing passes every budget',
    );
    for (final area in budget.keys) {
      expect(
        tally.counted[area],
        isNotNull,
        reason:
            'no read found in $area at all - either the budget entry is '
            'stale and should go, or the walk stopped seeing it',
      );
    }
    expectWithinBudget(
      counted: tally.counted,
      budget: budget,
      sites: tally.sites,
      budgetFile: 'test/device_scope_listen_test.dart',
      why: why,
    );
  }

  test('no read is guarded against is left in lib/', () {
    expectWithinBudget(
      counted: guarded.counted,
      budget: const <String, int>{},
      sites: guarded.sites,
      budgetFile: 'test/device_scope_listen_test.dart',
      why:
          'Two rules, both at zero, and the site named above is one of them '
          '- read the line it points at to see which: a .client taken off '
          'DeviceScope.of, or live state taken off DeviceScope.notifierOf. '
          '(1) A listening read whose only use is .client: DeviceScope.of '
          'registers a dependency and the client cannot change - '
          'DeviceController._client is final and the controller is late final '
          'in the one state that builds a scope - so the reader rebuilds on '
          'every device-info poll for a value that is the same object every '
          'time, and nothing clears a dependency on a rebuild, so it is '
          'standing wherever it is read. In #339 that was a crash. Call '
          'DeviceScope.clientOf(context). (2) Live state read off '
          'DeviceScope.notifierOf: that read registers no dependency, so the '
          'value is frozen at whenever something else last rebuilt the '
          'reader. Call DeviceScope.of(context) if you need it to stay '
          'current, or notifierOf only to call a method or hand the '
          'controller on. ADR 0011.',
    );
  });

  test('every listening read is one that reads live state in a build', () {
    expectCensus(
      listening,
      kListeningBudget,
      'A new DeviceScope.of read subscribes its whole element to a notifier '
      'that fires every five seconds while a Flipper is connected, and it '
      'keeps that subscription until the element goes - a rebuild does not '
      'clear it. That is right for a build that reads isConnected, info, '
      'dfuPresent or connectionState, and wrong for anything else: use '
      'clientOf for the client and notifierOf to call a method. If the read '
      'really does read live state in a build, raise the number and say what '
      'it reads.',
    );
  });

  test('and every notifierOf read says what it does with the controller', () {
    expectCensus(
      notifier,
      kNotifierBudget,
      'notifierOf hands back the whole controller with no dependency, so it '
      'is the one accessor with no type stopping a stale read - the guard '
      'above catches the obvious shape and cannot see one taken through a '
      'local. What covers that is this budget: raise the number and write '
      'down what the site does with the controller. If it calls a method or '
      'hands it to a Listenable-taking widget, that is what the accessor is '
      'for; if it reads state in a build, it wants DeviceScope.of.',
    );
  });

  test('the state set is every getter DeviceController exposes', () {
    // `kControllerState` is a hand-copied mirror of another file, and the
    // `notifierOf` guard is only as complete as it is: a getter added to
    // `DeviceController` tomorrow is invisible to the rule for ever, silently,
    // which is the one failure this whole file exists to prevent. So the copy
    // is checked rather than trusted - the shape
    // `test/native_struct_mirror_test.dart` established.
    //
    // Getters only. The actions are what `notifierOf` is *for*, and they are
    // `MethodInvocation`s rather than property accesses, so the visitor would
    // not see them anyway.
    const path = 'lib/pages/devices/controllers/device.dart';
    final unit = parseUnit(File(path).readAsStringSync(), path: path);
    final visitor = _GetterVisitor();
    unit.visitChildren(visitor);

    expect(
      visitor.getters,
      hasLength(greaterThan(5)),
      reason: 'found no getters at all in $path - the walk is broken',
    );
    expect(
      visitor.getters,
      kControllerState,
      reason:
          'kControllerState has drifted from DeviceController. Add the new '
          'getter to the set, or - if it really is not device state a build '
          'could read stale - leave it out and say why here. Leaving it out '
          'silently means DeviceScope.notifierOf(context).<it> stops being '
          'caught.',
    );
  });

  group('what counts as a listening read', () {
    ({
      List<int> listening,
      List<int> clientOnly,
      List<int> notifier,
      List<int> notifierState,
    })
    found(String source) => scopeReadsIn(parseUnit(source));

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

  group('what counts as a stale read off notifierOf', () {
    ({
      List<int> listening,
      List<int> clientOnly,
      List<int> notifier,
      List<int> notifierState,
    })
    found(String source) => scopeReadsIn(parseUnit(source));

    test('reading live state off it is the whole point of the rule', () {
      final reads = found('''
        Widget build(BuildContext context) =>
            Text(DeviceScope.notifierOf(context).info.toString());
      ''');
      expect(reads.notifier, [2]);
      expect(reads.notifierState, [2]);
    });

    test('and so is the client, which has its own accessor', () {
      final reads = found('''
        void f(BuildContext context) {
          g(DeviceScope.notifierOf(context).client);
        }
      ''');
      expect(reads.notifierState, [
        2,
      ], reason: 'clientOf is the shorter way round and gives away less');
    });

    test('calling a method on it is not a read', () {
      final reads = found('''
        void f(BuildContext context) {
          DeviceScope.notifierOf(context).synchronize();
        }
      ''');
      expect(reads.notifier, [2], reason: 'counted, so it has to be declared');
      expect(
        reads.notifierState,
        isEmpty,
        reason: 'a MethodInvocation parent, which is what the accessor is for',
      );
    });

    test('and a method whose name is a state member is still a call', () {
      // What pins the *parent type* rather than the name set. Every real
      // method on the controller - `synchronize`, `playAlert`,
      // `buildExportDump` - is absent from `kControllerState`, so a rule that
      // ignored the parent type entirely and matched on the name alone would
      // still pass the case above. A call spelt `info()` separates them: the
      // name is in the set and the parent is a [MethodInvocation].
      final reads = found('''
        void f(BuildContext context) {
          DeviceScope.notifierOf(context).info();
        }
      ''');
      expect(reads.notifier, [2]);
      expect(
        reads.notifierState,
        isEmpty,
        reason: 'a call is a call, whatever it is called',
      );
    });

    test('nor is handing the controller on untouched', () {
      final reads = found('''
        Widget build(BuildContext context) => ListenableBuilder(
          listenable: DeviceScope.notifierOf(context),
          builder: (context, _) => const SizedBox(),
        );
      ''');
      expect(reads.notifier, [2]);
      expect(reads.notifierState, isEmpty);
    });

    test('a getter that is not state is not caught', () {
      final reads = found('''
        void f(BuildContext context) {
          g(DeviceScope.notifierOf(context).hashCode);
        }
      ''');
      expect(
        reads.notifierState,
        isEmpty,
        reason: 'the set is DeviceController\'s state, not every property',
      );
    });

    test('a listening read is not a notifierOf read', () {
      final reads = found('''
        Widget build(BuildContext context) =>
            Text(DeviceScope.of(context).info.toString());
      ''');
      expect(reads.notifier, isEmpty);
      expect(reads.notifierState, isEmpty);
      expect(reads.listening, [2], reason: 'it belongs to the other census');
    });

    test('a read taken into a local is invisible here too', () {
      final reads = found('''
        void f(BuildContext context) {
          final ctrl = DeviceScope.notifierOf(context);
          g(ctrl.info);
        }
      ''');
      expect(
        reads.notifierState,
        isEmpty,
        reason:
            'which is the hole _openFullInfo sits in, covered by the '
            'budget line rather than by this rule',
      );
      expect(reads.notifier, [2], reason: 'but the census still counts it');
    });
  });

  group('what the walk is handed', () {
    const listeningSource = '''
      Widget build(BuildContext context) =>
          QPageAppBar(client: DeviceScope.of(context).client);
    ''';

    const notifierSource = '''
      Widget build(BuildContext context) =>
          Text(DeviceScope.notifierOf(context).info.toString());
    ''';

    test('a client-only listening read reaches the guard and the census', () {
      final listening = AreaTally();
      final notifier = AreaTally();
      final lines = scopeReadsFor(
        parseUnit(listeningSource),
        'lib/pages/about/license_page.dart',
        listening,
        notifier,
      );
      expect(lines, [2], reason: 'the guard is fed the client-only subset');
      expect(listening.counted, {'pages/about': 1});
      expect(listening.sites, {
        'pages/about': ['lib/pages/about/license_page.dart:2'],
      });
      expect(notifier.counted, isEmpty);
    });

    test('a stale notifierOf read reaches the guard and the other census', () {
      final listening = AreaTally();
      final notifier = AreaTally();
      final lines = scopeReadsFor(
        parseUnit(notifierSource),
        'lib/app/shell.dart',
        listening,
        notifier,
      );
      expect(lines, [2], reason: 'both guards share the one returned list');
      expect(notifier.counted, {'app': 1});
      expect(
        listening.counted,
        isEmpty,
        reason: 'notifierOf does not subscribe, so it is not in that census',
      );
    });

    test('and the scope file contributes to none of them', () {
      final listening = AreaTally();
      final notifier = AreaTally();
      expect(
        scopeReadsFor(
          parseUnit(listeningSource),
          kScopeFile,
          listening,
          notifier,
        ),
        isEmpty,
      );
      expect(
        scopeReadsFor(
          parseUnit(notifierSource),
          kScopeFile,
          listening,
          notifier,
        ),
        isEmpty,
      );
      expect(
        listening.counted,
        isEmpty,
        reason: 'the exemption covers every rule, not just the guards',
      );
      expect(notifier.counted, isEmpty);
    });
  });
}

/// The public getter names declared in a unit.
///
/// Only used on `controllers/device.dart`, which holds one class - so no class
/// filtering is needed, and the test asserts it found something rather than
/// trusting that.
class _GetterVisitor extends RecursiveAstVisitor<void> {
  final Set<String> getters = {};

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    if (node.isGetter && !name.startsWith('_')) getters.add(name);
    super.visitMethodDeclaration(node);
  }
}
