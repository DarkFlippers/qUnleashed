import 'dart:async';
import 'dart:io' show Platform;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../pages/tools/infrared/local_repo.dart';
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
  final gps = GeolocatorGpsProvider();
  client.attachGpsResponder(gps);

  // Desktop raises the prompt at launch instead of mid-request: there the ask
  // arrives when the map opens or the Flipper is already waiting for a fix.
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    unawaited(_guard('location permission', gps.ensureReady));
  }

  // Answers network requests from custom firmware apps with the phone's
  // internet connection.
  client.attachNetworkResponder();

  // Battery/storage polling is pointless while nobody can see it; freezing it
  // in the background saves both the phone's and the Flipper's battery.
  WidgetsBinding.instance.addObserver(_WatchLifecycleObserver());

  unawaited(_guard('push notifications', () => PushService.instance.start()));

  // A refresh killed mid-swap leaves the IR library under a name only recovery
  // looks for. Repairing it here rather than when the IR page opens means the
  // library is not absent to the rest of the app until the user happens to go
  // there — Settings → Storage reported its size as zero in the meantime — and
  // it lets exists() go back to being a plain read.
  unawaited(_guard('ir library recovery', IrLibLocalRepo.recoverStranded));
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
