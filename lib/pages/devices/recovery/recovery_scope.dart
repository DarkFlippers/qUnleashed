import 'package:flutter/widgets.dart';

import 'recovery_controller.dart';

class RecoveryScope extends InheritedNotifier<RecoveryController> {
  const RecoveryScope({
    super.key,
    required super.notifier,
    required super.child,
  });

  static RecoveryController of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<RecoveryScope>()!
        .notifier!;
  }
}
