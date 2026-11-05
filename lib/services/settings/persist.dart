import 'package:shared_preferences/shared_preferences.dart';

import '../logging.dart';

/// Writes one preference, and says so when it does not stick.
///
/// Never throws, which is the point. Every setter in this app applies the
/// user's choice to what is on screen first and persists it after, and most
/// of them are reached by tearing a `Future<void> Function(T)` off into a
/// `ValueChanged<T>` - so the future is discarded and a rejection arrives as
/// an unlabelled `[uncaught]` with no setting named. The control stays where
/// the user put it, and takes itself back at the next launch, hours later,
/// with nothing connecting the two.
///
/// One line in the log at a level that survives a release build is the whole
/// of what can be done about it: there is no retry that helps, and no surface
/// worth stopping the user for. `UpdateSettingsStore.remember` is where that
/// rule was first written down in this codebase. #120.
///
/// [what] names the setting, not the operation - a log that says "save
/// failed" five times over cannot tell a reader which control went back.
///
/// [write] returns the `Future<bool>` that `setString` and the rest hand back,
/// because a write can fail without throwing. On Android the legacy backend
/// returns `Editor.commit()` straight through, and that is `false` when the
/// write to persistent storage failed; Windows and Linux answer the same way
/// when the preferences file cannot be written. Apple cannot - its
/// implementation ends in a literal `return true`. `SharedPreferences`
/// updates its own cache before it asks the store, so a refused write reads
/// back correctly for the rest of the session and is gone at the next launch.
/// Typing [write] `Future<void>` discarded that `false` with no analyzer
/// warning - `void` is a top type, so a `Future<bool>` satisfies it silently -
/// and the promise above was kept only for the failures that throw. #313.
///
/// [write] performs **one** write. Two in one callback can only return one
/// answer, and `&&` would report a failure without saying which half - which
/// is the shape `ArchiveSortSettings` already refuses for its own pair.
///
/// Three places in `lib/` read this `false` without coming through here, each
/// because the level or the shape is its own:
///
///  * `MediaRemoteBridge._write` throws, because its caller is a dialog that
///    has to tell a failed save from a failed start.
///  * `KnownDevices._persist` logs at `error`: it is the one write that loses
///    something durable.
///  * `RemoteBuildService.ensureClientId` logs at `caught` and carries on,
///    and is a read and a conditional write rather than the one write below.
///
/// All three say `the store refused the write`, so one grep finds every
/// store that declined one. A setting the user flipped has no surface worth
/// more than that, which is what the rest of this comment is about.
///
/// Returns whether the setting stuck. Most callers ignore it and should: they
/// have applied the value to what is on screen already and have nowhere to put
/// a failure. It is there for the caller that has a second, durable copy to
/// keep in step - `HomeWidgetSettings` does not push a look to the launcher
/// that the next launch would take back.
Future<bool> persistSetting(
  String what,
  Future<bool> Function(SharedPreferences prefs) write,
) async {
  // Carried out rather than logged where it is found, so the line's one
  // literal has one home. Logging at each site meant two copies of
  // `did not persist` to keep in step, and the tests match on it.
  String reason;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (await write(prefs)) return true;
    reason = 'the store refused the write';
  } catch (e, st) {
    // The stack is what names the setter that passed a bad value; the
    // message alone names only the preference key.
    reason = LogService.describe(e, st);
  }
  LogService.warn('[Settings] "$what" did not persist: $reason');
  return false;
}
