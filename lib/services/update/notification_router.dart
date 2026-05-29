import 'dart:io';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../config.dart';
import '../../pages/devices/widgets/firmware_changelog_page.dart';
import 'firmware_directory.dart';
import 'update_service.dart';

final GlobalKey<NavigatorState> updateNavigatorKey =
    GlobalKey<NavigatorState>();

String? _pendingFirmwareUpdatePayload;

void handleFirmwareUpdateNotificationPayload(String? payload) {
  if (payload == null || !payload.startsWith('firmware_update:')) return;
  _pendingFirmwareUpdatePayload = payload;
  _flushPendingFirmwareUpdatePayload();
}

void flushPendingFirmwareUpdateRoute() {
  _flushPendingFirmwareUpdatePayload();
}

Future<void> _flushPendingFirmwareUpdatePayload() async {
  final payload = _pendingFirmwareUpdatePayload;
  if (payload == null) return;

  final navigator = updateNavigatorKey.currentState;
  if (navigator == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushPendingFirmwareUpdatePayload();
    });
    return;
  }

  final source = payload.substring('firmware_update:'.length);
  final entry = QAppConfig.firmware.firmwares
      .where((entry) => entry.shortName == source)
      .firstOrNull;
  if (entry == null) return;

  final dir = UpdateService.instance.directoryForSource(source);
  final version = dir?.channelById('release')?.latest;
  if (version == null) return;

  _pendingFirmwareUpdatePayload = null;
  await _activateExistingDesktopWindow();
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => FirmwareChangelogPage(
        entry: entry,
        version: version,
        changelog: version.changelog,
        fetchLoading: false,
        latestVersion: version.version,
        deviceVersion: null,
        deviceInfo: const {},
        selectedChannelId: FirmwareChannel.release.id,
        selectedVariant: UnleashedVariant.extraPacks,
        client: FlipperOneClient().get(),
      ),
    ),
  );
}

Future<void> _activateExistingDesktopWindow() async {
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;
  await windowManager.ensureInitialized();
  if (!await windowManager.isVisible()) {
    await windowManager.show();
  }
  if (await windowManager.isMinimized()) {
    await windowManager.restore();
  }
  await windowManager.focus();
}
