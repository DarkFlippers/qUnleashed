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
  static const String _noticeShownKey = 'diagnostics.notice_shown';

  /// On, and the direction of that default is the decision rather than a
  /// convenience. §1: an opt-in crash reporter on a tool with this audience
  /// collects from a single-digit share of installs, which is not enough
  /// reports to find a fault in a BLE stack on a handset nobody on the
  /// project owns.
  static const bool _defaultShareLogs = true;

  bool _shareLogs = _defaultShareLogs;
  bool _noticeShown = false;

  bool get shareLogs => _shareLogs;

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
    _noticeShown = reader.or(_noticeShownKey, false);
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
    _noticeShown = false;
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
