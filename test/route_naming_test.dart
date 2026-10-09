// Every route the registry pushes carries its name — ADR 0013, phase 2.
//
// A navigator observer has one way to say which screen a transaction belongs
// to, and that is `RouteSettings.name`. Before this, `openRoute` built a bare
// `MaterialPageRoute` and every cross-feature screen reported as an
// indistinguishable unnamed route - so the transactions existed and told
// nobody anything, which is worse than not having them.
//
// The 25 `MaterialPageRoute`s inside features stay unnamed on purpose: naming
// them would be 25 strings with nothing keeping them in step, where these are
// derived from the enum and cannot drift.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/navigation.dart';

/// Pushes without waiting for the pop.
///
/// `openRoute`'s future completes when the route is *popped*, so awaiting it
/// in a test that never pops hangs until the harness gives up. `unawaited`
/// rather than a bare call because the analyzer is right to ask, and the throw
/// `openRoute` can produce is synchronous - it happens before there is a
/// future, so nothing is being dropped.
void push(BuildContext context, AppRoute route, {bool replace = false}) {
  unawaited(openRoute(context, route, replace: replace));
}

/// Records what the navigator was handed, which is what an observer sees.
///
/// Both callbacks, because a replacement is not a push: `pushReplacement`
/// fires `didReplace` and nothing else, so a spy watching only `didPush` reads
/// a replaced screen as never having been navigated to. That is the same hole
/// a real observer would have, which is why the test needs both.
class _Spy extends NavigatorObserver {
  final List<String?> arrived = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previous) {
    arrived.add(route.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    arrived.add(newRoute?.settings.name);
  }
}

void main() {
  testWidgets('a pushed route is named after the enum', (tester) async {
    final spy = _Spy();
    registerRoute(AppRoute.about, (_, _) => const Scaffold());

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [spy],
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold();
          },
        ),
      ),
    );

    push(ctx, AppRoute.about);
    await tester.pumpAndSettle();

    expect(spy.arrived, contains('about'));
  });

  testWidgets('a replacement is named too', (tester) async {
    // `pushReplacement` goes through the same builder, so this is really
    // asserting that the settings are on the route rather than on the push.
    final spy = _Spy();
    registerRoute(AppRoute.appSettings, (_, _) => const Scaffold());

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [spy],
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold();
          },
        ),
      ),
    );

    push(ctx, AppRoute.appSettings, replace: true);
    await tester.pumpAndSettle();

    expect(spy.arrived, contains('appSettings'));
  });

  test('every route can be named, and no two share a name', () {
    // The names are `AppRoute`'s own, so this is really a check that the enum
    // has no duplicate-looking members and that nothing is blank - a blank
    // name reads to an observer exactly like an unnamed route.
    final names = AppRoute.values.map((r) => r.name).toList();
    expect(names, everyElement(isNotEmpty));
    expect(names.toSet(), hasLength(names.length));
  });
}
