import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../storage/permissions.dart';
import 'center.dart';
import 'permission.dart';

/// How to re-read each permission, for the composition root to hand to
/// [PermissionCenter].
///
/// Here rather than in `center.dart` so that file names no plugin: the
/// probes sit behind four packages directly (five counting `device_info_plus`
/// behind the storage one), and a centre that imported all
/// of them could not be constructed in a unit test at all. This file is the
/// one place the two halves meet.
///
/// Every probe reads and none of them asks. That is the rule the resume
/// re-read depends on: a probe that raised a prompt would re-ask on every
/// return to the app, and on Android's all-files-access screen that means
/// bouncing the user straight back out of the app they just came back to.
Map<AppPermission, PermissionProbe> buildPermissionProbes(
  FlipperClient client,
) {
  return {
    AppPermission.storage: readAndroidStoragePermission,
    AppPermission.bluetooth: () => _bluetooth(client),
    AppPermission.pushNotifications: _pushNotifications,
    AppPermission.serviceNotification: _serviceNotification,
    AppPermission.serviceLocation: _serviceLocation,
  };
}

/// Maps the transport's answer onto the app's.
///
/// One function and not two. This mapping existed twice - here and in the
/// device picker - character for character, which is the clearest reuse miss
/// the first draft of #351 had: both copies are exhaustive, so a *new*
/// `BleAccess` value breaks both, but a changed *decision* changes one, and
/// then the picker and the resume probe disagree about whether a switched-off
/// adapter is a denial.
///
/// `off` reports as granted, which looks wrong and is not: an adapter that is
/// merely switched off answered `poweredOff` rather than `unauthorized`, so
/// the authorisation is in place and there is nothing for the user to grant.
/// `FlipperConnectErrorKind.bluetoothUnavailable` is the bucket for that - and
/// for an unauthorised adapter too, since `classifyConnectError` routes
/// `bluetoothunauthorized`, `accessdenied` and `not authorized` into the same
/// kind, whose one sentence covers both. So this is not a case the classifier
/// has no answer for; it is one it answers better, at the moment of a failed
/// connect, than a standing notice could.
PermissionOutcome outcomeOfBleAccess(BleAccess access) {
  return switch (access) {
    BleAccess.granted => PermissionOutcome.granted,
    BleAccess.denied => PermissionOutcome.denied,
    BleAccess.off => PermissionOutcome.granted,
    BleAccess.unsupported => PermissionOutcome.unavailable,
    BleAccess.unknown => PermissionOutcome.unknown,
  };
}

/// Maps the foreground-service plugin's answer onto the app's.
///
/// Shared with `foreground_service.dart`, which folded every non-granted value
/// into `denied` with a ternary - recording a refusal the user was never
/// offered the chance to make on the `widgetMain()` path, where by that file's
/// own comment there is no activity to prompt from.
PermissionOutcome outcomeOfNotificationPermission(
  NotificationPermission permission,
) {
  return switch (permission) {
    NotificationPermission.granted => PermissionOutcome.granted,
    NotificationPermission.denied => PermissionOutcome.denied,
    // The plugin spells this one in snake case. Both denials read the same
    // here: `PermissionOutcome` has no `permanentlyDenied`, because the route
    // out of each is the same settings page.
    NotificationPermission.permanently_denied => PermissionOutcome.denied,
  };
}

Future<PermissionOutcome> _bluetooth(FlipperClient client) async {
  return outcomeOfBleAccess(await client.readBleAccess());
}

/// Reads `POST_NOTIFICATIONS` as push cares about it.
///
/// `permission_handler` rather than `FirebaseMessaging.getNotificationSettings`
/// deliberately: the whole point of this probe is to tell a denied permission
/// apart from a Firebase that never came up, and asking Firebase would
/// conflate them again — which is exactly how Settings → Push came to claim
/// "this build is not signed for push" for a denial.
Future<PermissionOutcome> _pushNotifications() async {
  // Desktop has no runtime notification permission at all, which is not a
  // denial. Android 12 and below have none either, but `permission_handler`
  // reports granted there, so no version check is needed to get that right.
  if (!io.Platform.isAndroid && !io.Platform.isIOS) {
    return PermissionOutcome.unavailable;
  }
  final status = await Permission.notification.status;
  if (status.isGranted) return PermissionOutcome.granted;
  // `permanentlyDenied` is the only unambiguous refusal this plugin reports.
  if (status.isPermanentlyDenied) return PermissionOutcome.denied;
  // Plain `denied` is deliberately *not* a refusal here, and treating it as
  // one would have shipped a notice at a user who refused nothing:
  // `permission_handler` maps iOS's `UNAuthorizationStatusNotDetermined` to
  // `PermissionStatus.denied` (NotificationPermissionStrategy.m), and Android
  // answers `denied` for a runtime permission nobody has asked for yet. So on
  // a fresh install this status cannot tell "never asked" from "said no", and
  // guessing is the wrong-cause failure #351 is about.
  //
  // Nothing is lost by it. `PushService.start` records the real answer when it
  // asks, and `PermissionCenter.record` refuses to downgrade a known outcome
  // to `unknown` - so the ask establishes a denial and this read cannot talk
  // over it.
  //
  // `restricted`, `limited`, `provisional`: not refusals either, and none of
  // them stops a notification arriving on the platforms this app ships to.
  return PermissionOutcome.unknown;
}

/// Reads the notification permission the foreground service needs.
///
/// The plugin's own check rather than the one above, although Android has a
/// single permission behind both: the service asks through
/// `FlutterForegroundTask`, and its answer is what decides whether the
/// ongoing notification — and so the background link — can exist at all.
Future<PermissionOutcome> _serviceNotification() async {
  if (!io.Platform.isAndroid) return PermissionOutcome.unavailable;
  final permission = await FlutterForegroundTask.checkNotificationPermission();
  return outcomeOfNotificationPermission(permission);
}

/// Reads the location permission the foreground service declares its type
/// from.
///
/// Not the same question as the map's. The map needs a fix; the service needs
/// only the standing grant, so that `ForegroundServiceTypes.location` can go
/// on the service it starts. `foreground_service.dart` asked this and threw
/// the answer away in a `catch (_)`.
Future<PermissionOutcome> _serviceLocation() async {
  if (!io.Platform.isAndroid) return PermissionOutcome.unavailable;
  return outcomeOfLocationPermission(await Geolocator.checkPermission());
}

/// Maps Geolocator's answer onto the app's.
///
/// Shared with `foreground_service.dart`, and extracted because the first new
/// call site broke the rule this comment states. That file folded every
/// non-granted value into `denied` with a ternary — and nothing in the app
/// ever *asks* for the foreground service's location permission, so on a
/// fresh Android install that recorded a refusal the user was never offered
/// and drew an un-actionable notice about a capability they never declined.
///
/// `deniedForever` is the unambiguous refusal. Plain `denied` is also what
/// Geolocator answers for a permission nobody has asked for, so it cannot
/// tell "never asked" from "said no" and is reported as neither — the same
/// reasoning as the push probe above. Having it in one function makes that a
/// property of the mapping rather than a convention each call site may break.
PermissionOutcome outcomeOfLocationPermission(LocationPermission permission) {
  return switch (permission) {
    LocationPermission.always => PermissionOutcome.granted,
    LocationPermission.whileInUse => PermissionOutcome.granted,
    LocationPermission.deniedForever => PermissionOutcome.denied,
    LocationPermission.denied => PermissionOutcome.unknown,
    LocationPermission.unableToDetermine => PermissionOutcome.unknown,
  };
}
