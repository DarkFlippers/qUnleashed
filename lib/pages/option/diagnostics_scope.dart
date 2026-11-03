import 'package:flutter/widgets.dart';

import '../../services/telemetry/settings.dart';

/// Hands the reporting switch to whoever draws it.
///
/// `DeviceScope`'s shape, for the same reason: the object is built once at the
/// composition root and handed down, rather than reached for through a static
/// ([0002](../../../docs/adr/0002-dependencies-are-passed-in.md)). A scope and
/// not a constructor parameter because the settings screen is reached through
/// the `AppRoute` registry, which builds pages without arguments
/// ([0006](../../../docs/adr/0006-navigation.md)) - threading one bool through
/// it would mean a parameter on every page between here and there.
///
/// An `InheritedNotifier`, so the switch redraws itself when the value
/// changes and the one-time notice's **Turn it off** is visible on the screen
/// behind it.
///
/// Mounted in `MaterialApp.builder` rather than in `AppShell`, which is what
/// `DeviceScope`'s comment there is about: `builder` wraps the Navigator, so a
/// pushed route is inside the scope. Mounted in the shell it would sit on
/// route `/` and the settings screen would be that route's sibling.
class DiagnosticsScope extends InheritedNotifier<DiagnosticsSettings> {
  const DiagnosticsScope({
    super.key,
    required super.notifier,
    required super.child,
  });

  /// The switch, with a dependency on it: the reader redraws when it moves.
  ///
  /// For a widget that draws the value - the settings screen's own `Switch`,
  /// which is the one call site. **Not for reading it once from a callback**,
  /// which is what [notifierOf] is for: nothing clears
  /// `Element._dependencies` on a rebuild, so a single read from a gesture
  /// handler or a post-frame callback subscribes that element for its whole
  /// life rather than until its next build.
  static DiagnosticsSettings of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DiagnosticsScope>()!
        .notifier!;
  }

  /// The switch, without a dependency.
  ///
  /// `getInheritedWidgetOfExactType` reads the current inherited widget
  /// without registering one: "This method does not introduce a dependency
  /// the way that the more typical `dependOnInheritedWidgetOfExactType` does,
  /// so this context will not be rebuilt if the `InheritedWidget` changes."
  /// That is the sentence worth citing, and not the one about "interaction
  /// event handlers (e.g. gesture callbacks) or timers, to obtain a value
  /// once" - which sits in **both** accessors' doc templates and so blesses
  /// neither over the other. The one call site is `AppShell`'s post-frame
  /// callback, which
  /// reads the switch to decide whether ADR 0013 §1's notice is due - once, at
  /// the first frame, for a shell whose `build` assembles the page stack and
  /// the rail groups. Taken the listening way, flipping the reporting switch
  /// rebuilt all of that. #415.
  ///
  /// This is `DeviceScope.notifierOf`'s shape and the third version of the
  /// same mistake - #344 and #407 were the first two - with one difference
  /// worth keeping in view: there the poll notified twelve times a minute,
  /// here it is a switch a user flips, so the cost was a rebuild nobody would
  /// have measured. The accessor is the point, so the next reader has the
  /// non-listening spelling to hand.
  ///
  /// **What makes it safe is that there is one switch for the run**, and not
  /// the "value read once and not kept" wording - because the one call site
  /// does keep it. `showDiagnosticsNoticeIfDue` holds the object across
  /// `settings.load()`, `markNoticeShown()` and a sheet that stays up until
  /// the user answers, then calls `setShareLogs(false)` on it. What covers
  /// that is `DeviceScope.clientOf`'s argument rather than Flutter's:
  /// `lib/main.dart` constructs exactly one `DiagnosticsSettings`, hands it to
  /// `Telemetry`, and passes that same object to `QUnleashedApp`, where a
  /// `final` field feeds the only scope - so there is nothing for the read to
  /// go stale against. `clientOf` had to add this paragraph after #406 for
  /// over-claiming the same blessing; this is that correction taken rather
  /// than re-learned.
  ///
  /// **Still never for reading state off in a `build`.** `DiagnosticsSettings`
  /// carries `shareLogs`, `shareReplay` and `noticeShown`, and any of the
  /// three drawn from this would show whatever it was when something else last
  /// rebuilt the reader. Nothing enforces that: `DeviceScope` has a syntactic
  /// ratchet for it in `test/device_scope_listen_test.dart`, hard-wired to
  /// that scope, and #415's own argument is that two call sites do not warrant
  /// a second census. So this paragraph is the whole of the guard.
  static DiagnosticsSettings notifierOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<DiagnosticsScope>()!.notifier!;
  }
}
