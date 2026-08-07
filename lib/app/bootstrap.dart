import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../services/connection/device_info_watch.dart';
import '../services/connection/foreground_service.dart';
import '../services/connection/notification_service.dart';
import '../services/logging.dart';
import '../services/notifications/push_service.dart';
import '../services/rpc/gps/geolocator_gps_provider.dart';
import '../services/rpc/gps/gps_responder.dart';
import '../services/rpc/network/network_responder.dart';

/// genuinely unexpected runtime errors (IO, OS permission denials), not a
/// substitute for correct per-platform configuration.
void bootstrapAmbientServices() {
  final client = FlipperOneClient().get();

  unawaited(
    _guard(
      'connection notifier',
      () => ConnectionNotificationService.instance.start(client),
    ),
  );

  unawaited(
    _guard(
      'ble foreground service',
      () => BleForegroundService.instance.start(client),
    ),
  );

  // Answers GPS requests from custom firmware apps with the phone's location.
  client.attachGpsResponder(GeolocatorGpsProvider());

  // Answers network requests from custom firmware apps with the phone's
  // internet connection.
  client.attachNetworkResponder();

  // Battery/storage polling is pointless while nobody can see it; freezing it
  // in the background saves both the phone's and the Flipper's battery.
  WidgetsBinding.instance.addObserver(_WatchLifecycleObserver());

  unawaited(_guard('push notifications', () => PushService.instance.start()));
}

class _WatchLifecycleObserver with WidgetsBindingObserver {
  _WatchLifecycleObserver();

  bool _frozen = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final background =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (background == _frozen) return;
    _frozen = background;
    if (background) {
      DeviceInfoWatchService.instance.freeze();
    } else {
      DeviceInfoWatchService.instance.unfreeze();
    }
  }
}

Future<void> _guard(String label, Future<void> Function() task) async {
  try {
    await task();
  } catch (error, stackTrace) {
    LogService.log('Ambient service "$label" failed: $error\n$stackTrace');
  }
}
