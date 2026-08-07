import 'dart:io' as io;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests the runtime permission required to write into the shared
/// Documents directory on Android. Returns true if access is granted.
///
/// Which permission applies depends on the OS version: API 30+ can only reach
/// files outside the sandbox through MANAGE_EXTERNAL_STORAGE, while API 29
/// still runs in legacy mode and uses WRITE_EXTERNAL_STORAGE (declared in the
/// manifest with maxSdkVersion="29"). Requesting the other one is always
/// denied, since the platform drops out-of-range permissions from the package.
///
/// Requested once per process: MANAGE_EXTERNAL_STORAGE sends the user to a
/// system settings screen, so it must not be re-asked per file operation.
Future<bool> ensureAndroidStoragePermission() {
  return _androidStoragePermission ??= _requestAndroidStoragePermission();
}

Future<bool>? _androidStoragePermission;

Future<bool> _requestAndroidStoragePermission() async {
  if (!io.Platform.isAndroid) return true;

  final android = await DeviceInfoPlugin().androidInfo;
  final permission = android.version.sdkInt >= 30
      ? Permission.manageExternalStorage
      : Permission.storage;
  return (await permission.request()).isGranted;
}
