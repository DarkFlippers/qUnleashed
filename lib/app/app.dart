import 'package:flutter/material.dart';

import '../pages/devices/controllers/device.dart';
import '../pages/devices/device_scope.dart';
import '../services/localization/controller.dart';
import '../services/localization/l10n.dart';
import '../theme/theme.dart';
import 'shell.dart';

class QUnleashedApp extends StatefulWidget {
  const QUnleashedApp({super.key, this.device});

  /// The device controller the whole app reads, for a test that wants to
  /// supply its own. Built here when nobody does.
  final DeviceController? device;

  @override
  State<QUnleashedApp> createState() => _QUnleashedAppState();
}

class _QUnleashedAppState extends State<QUnleashedApp> {
  /// Owned here rather than by [AppShell], and held in state rather than
  /// built in [build] - ADR 0011.
  ///
  /// The `MaterialApp` below is rebuilt on every theme and locale change, so
  /// a controller constructed in `build` would be replaced on each accent
  /// colour, taking its subscriptions and its device with it.
  late final DeviceController _device = widget.device ?? DeviceController();

  @override
  void dispose() {
    // Only what this built. A controller handed in belongs to whoever handed
    // it over, and tearing down someone else's fixture from here is how a
    // test comes to fail in its teardown rather than its body.
    if (widget.device == null) {
      _device.dispose();
      // Moved up with the controller. Only reached when the app itself goes,
      // which on a phone is never - but it belongs wherever the controller
      // is, and it was in `AppShell.dispose` for the same reason.
      _device.client.disconnectAll();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = QAppThemeController.instance;
    final locales = QLocaleController.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([controller, locales]),
      builder: (context, _) {
        return MaterialApp(
          onGenerateTitle: (context) => context.l10n.appTitle,
          debugShowCheckedModeBanner: false,
          locale: locales.locale,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: buildAppTheme(controller.brightness, controller.accent),
          themeAnimationDuration: Duration.zero,
          // `builder` wraps the Navigator, so a pushed route is inside this
          // scope as well as the shell is. Mounting it in `AppShell` put it
          // on route `/`, and a pushed route is that route's sibling.
          builder: (context, child) =>
              DeviceScope(notifier: _device, child: child!),
          home: const AppShell(),
        );
      },
    );
  }
}
