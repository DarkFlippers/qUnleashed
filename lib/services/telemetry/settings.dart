import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../logging.dart';
import '../prefs_reader.dart';
import '../settings/persist.dart';
import '../settings/store.dart';

/// Whether the app shares what fails with the people who wrote it.
///
/// One switch, on by default, sending automatically -
/// [ADR 0013 §1](../../../docs/adr/0013-observability-with-sentry.md). Not a
/// consent record: reporting is already running while the notice that explains
/// it is on screen, which is what makes it a notice and not a gate.
///
/// Constructed rather than a `static final instance`, unlike the three
/// preference stores it is a sibling of. Those are the legacy shape CLAUDE.md
/// names, and the switch has exactly one reader in `_initCore` plus one in the
/// settings screen, so passing it is cheap here where retrofitting the other
/// three would be a task of its own.
class DiagnosticsSettings extends PrefsBackedSettings {
  static const String _shareLogsKey = 'diagnostics.share_logs';
  static const String _replayKey = 'diagnostics.share_replay';
  static const String _noticeShownKey = 'diagnostics.notice_shown';

  /// On, and the direction of that default is the decision rather than a
  /// convenience. §1: an opt-in crash reporter on a tool with this audience
  /// collects from a single-digit share of installs, which is not enough
  /// reports to find a fault in a BLE stack on a handset nobody on the
  /// project owns.
  static const bool _defaultShareLogs = true;

  /// Named for the same reason as its sibling, and pointing the other way:
  /// [onLoadFailed] and [noticeShown] each argue why. Written as a literal in
  /// three places before, which is how two defaults that must differ come to
  /// agree by accident.
  static const bool _defaultNoticeShown = false;

  /// On, which is §1's decision and not an oversight - and it is the masks in
  /// `options.dart` that make it defensible, because of what "errors only"
  /// does and does not mean.
  ///
  /// A replay is only **sent** when something already failed. It is
  /// **recorded** continuously: `onErrorSampleRate` above zero starts the
  /// native recorder at init, and the frames go into a rolling buffer that is
  /// discarded unless an error arrives. So this default is not the same trade
  /// [_defaultShareLogs] makes - that one costs nothing until a failure, this
  /// one costs a masked screen capture all the time the app is up on Android
  /// and iOS.
  ///
  /// What makes it still the right default is that the masking runs at capture
  /// time, so the buffer never holds card bytes, a pulse plot or the device
  /// screen in the first place; the alternative is too few reports to find a
  /// fault on a handset nobody on the project owns. The user is told this in
  /// `diagnosticsReplaySubtitle` rather than left to infer it from the word
  /// "errors".
  static const bool _defaultShareReplay = true;

  /// Whether replay can record on this platform at all.
  ///
  /// `ReplayIntegration` gates on `supportsReplay`, which is true only in the
  /// Java binding and, for Cocoa, only on iOS - so the four desktop targets
  /// and web record nothing whatever the rates say. The same shape as
  /// `HomeWidgetService.supported` and `PushService.supported`, and here
  /// rather than in `Telemetry` because the Diagnostics screen needs it too
  /// and already holds this object.
  ///
  /// Two things read it: the screen, to leave the row out instead of offering
  /// a switch that does nothing, and `Telemetry._reconcile`, to not tear the
  /// SDK down for a rate nothing will read.
  /// [defaultTargetPlatform] and not `Platform.isAndroid`, which is what the
  /// rest of the app reaches for: a widget test runs on the host, so `dart:io`
  /// would answer Windows and hide the row from the tests that cover it. This
  /// one is overridable through `debugDefaultTargetPlatformOverride`, which is
  /// how `diagnostics_screen_test.dart` pins a phone. It is also the right
  /// answer on web, where `Platform` throws.
  static bool get replaySupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool _shareLogs = _defaultShareLogs;
  bool _shareReplay = _defaultShareReplay;
  bool _noticeShown = _defaultNoticeShown;

  bool get shareLogs => _shareLogs;

  /// Whether a replay of the seconds before a failure goes with it.
  ///
  /// §1's "second switch of its own", and subordinate to [shareLogs] rather
  /// than independent of it: with sharing off the SDK is not running, so
  /// nothing is captured either, and there would be nothing for a replay to be
  /// attached to in any case. The Diagnostics screen leaves this row out in
  /// that state rather than showing a control that does nothing.
  ///
  /// On, this is what the user is consenting to: a continuously recorded,
  /// masked buffer of the screen, uploaded only when something fails. See
  /// [_defaultShareReplay].
  bool get shareReplay => _shareReplay;

  /// Whether §1's one-time notice has been put in front of this user.
  ///
  /// False on a fresh install, and false for everyone already running the app
  /// when this shipped - which is exactly §1's "once more for existing users
  /// after the update that carries this", with no second flag and no version
  /// comparison. The key is written the first time the notice is raised and
  /// never read again after that.
  ///
  /// Defaults to false, so a store that will not open means the notice is
  /// shown again rather than skipped. The direction is deliberate and it is
  /// the opposite of [shareLogs]'s: being told twice is a nuisance, never
  /// being told is the failure that matters.
  bool get noticeShown => _noticeShown;

  @override
  void readFrom(PrefsReader reader) {
    _shareLogs = reader.or(_shareLogsKey, _defaultShareLogs);
    _shareReplay = reader.or(_replayKey, _defaultShareReplay);
    _noticeShown = reader.or(_noticeShownKey, _defaultNoticeShown);
    reader.report('[Diagnostics]');
  }

  /// **Reports rather than going quiet**, which is the opposite of what the
  /// consent shape this reversed would have needed.
  ///
  /// [loaded] stays false and [shareLogs] stays at its initialiser, so a
  /// preference store that will not open leaves reporting on. Under consent a
  /// failed read had to mean "no" — there was no answer, and acting without
  /// one is the thing consent forbids. On by default inverts that: the
  /// setting the user never changed is the one that was already in force, and
  /// a broken store is not them turning it off.
  ///
  /// So nothing downstream gates on [loaded]. `Telemetry.start` reads
  /// [shareLogs] directly for that reason.
  @override
  void onLoadFailed(Object error, StackTrace stack) {
    LogService.warn(
      '[Diagnostics] load failed, reporting stays on: '
      '${LogService.describe(error, stack)}',
    );
  }

  @override
  void resetFields() {
    _shareLogs = _defaultShareLogs;
    _shareReplay = _defaultShareReplay;
    _noticeShown = _defaultNoticeShown;
  }

  /// Applies the choice to this object and persists it, in that order.
  ///
  /// Listeners fire before the write lands, which is deliberate and is what
  /// `persistSetting` exists for: the switch stays where the user put it and
  /// `Telemetry` starts or stops from the listener, whether or not the disk
  /// agreed. A write that does not stick is one line in the log, #120.
  ///
  /// Starting and stopping the SDK is **not** done here. `Telemetry` listens,
  /// so the dependency runs one way - telemetry knows about the switch, the
  /// switch knows nothing about Sentry - and so this stays testable without
  /// the SDK.
  Future<void> setShareLogs(bool value) async {
    if (value == _shareLogs) return;
    _shareLogs = value;
    notifyListeners();
    await persistSetting(
      'share logs with developers',
      (prefs) => prefs.setBool(_shareLogsKey, value),
    );
  }

  /// Applies the replay choice to this object and persists it.
  ///
  /// The same shape as [setShareLogs], and for the same reason - but what
  /// `Telemetry` does with the notification differs: there is no app-facing
  /// pause API in this major, so a replay sample rate can only be changed by
  /// bringing the SDK down and up again. `Telemetry._reconcile` owns that;
  /// this still knows nothing about Sentry.
  Future<void> setShareReplay(bool value) async {
    if (value == _shareReplay) return;
    _shareReplay = value;
    notifyListeners();
    await persistSetting(
      'send a replay with a failure',
      (prefs) => prefs.setBool(_replayKey, value),
    );
  }

  /// Records that the notice has been seen, so it never appears again.
  ///
  /// Called when it is raised rather than when it is answered. §1: the app is
  /// usable behind it and dismissing it is the same as **Got it**, so there is
  /// no answer to wait for - and a notice that only counts as shown once
  /// somebody taps a button is a notice that comes back forever for anyone who
  /// swipes it away.
  ///
  /// No listeners are notified. Nothing on screen is drawn from this, and the
  /// one thing that reads it has already read it by the time this runs -
  /// notifying would rebuild the tree underneath a sheet that is opening.
  Future<void> markNoticeShown() async {
    if (_noticeShown) return;
    _noticeShown = true;
    await persistSetting(
      'the diagnostics notice has been shown',
      (prefs) => prefs.setBool(_noticeShownKey, true),
    );
  }
}
