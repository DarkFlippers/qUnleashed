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
  /// without registering one, and Flutter's doc on it blesses exactly this
  /// use: "interaction event handlers (e.g. gesture callbacks) or timers, to
  /// obtain a value once, as long as that value is not cached and/or reused
  /// later". The one call site is `AppShell`'s post-frame callback, which
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
  /// **For a value read once and not kept.** A non-listening read taken into
  /// a `build` is a silent staleness bug: `DiagnosticsSettings` carries
  /// `shareLogs` and `shareReplay`, and either one drawn from this would show
  /// whatever it was when something else last rebuilt the reader.
  static DiagnosticsSettings notifierOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<DiagnosticsScope>()!.notifier!;
  }
}
