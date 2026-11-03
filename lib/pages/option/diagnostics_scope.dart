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
  /// which is what [notifierOf] is for: the subscription a single read
  /// registers does not lapse on the next build. `DeviceScope.of` and
  /// [ADR 0011](../../../docs/adr/0011-device-scope-above-the-navigator.md)
  /// have the mechanism.
  static DiagnosticsSettings of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DiagnosticsScope>()!
        .notifier!;
  }

  /// The switch, without a dependency.
  ///
  /// `DeviceScope.clientOf`'s accessor, for this scope's one object - read
  /// without registering a dependency, by `getInheritedWidgetOfExactType`.
  ///
  /// **The sentence of Flutter's worth citing for it is "this method does not
  /// introduce a dependency"**, and not the one about "interaction event
  /// handlers (e.g. gesture callbacks) or timers, to obtain a value once":
  /// that one sits in **both** accessors' doc templates, so it tells them
  /// apart in neither direction. `clientOf` cited it until this accessor was
  /// written and has been corrected.
  ///
  /// The one call site is `AppShell`'s post-frame callback, which
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
  /// **What makes it safe is `clientOf`'s argument and not Flutter's wording**,
  /// because the one call site does keep the object:
  /// `showDiagnosticsNoticeIfDue` holds it across `settings.load()`,
  /// `markNoticeShown()` and a sheet that stays up until the user answers,
  /// then calls `setShareLogs(false)` on it. The evidence that rescues that is
  /// particular to this scope, so it belongs here: `lib/main.dart` constructs
  /// exactly one `DiagnosticsSettings` and hands it to `Telemetry`, and
  /// `main` passes that same object to `QUnleashedApp`, where a `final` field
  /// feeds the only scope. There is nothing for the read to go stale against.
  ///
  /// **Still never for reading state off in a `build`** - `clientOf`'s doc has
  /// why. What is particular here is that nothing enforces it:
  /// `test/device_scope_listen_test.dart` is hard-wired to `DeviceScope`, and
  /// #415's argument is that two call sites do not warrant a second census. So
  /// this paragraph is the whole of the guard, over a `DiagnosticsSettings`
  /// carrying three live values.
  static DiagnosticsSettings notifierOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<DiagnosticsScope>()!.notifier!;
  }
}
