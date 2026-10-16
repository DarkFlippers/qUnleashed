import 'dart:io' as io;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:permission_handler/permission_handler.dart';

import '../logging.dart';
import '../permissions/permission.dart';
import 'asked_store.dart';

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
///
/// The answer also reaches the sink `reportStoragePermissionTo` installed,
/// which is how it leaves this file at all. Until #351 the bool was the only
/// account of a denial and its one caller discarded it, so a user who said no
/// was told nothing: the IR page offered to re-download a library that was
/// already on disk, and Settings → Storage reported 0 B.
///
/// **A failure is never reported as a refusal.** Every path below that cannot
/// get an answer reports [PermissionOutcome.unknown], which draws nothing. The
/// alternative shipped a non-dismissible gate on three screens, and disabled
/// the IR download button, because a plugin call failed during startup.
Future<bool> ensureAndroidStoragePermission() async {
  // Not Android: there is nothing to grant, which is not the same as granted.
  // `true` is still the right answer to the caller's question — the path is
  // writable — but reporting it as a grant would make a desktop build show a
  // storage notice the day someone inverted a condition here.
  if (!io.Platform.isAndroid) {
    _report(PermissionOutcome.unavailable);
    return true;
  }
  final permission = await _resolvePermission();
  if (permission == null) {
    _report(PermissionOutcome.unknown);
    return false;
  }
  switch (await _isGranted(permission)) {
    case true:
      _report(PermissionOutcome.granted);
      return true;
    case null:
      // The status read itself failed. Not a refusal, and the caller still has
      // to try the operation — the OS is what refuses, not this function.
      _report(PermissionOutcome.unknown);
      return false;
    case false:
      break;
  }
  final granted = await (_prompt ??= _requestOnce(permission));
  if (granted == null) {
    // Could not ask. The plugin refuses a request while another one is
    // running and the app fires several at startup, so this is a routine
    // path, not an exotic one.
    _report(PermissionOutcome.unknown);
    return false;
  }
  _report(granted ? PermissionOutcome.granted : PermissionOutcome.denied);
  return granted;
}

/// Reads the storage permission's state without raising a prompt.
///
/// The probe `PermissionCenter` re-runs on resume. A read and never an ask:
/// MANAGE_EXTERNAL_STORAGE opens a full system settings screen, and raising
/// that on every return to the app would bounce the user straight back out of
/// the one they just came back to.
///
/// "Not granted" becomes [PermissionOutcome.denied] only once this install has
/// actually shown the prompt. Before that it is [PermissionOutcome.unknown]:
/// a permission nobody has asked for is not one the user refused, and a gate
/// drawn over it would be a wall in front of someone who has not been shown
/// the explainer yet.
///
/// The asked flag is persisted, which is what makes a standing denial visible
/// at startup. Held per process it could not be — every fresh launch read
/// `unknown`, so the notice could not appear until something re-fired the raw
/// system ask, which is exactly the unannounced settings dump the explainer
/// exists to replace.
Future<PermissionOutcome> readAndroidStoragePermission() async {
  if (!io.Platform.isAndroid) return PermissionOutcome.unavailable;
  final permission = await _resolvePermission();
  if (permission == null) return PermissionOutcome.unknown;
  switch (await _isGranted(permission)) {
    case true:
      return PermissionOutcome.granted;
    case null:
      // A read that failed is not a user who said no. Reported as a refusal
      // this told a user who *had* granted the permission to go and grant it,
      // and unlike the request path it survived every later resume.
      return PermissionOutcome.unknown;
    case false:
      return await storageAskedStore.wasAsked()
          ? PermissionOutcome.denied
          : PermissionOutcome.unknown;
  }
}

/// Raises the system prompt, once per process, and records that it happened.
///
/// Called by the explainer dialog rather than by a file operation, which is
/// the "ask in context, never at launch" half of #351: MANAGE_EXTERNAL_STORAGE
/// does not raise a dialog, it drops the user into a settings list of every
/// installed app, and unannounced that is bewildering.
///
/// Returns the outcome so the caller can report it immediately rather than
/// waiting for the resume re-read.
Future<PermissionOutcome> askForAndroidStoragePermission() async {
  if (!io.Platform.isAndroid) return PermissionOutcome.unavailable;
  final permission = await _resolvePermission();
  if (permission == null) return PermissionOutcome.unknown;
  final granted = await _requestOnce(permission);
  if (granted == null) return PermissionOutcome.unknown;
  final outcome = granted
      ? PermissionOutcome.granted
      : PermissionOutcome.denied;
  _report(outcome);
  return outcome;
}

/// Where the answer goes. Set once by the composition root.
///
/// A sink rather than an import of `PermissionCenter`: this file is reached
/// from `paths.dart`, which the home-screen widget's isolate and a dozen unit
/// tests also reach, and none of them has a centre to notify. A callback that
/// nobody set is a no-op, so those paths keep working unchanged.
void Function(PermissionOutcome outcome)? _onOutcome;

/// Installs the sink. Called from the composition root, before the first file
/// operation.
void reportStoragePermissionTo(void Function(PermissionOutcome) onOutcome) {
  _onOutcome = onOutcome;
}

void _report(PermissionOutcome outcome) => _onOutcome?.call(outcome);

Future<bool?>? _prompt;
Future<Permission>? _storagePermission;

/// Clears this file's process-wide state.
///
/// These are library statics with no owner, which is the shape CLAUDE.md
/// devotes an anti-pattern to: `LogService`'s line fold is a static nothing
/// resets, and a test that logged a body an earlier test logged read as broken
/// wiring. `test/flutter_test_config.dart` calls this for the same reason it
/// resets that fold.
@visibleForTesting
void debugResetStoragePermissionState() {
  _prompt = null;
  _storagePermission = null;
  _onOutcome = null;
  storageAskedStore.debugReset();
}

/// Resolves which permission applies, or null when that could not be read.
///
/// A rejected future is **not** memoised. Cached, it latched the probe for the
/// life of the process: every resume awaited the same rejection, storage
/// stayed unknown, and no notice could ever be drawn again.
Future<Permission?> _resolvePermission() async {
  try {
    return await (_storagePermission ??= _readPermission());
  } catch (e, st) {
    _storagePermission = null;
    LogService.caught(
      '[Storage] could not read the Android version, so the storage '
      'permission is unknown: ${LogService.describe(e, st)}',
    );
    return null;
  }
}

Future<Permission> _readPermission() async {
  final android = await DeviceInfoPlugin().androidInfo;
  return android.version.sdkInt >= 30
      ? Permission.manageExternalStorage
      : Permission.storage;
}

/// Whether [permission] is granted, or null when the status could not be read.
///
/// Three-valued on purpose. `catch (_) => false` folded a failed read into
/// "not granted", and the caller then reported that as a refusal.
Future<bool?> _isGranted(Permission permission) async {
  try {
    return (await permission.status).isGranted;
  } catch (e, st) {
    LogService.caught(
      '[Storage] permission status unreadable: ${LogService.describe(e, st)}',
    );
    return null;
  }
}

/// Asks once, answering null when the ask could not be made.
///
/// Null rather than false for the throw: the plugin refuses a request while
/// another one is running, and the app fires several at startup. Reported as
/// `false` that became a denial the user never made.
Future<bool?> _requestOnce(Permission permission) async {
  try {
    final granted = (await permission.request()).isGranted;
    // Recorded after the ask returned, so a prompt that never reached the
    // user does not leave this install believing it was shown one.
    await storageAskedStore.markAsked();
    return granted;
  } catch (e, st) {
    _prompt = null;
    LogService.caught(
      '[Storage] could not raise the permission prompt: '
      '${LogService.describe(e, st)}',
    );
    return null;
  }
}
