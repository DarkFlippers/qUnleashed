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

  static DiagnosticsSettings of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DiagnosticsScope>()!
        .notifier!;
  }
}
