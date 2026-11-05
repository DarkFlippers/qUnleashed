/// The permissions this app asks the user for, and the only list of them.
///
/// One enum rather than a type per permission (`PermissionCenter` keys off it,
/// [AppPermission.tier] classifies it, and one widget draws all of them),
/// because the five sites #351 found had nothing in common except that each
/// had invented its own way of dropping the answer on the floor.
///
/// Not every platform permission is here. Battery optimisation is asked for
/// in `foreground_service.dart` and its outcome is ignored deliberately — an
/// engine a home-screen widget started has no activity to prompt from, and
/// the comment there says so. Adding it would mean a notice nobody can act
/// on. Map location is not here either: `archive/map/controller.dart` already
/// holds the complete pattern in its own state, scoped to the one screen that
/// uses it, and moving it here would buy nothing.
enum AppPermission {
  /// Android's `MANAGE_EXTERNAL_STORAGE` (API 30+) or `WRITE_EXTERNAL_STORAGE`
  /// (API 29), which is what reaches `Documents/qUnleashed`.
  ///
  /// The root cause rather than one of five: `paths.dart` is the single call
  /// site, every storage path in the app hangs off it, and the answer never
  /// left `storage/permissions.dart`.
  storage,

  /// Scanning and connecting over Bluetooth — `BLUETOOTH_SCAN` on Android,
  /// the CoreBluetooth authorisation on iOS.
  bluetooth,

  /// `POST_NOTIFICATIONS` as Firebase Messaging asks for it, for push.
  pushNotifications,

  /// `POST_NOTIFICATIONS` as the foreground service asks for it, for the
  /// ongoing notification the background link needs in order to exist.
  ///
  /// Separate from [pushNotifications] although Android has one permission
  /// behind both: the consequences differ and so do the sentences. Losing
  /// push costs release announcements; losing this kills the link when the
  /// screen sleeps. A user who denied it needs to be told the second thing.
  serviceNotification,

  /// Location, as the foreground service asks for it so the service may
  /// declare `ForegroundServiceTypes.location`.
  serviceLocation;

  /// Which tier this permission falls in, which decides what the user is
  /// shown and how insistently.
  ///
  /// The question that decides it, from #351: without this permission, is
  /// there another route to the app's core job — reaching a Flipper?
  ///
  /// [iosBluetoothIsBlocking] is the one place the answer depends on the
  /// platform. On iOS there is no second transport — `transport/usb/ios.dart`
  /// throws `UnsupportedError` — so a Bluetooth denial leaves every screen
  /// behind it as furniture. On Android USB-OTG still works, which makes the
  /// same denial a feature gate. Passed in rather than read from
  /// `Platform.isIOS` here so this stays a pure function and a test can ask
  /// for both answers.
  PermissionTier tier({required bool iosBluetoothIsBlocking}) {
    return switch (this) {
      AppPermission.storage => PermissionTier.featureGate,
      AppPermission.bluetooth =>
        iosBluetoothIsBlocking
            ? PermissionTier.blocking
            : PermissionTier.featureGate,
      AppPermission.pushNotifications => PermissionTier.informOnce,
      AppPermission.serviceNotification => PermissionTier.informOnce,
      AppPermission.serviceLocation => PermissionTier.informOnce,
    };
  }

  /// The key a dismissal is stored under.
  ///
  /// Spelled out rather than derived from [name], so renaming a value in this
  /// enum cannot silently un-dismiss a notice on every install that had
  /// already dismissed it.
  String get dismissalKey => switch (this) {
    AppPermission.storage => 'permission.dismissed.storage',
    AppPermission.bluetooth => 'permission.dismissed.bluetooth',
    AppPermission.pushNotifications => 'permission.dismissed.push',
    AppPermission.serviceNotification => 'permission.dismissed.fgs_notify',
    AppPermission.serviceLocation => 'permission.dismissed.fgs_location',
  };
}

/// How much of the app a denial takes away, which is what decides the surface.
///
/// The tiers are #351's, and the names are the question they answer rather
/// than how bad they feel. A tier is a fact about the app's capabilities; a
/// severity is how it is drawn.
enum PermissionTier {
  /// No route at all. Every screen behind the prompt is furniture, so the
  /// prompt is the screen.
  blocking,

  /// The app runs; the affected surface refuses and says why.
  featureGate,

  /// An enhancement or a silent capability downgrade. Nothing the user asked
  /// for fails, so it never nags: this is the only tier whose notices can
  /// be dismissed, and `PermissionNotice.dismissible` is what decides
  /// whether a given surface offers it.
  informOnce,
}

/// What the platform last answered about one permission.
///
/// Four values and no `permanentlyDenied`. Every permission in
/// [AppPermission] is reversible only in system settings — Android's
/// MANAGE_EXTERNAL_STORAGE opens a settings list rather than a dialog, and a
/// second ask for the others is refused once the user has said no twice — so
/// the route out is the same page either way and a fifth value would not
/// change a single sentence or button. `archive/map/controller.dart` keeps
/// the distinction because location there has two different settings pages
/// behind it.
enum PermissionOutcome {
  /// Never asked, or the read failed. **Not** a denial: a notice raised on a
  /// guess is the wrong-cause failure #351 is about, so this draws nothing.
  unknown,

  /// Usable. Nothing to tell the user.
  granted,

  /// The user said no. The one value that draws a notice.
  denied,

  /// There is nothing to grant on this platform — no radio, no Play Services,
  /// a desktop build with no runtime permission model. Draws nothing, and
  /// must never be reported as a denial.
  unavailable;

  /// Whether this outcome is worth putting in front of the user.
  ///
  /// The single predicate every surface asks, so that "unknown and
  /// unavailable are silent" is decided once rather than at five call sites —
  /// which is how `push_service.dart` came to assert a denied permission as
  /// an unsigned build.
  bool get warrantsNotice => this == PermissionOutcome.denied;
}
