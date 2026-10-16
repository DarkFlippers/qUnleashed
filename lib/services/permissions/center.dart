import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging.dart';
import '../prefs_reader.dart';
import '../settings/persist.dart';
import 'permission.dart';

/// Reads one permission's current state without raising a prompt.
///
/// Returning [PermissionOutcome.unknown] rather than throwing is the contract:
/// this runs on every resume, and a probe that rejects there would either
/// strand the re-read or arrive in the log as an unlabelled `[uncaught]`.
/// [PermissionCenter.refresh] catches anyway, because a contract a plugin can
/// break is not one.
typedef PermissionProbe = Future<PermissionOutcome> Function();

/// The app's one record of which permissions were granted and which notices
/// the user has put away.
///
/// Why this exists at all: five permissions were requested, denied, and then
/// silently absorbed, so each feature failed in its own unrelated-looking way
/// and the user was told nothing or told the wrong cause (#351). The answers
/// now land here, and every surface reads them from the same place.
///
/// A `ChangeNotifier` handed down through `PermissionScope`, which is
/// `DiagnosticsScope`'s shape for `DiagnosticsSettings` and `DeviceScope`'s
/// for the device controller — built once at the composition root and passed
/// in rather than reached for through a static
/// ([0002](../../../docs/adr/0002-dependencies-are-passed-in.md)).
///
/// Built in `_initCore` and not in `_runApp`, because the foreground service
/// records two of these five and it comes up in `widgetMain()`, where nothing
/// from `_runApp` exists — CLAUDE.md's standing warning. Constructing this
/// touches no disk and no platform channel, so it is safe on a path that must
/// never throw.
class PermissionCenter extends ChangeNotifier with WidgetsBindingObserver {
  PermissionCenter({
    Map<AppPermission, PermissionProbe> probes = const {},
    bool? bluetoothIsTheOnlyTransport,
  }) : _probes = Map.unmodifiable(probes),
       _bluetoothIsTheOnlyTransport =
           bluetoothIsTheOnlyTransport ?? io.Platform.isIOS;

  /// How to re-read each permission, injected by the composition root.
  ///
  /// Injected rather than imported so this file names no plugin: the probes
  /// sit behind four packages, and a centre that imported all of them could
  /// not be built in a unit test at all. A permission with no probe simply
  /// never refreshes — it keeps whatever [record] last said, which is correct
  /// for one the app only ever learns about by asking.
  final Map<AppPermission, PermissionProbe> _probes;

  /// Whether a Bluetooth denial takes the whole app away.
  ///
  /// True on iOS alone, where `transport/usb/ios.dart` throws
  /// `UnsupportedError` and there is no second transport. Injectable because
  /// the one decision that hangs off it blacks out the entire app, and a
  /// `Platform.isIOS` read inside it would make both branches of that
  /// untestable — the mistake [AppPermission.tier] was written to avoid and
  /// which its first caller then made anyway.
  final bool _bluetoothIsTheOnlyTransport;

  final Map<AppPermission, PermissionOutcome> _outcomes = {};
  final Set<AppPermission> _dismissed = {};

  Future<void>? _load;
  Future<void>? _refresh;
  bool _refreshAgain = false;
  bool _installed = false;
  bool _everPaused = false;

  /// What the platform last said about [permission].
  ///
  /// [PermissionOutcome.unknown] until something asks, which is why every
  /// surface draws nothing for it.
  PermissionOutcome outcomeOf(AppPermission permission) =>
      _outcomes[permission] ?? PermissionOutcome.unknown;

  /// Whether [permission] is denied **and** the user has not put the notice
  /// away.
  ///
  /// The question a *dismissible* notice asks. Anything that suppresses a
  /// competing explanation must ask [outcomeOf] instead: a dismissal is a
  /// statement about the notice, never about the cause, and
  /// `pages/option/pages/push.dart` shipped the wrong one of these for a day
  /// — one tap put "this build is not signed for push" back in front of a
  /// user whose permission was still provably refused.
  bool shouldNotice(AppPermission permission) =>
      outcomeOf(permission).warrantsNotice && !isDismissed(permission);

  bool isDismissed(AppPermission permission) => _dismissed.contains(permission);

  /// Whether [permission] is refused, regardless of any dismissal.
  ///
  /// The question anything suppressing a competing explanation asks, and the
  /// sibling of [shouldNotice] — three surfaces were open-coding
  /// `outcomeOf(x).warrantsNotice`, and one of them reached for
  /// [shouldNotice] instead and put a false sentence back on screen. Naming
  /// both makes the choice a word rather than an expression.
  bool isDenied(AppPermission permission) =>
      outcomeOf(permission).warrantsNotice;

  /// [AppPermission.tier], with this platform's answer filled in.
  PermissionTier tierOf(AppPermission permission) =>
      permission.tier(iosBluetoothIsBlocking: _bluetoothIsTheOnlyTransport);

  /// Writes down what a request or a status read answered.
  ///
  /// Idempotent and quiet when nothing changed: this is called from the
  /// storage path, which runs on every file operation, and a notify per
  /// `appDocumentsDirectory()` would rebuild every listening surface on a
  /// directory walk. `DeviceScope`'s five-second battery poll rebuilding a
  /// subtree twelve times a minute is the shape (#135/#136).
  ///
  /// **A known outcome is never downgraded to [PermissionOutcome.unknown].**
  /// Forgetting a denial already proved is how a gate disappears and the
  /// feature behind it fails unexplained all over again — the original bug,
  /// reintroduced by its own fix. It is a real path, not a hypothetical: the
  /// only unambiguous refusal `permission_handler` reports is
  /// `permanentlyDenied`, because both platforms answer `denied` for a
  /// permission nobody has asked for yet. So the ask records the truth and the
  /// resume probe must not talk over it.
  void record(AppPermission permission, PermissionOutcome outcome) {
    if (outcome == PermissionOutcome.unknown &&
        _outcomes.containsKey(permission)) {
      return;
    }
    if (_outcomes[permission] == outcome) return;
    _outcomes[permission] = outcome;
    if (outcome == PermissionOutcome.granted) _clearDismissal(permission);
    notifyListeners();
  }

  /// Puts a notice away for good, on this install.
  ///
  /// Per install and not per process. All of these are reversible only in
  /// system settings, so a dismissal that lapsed at the next launch would ask
  /// again about something the user had already decided — which is what
  /// `storage/permissions.dart`'s `_prompt ??=` does today, one process at a
  /// time.
  ///
  /// Applied to what is on screen first and persisted after, like every other
  /// setting in this app. `persistSetting` never throws and says so in the log
  /// when the store refuses the write.
  Future<void> dismiss(AppPermission permission) async {
    if (!_dismissed.add(permission)) return;
    notifyListeners();
    await persistSetting(
      'dismissed permission notice for ${permission.name}',
      (prefs) => prefs.setBool(permission.dismissalKey, true),
    );
  }

  /// Forgets a dismissal, in memory and on disk.
  ///
  /// Both halves, which is the point. Clearing only the in-memory copy left
  /// the stored `true` behind, so the next launch read it back and a *fresh*
  /// denial was silenced by a dismissal the user made before they granted the
  /// permission. Harmless only for as long as nothing called [load].
  void _clearDismissal(AppPermission permission) {
    _dismissed.remove(permission);
    // Unconditional, and that is the whole point. Guarded on the in-memory
    // set having held it, a grant that landed before [load] had read the
    // store left the stored `true` behind - and then `load` read it back and
    // re-added a dismissal the user made *before* they granted the
    // permission, so the next revocation was silenced. At startup that race
    // was live: `bootstrapAmbientServices` started the read and the probes
    // together.
    unawaited(
      persistSetting(
        'cleared dismissed permission notice for ${permission.name}',
        (prefs) => prefs.remove(permission.dismissalKey),
      ),
    );
  }

  /// Reads the stored dismissals. Memoised, and never throws.
  ///
  /// Memoised because the alternative is a disk read per build of every
  /// notice, which is CLAUDE.md's first anti-pattern. Started from
  /// `bootstrapAmbientServices` rather than awaited in `build` for the same
  /// reason; a notice that appears a frame late is correct, and one that
  /// re-reads the store on every frame is not.
  Future<void> load() => _load ??= _loadOnce();

  Future<void> _loadOnce() async {
    try {
      // `PrefsReader` and not `getBool(...) ?? false`: five keys in a loop is
      // the opening case of its own doc — one stored value of the wrong type
      // would otherwise throw out of the loop and cost every key after it,
      // reported as "dismissals unreadable" with the offending key never
      // named. `report` says once what the whole read ignored.
      final reader = PrefsReader(await SharedPreferences.getInstance());
      var changed = false;
      for (final permission in AppPermission.values) {
        if (reader.or<bool>(permission.dismissalKey, false)) {
          changed |= _dismissed.add(permission);
        }
      }
      reader.report('[Permissions]');
      if (changed) notifyListeners();
    } catch (e, st) {
      // `caught` and not `info`: a store that will not open means every
      // dismissible notice comes back after the user dismissed it, for the
      // life of the install, and nothing else would say so. Not `warn` — the
      // app works, and the user is being told something true, just more often
      // than they agreed to.
      LogService.caught(
        '[Permissions] dismissals unreadable, notices will return: '
        '${LogService.describe(e, st)}',
      );
    }
  }

  /// Starts watching for the user coming back from system settings.
  ///
  /// Called from `bootstrapAmbientServices` and so only on the path that has
  /// a UI. `widgetMain()`'s isolate records outcomes but has no screen to
  /// update, and a bare unit test has no `WidgetsBinding` to add an observer
  /// to — `localization/controller.dart` is the file that learned that one.
  void install() {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    if (_installed) {
      WidgetsBinding.instance.removeObserver(this);
      // Reset, so this object cannot be left claiming an observer it no longer
      // has. It outlives the app in practice; costing one line to not be a
      // trap is still worth it.
      _installed = false;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _everPaused = true;
      return;
    }
    // Only a resume that follows a pause. Android announces `resumed` shortly
    // after the engine attaches, and because `refresh` queues rather than
    // drops a concurrent call, that landed on top of the explicit startup read
    // and ran all the probes a second time at launch. The explicit read stays:
    // Flutter does not re-announce the initial state to an observer added
    // later, so the lifecycle event alone cannot be relied on.
    if (!_everPaused) return;
    // Not awaited and not bare-unawaited. `guarded` is unavailable here
    // without a circular import, so the catch is inside `refresh` itself and
    // this call cannot reject — #23's rule is about futures that can.
    refresh();
  }

  /// Re-reads every permission that has a probe.
  ///
  /// This is the half of #351 the widget cannot supply: all five are
  /// reversible only in system settings, so the app has to notice the user
  /// came back having granted one, and clear the notice without a restart. The
  /// iOS blocking screen depends on it absolutely — it promises "Checked again
  /// when you come back to the app", and it is the whole app.
  ///
  /// Reads rather than asks. A probe that raised a prompt would re-ask on
  /// every resume, which on Android's all-files-access screen means bouncing
  /// the user straight back out of the app they just returned to.
  ///
  /// A call arriving while a run is in flight is **queued, not dropped**. Two
  /// resumes in quick succession — a permission sheet closing is one — must
  /// not run every probe twice over, but the second one may be the resume that
  /// comes after the grant, and dropping it leaves the notice up until the
  /// next one.
  Future<void> refresh() async {
    final pending = _refresh;
    if (pending != null) {
      _refreshAgain = true;
      return pending;
    }
    final run = _drain();
    _refresh = run;
    try {
      await run;
    } finally {
      // Cleared whatever happened, or `refresh` becomes a once-per-process
      // operation and every later resume returns this same finished future.
      // A mutation that drops this `finally` leaves the suite green, so
      // `permission_notice_test.dart` counts probe calls across two refreshes.
      _refresh = null;
    }
  }

  Future<void> _drain() async {
    // `do/while` rather than a first pass plus a loop: one call site, and the
    // flag is cleared *before* each pass. Cleared only inside the loop, a
    // `refresh()` arriving in the window between `await run` resolving and
    // the `finally` nulling `_refresh` set the flag, got the finished future
    // back, and left a `true` behind for the next run to probe on twice.
    do {
      _refreshAgain = false;
      await _refreshOnce();
    } while (_refreshAgain);
  }

  /// Runs every probe, together rather than one after another.
  ///
  /// They are unrelated plugin round-trips behind four packages, nothing in
  /// one depends on another, and this runs on resume — the tightest frame
  /// budget the app has. Neither reason to serialise them holds: none of them
  /// asks for anything, so there is no prompt to queue, and `record` is
  /// per-permission with no cross-permission effect, so the writes stay
  /// ordered by the isolate whatever order they arrive in.
  Future<void> _refreshOnce() => Future.wait(_probes.entries.map(_runProbe));

  Future<void> _runProbe(MapEntry<AppPermission, PermissionProbe> entry) async {
    final PermissionOutcome outcome;
    try {
      outcome = await entry.value();
    } catch (e, st) {
      // One probe failing must not strand the others, and the failure is
      // worth keeping: a permission that cannot be read is one whose notice
      // will not clear when the user grants it. The outcome is left as it was
      // rather than set to `unknown` — see [record].
      LogService.caught(
        '[Permissions] could not re-read ${entry.key.name}: '
        '${LogService.describe(e, st)}',
      );
      return;
    }
    // Outside the try on purpose. `record` calls `notifyListeners`
    // synchronously, so a throwing listener — or a notify after `dispose`,
    // which a refresh started from `bootstrap` can outlive into — used to be
    // caught and logged as "could not re-read X", a probe failure message for
    // a UI failure.
    record(entry.key, outcome);
  }
}
