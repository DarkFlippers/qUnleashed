import 'package:flutter/widgets.dart';

import 'controller.dart';

class DeviceScope extends InheritedNotifier<DeviceController> {
  const DeviceScope({
    super.key,
    required super.notifier,
    required super.child,
  });

  static DeviceController of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DeviceScope>()!
        .notifier!;
  }
}
