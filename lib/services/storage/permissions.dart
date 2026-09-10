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
/// The status is re-read on every call: it needs no activity, shows nothing and
/// costs a context lookup, so a grant made later - from the system settings, or
/// after the app was reinstalled and the permission came back revoked - is seen
/// at once. Only the prompt is fired once per process: MANAGE_EXTERNAL_STORAGE
/// sends the user to a system settings screen, so it must not be re-asked per
/// file operation. A prompt that never reached the user (the plugin refuses a
/// request while another one is running, and the app fires several at startup)
/// does not count as asked, or the ask would be lost for the whole run.
Future<bool> ensureAndroidStoragePermission() async {
  if (!io.Platform.isAndroid) return true;
  final permission = await (_storagePermission ??= _resolvePermission());
  if (await _isGranted(permission)) return true;
  return _prompt ??= _requestOnce(permission);
}

Future<Permission>? _storagePermission;
Future<bool>? _prompt;

Future<Permission> _resolvePermission() async {
  final android = await DeviceInfoPlugin().androidInfo;
  return android.version.sdkInt >= 30
      ? Permission.manageExternalStorage
      : Permission.storage;
}

Future<bool> _isGranted(Permission permission) async {
  try {
    return (await permission.status).isGranted;
  } catch (_) {
    return false;
  }
}

Future<bool> _requestOnce(Permission permission) async {
  try {
    return (await permission.request()).isGranted;
  } catch (_) {
    _prompt = null;
    return false;
  }
}
