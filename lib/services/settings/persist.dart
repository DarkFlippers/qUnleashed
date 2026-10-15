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
/// because a write can fail without throwing: on Android the legacy backend
/// returns `Editor.commit()` straight through, and that is `false` when the
/// write to persistent storage did not land. `SharedPreferences` has already
/// updated its own cache by then, so the setting reads back correctly for the
/// rest of the session and is gone at the next launch. Typing this `void`
/// discarded that `false` with no analyzer warning - `void` is a top type, so
/// `Future<bool>` satisfies it silently - and the one promise this function
/// makes was not kept for the whole half of the failures that do not throw.
/// #313.
Future<void> persistSetting(
  String what,
  Future<bool> Function(SharedPreferences prefs) write,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (!await write(prefs)) {
      LogService.warn(
        '[Settings] "$what" did not persist: the store refused the write',
      );
    }
  } catch (e) {
    LogService.warn('[Settings] "$what" did not persist: $e');
  }
}
