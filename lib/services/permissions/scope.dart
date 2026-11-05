import 'package:flutter/widgets.dart';

import 'center.dart';

/// Hands the permission record to whoever draws a notice.
///
/// `DiagnosticsScope`'s shape, for the same reasons it gives: the object is
/// built once at the composition root and handed down rather than reached for
/// through a static
/// ([0002](../../../docs/adr/0002-dependencies-are-passed-in.md)), and it is a
/// scope rather than a constructor parameter because the screens that need it
/// — Settings → Storage, Settings → Push, the IR dialog, the device picker —
/// are reached through the `AppRoute` registry, which builds pages without
/// arguments ([0006](../../../docs/adr/0006-navigation.md)).
///
/// An `InheritedNotifier`, which is the whole point: a user who leaves for
/// system settings, grants the permission and comes back must find the notice
/// gone without restarting the app. The resume re-read lives in
/// [PermissionCenter]; this is what makes it visible.
///
/// Mounted in `MaterialApp.builder` beside the other two, so a pushed route is
/// inside it. Mounted in `AppShell` it would sit on route `/` and every
/// settings page would be that route's sibling.
class PermissionScope extends InheritedNotifier<PermissionCenter> {
  const PermissionScope({
    super.key,
    required super.notifier,
    required super.child,
  });

  /// The record, for a widget that is going to draw something from it.
  ///
  /// Asserts rather than returning null: every caller is below
  /// `MaterialApp.builder`, and a null here would be a wiring mistake that
  /// shows up as a notice silently never appearing — the exact failure #351
  /// is about.
  static PermissionCenter of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PermissionScope>();
    assert(scope != null, 'No PermissionScope above this widget');
    return scope!.notifier!;
  }

  /// The record, or null where there may not be one.
  ///
  /// For a widget that is also built outside the app's tree — a dialog shown
  /// from a widget test that puts up a bare `MaterialApp`, which is how
  /// `L10nContext` justifies its own fallback. A notice that cannot find the
  /// record draws nothing, which is the same thing it does for an unknown
  /// outcome.
  static PermissionCenter? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PermissionScope>()
        ?.notifier;
  }
}
