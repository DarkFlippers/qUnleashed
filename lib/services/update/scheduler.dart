import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:workmanager/workmanager.dart';

import '../../widgets/notifications/update.dart';
import 'update_service.dart';
import 'worker.dart';

const String kFirmwareUpdateTaskUniqueName = 'firmware_update_check';
const String kFirmwareUpdateTaskName = 'firmware_update_check';

@pragma('vm:entry-point')
void firmwareUpdateCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await UpdateService.instance.initialize();
    await initFirmwareUpdateNotifications(requestPermissions: false);
    await checkAndNotifyFirmwareUpdates();
    return Future.value(true);
  });
}

Future<void> initializeUpdateScheduling() async {
  if (Platform.isAndroid) {
    await _initializeAndroidScheduling();
    return;
  }

  if (Platform.isIOS) {
    await _initializeIosScheduling();
    return;
  }

  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await DesktopUpdateScheduler.instance.initialize();
  }
}

Future<int> checkAndNotifyFirmwareUpdates() async {
  final updates = await UpdateService.instance.checkForUpdates();
  for (final update in updates) {
    await FirmwareUpdateNotification.show(
      firmwareName: update.sourceName,
      newVersion: update.newVersion,
      previousVersion: update.previousVersion,
    );
  }
  return updates.length;
}

Future<void> _initializeAndroidScheduling() async {
  await Workmanager().initialize(firmwareUpdateCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    kFirmwareUpdateTaskUniqueName,
    kFirmwareUpdateTaskName,
    frequency: UpdateWorker.interval,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

Future<void> _initializeIosScheduling() async {
  await Workmanager().initialize(firmwareUpdateCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    kFirmwareUpdateTaskUniqueName,
    kFirmwareUpdateTaskName,
    initialDelay: UpdateWorker.interval,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

class DesktopUpdateScheduler with TrayListener, WindowListener {
  DesktopUpdateScheduler._();

  static final DesktopUpdateScheduler instance = DesktopUpdateScheduler._();

  bool _initialized = false;
  bool _allowClose = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    trayManager.addListener(this);
    await trayManager.setIcon(_trayIconPath());
    await trayManager.setToolTip('qUnleashed');
    await _setTrayMenu();

    UpdateWorker.instance.events.listen((event) {
      FirmwareUpdateNotification.show(
        firmwareName: event.sourceName,
        newVersion: event.newVersion,
        previousVersion: event.previousVersion,
      );
    });
    UpdateWorker.instance.start();
  }

  Future<void> _setTrayMenu() async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Open qUnleashed'),
          MenuItem(key: 'check', label: 'Check for Updates'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: 'Exit'),
        ],
      ),
    );
  }

  String _trayIconPath() {
    return 'assets/firmware/unleashed_tray.png';
  }

  @override
  void onTrayIconMouseDown() {
    if (Platform.isMacOS || Platform.isWindows) {
      trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    if (Platform.isMacOS || Platform.isWindows) {
      trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_showWindow());
      case 'check':
        unawaited(_checkNow());
      case 'exit':
        unawaited(_exitApp());
    }
  }

  @override
  void onWindowClose() {
    if (_allowClose) return;
    unawaited(windowManager.hide());
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _checkNow() async {
    final count = await checkAndNotifyFirmwareUpdates();
    if (count > 0) return;
    await FirmwareUpdateNotification.showMessage(
      id: 1010,
      title: 'Firmware Updates',
      body: 'No updates found',
    );
  }

  Future<void> _exitApp() async {
    _allowClose = true;
    UpdateWorker.instance.stop();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
    await windowManager.destroy();
    exit(0);
  }
}
