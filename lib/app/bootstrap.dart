import 'dart:async';
import 'dart:io' show Platform;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../pages/tools/infrared/local_repo.dart';
import '../services/connection/device_info_watch.dart';
import '../services/connection/foreground_service.dart';
import '../services/connection/link_service.dart';
import '../services/connection/notification_service.dart';
import '../services/guarded.dart';
import '../services/notifications/push_service.dart';
import '../services/permissions/center.dart';
import '../services/rpc/gps/geolocator_gps_provider.dart';
import '../services/rpc/gps/gps_responder.dart';
import '../services/rpc/network/network_responder.dart';

/// genuinely unexpected runtime errors (IO, OS permission denials), not a
/// substitute for correct per-platform configuration.
void bootstrapAmbientServices(PermissionCenter permissions) {
  final client = FlipperOneClient().get();

  // Starts watching for the user coming back from system settings, so a
  // granted permission clears its notice without a restart. Here and not in
  // the constructor: `widgetMain()`'s isolate records outcomes but has no
  // screen to update, and a bare unit test has no `WidgetsBinding` to add an
  // observer to - which is the trap `localization/controller.dart` is in. #351.
  permissions.install();

  // One read at startup, so a standing denial is known before the user walks
  // into the surface it affects. Reads only - no probe raises a prompt, which
  // is what makes this safe here rather than an ask at launch, the thing #351
  // explicitly rules out. It is also what gives the iOS blocking screen its
  // signal: nothing else would ask about Bluetooth until a scan.
  //
  // The no-prompt half rests on `ios/Runner/Info.plist` declaring the
  // `bluetooth-central` background mode: universal_ble answers the
  // authorisation read without instantiating a `CBCentralManager` only when
  // it is there, and creating that manager is what raises the iOS prompt.
  // Drop the key and this line starts prompting at launch.
  // One ordered entry, not two concurrent ones. Started separately, a probe
  // recording `granted` could beat the dismissal read, and then the stored
  // dismissal was re-added by a read that arrived after the clear - see
  // `PermissionCenter._clearDismissal`. Reading the dismissals first also
  // means a notice never flickers in before its dismissal is known.
  _start('permission status', () async {
    await permissions.load();
    await permissions.refresh();
  });

  LinkService.instance.start(client);

  _start(
    'connection notifier',
    () => ConnectionNotificationService.instance.start(client),
  );

  _start(
    'ble foreground service',
    () => BleForegroundService.instance.start(client, permissions: permissions),
  );

  // Answers GPS requests from custom firmware apps with the phone's location.
  final gps = GeolocatorGpsProvider();
  client.attachGpsResponder(gps);

  // Desktop raises the prompt at launch instead of mid-request: there the ask
  // arrives when the map opens or the Flipper is already waiting for a fix.
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    _start('location permission', gps.ensureReady);
  }

  // Answers network requests from custom firmware apps with the phone's
  // internet connection.
  client.attachNetworkResponder();

  // Battery/storage polling is pointless while nobody can see it; freezing it
  // in the background saves both the phone's and the Flipper's battery.
  WidgetsBinding.instance.addObserver(_WatchLifecycleObserver());

  _start(
    'push notifications',
    () => PushService.instance.start(permissions: permissions),
  );

  // A refresh killed mid-swap leaves the IR library under a name only recovery
  // looks for. Repairing it here rather than when the IR page opens means the
  // library is not absent to the rest of the app until the user happens to go
  // there — Settings → Storage reported its size as zero in the meantime — and
  // it lets exists() go back to being a plain read.
  _start('ir library recovery', IrLibLocalRepo.recoverStranded);
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

/// Starts an ambient service and records a failure rather than dropping it.
///
/// Returns void rather than a future the caller must remember to drop: nothing
/// awaits any of these - the app comes up either way - and a signature that
/// cannot be awaited says so better than an unawaited() at each site did.
///
/// Tagged like every other kept line, because these now reach the reporting
/// channel and the label is what makes one searchable there; before, at info,
/// they reached nothing.
/// Generic for the same reason [guarded] is: `Future<void> Function()` accepts
/// a task returning anything, because `void` is a top type, so this wrapper
/// used to erase the type one frame above `guarded` and hand it a future whose
/// real argument was something else. `guarded` no longer cares - it catches
/// rather than reading a type argument - but leaving the erasure here is how
/// the next `catchError` written in this file would inherit QUNLEASHED-A.
void _start<T>(String label, Future<T> Function() task) =>
    unawaited(guarded('[Bootstrap] ambient service "$label"', task));
