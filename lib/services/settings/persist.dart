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
Future<void> persistSetting(
  String what,
  Future<void> Function(SharedPreferences prefs) write,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await write(prefs);
  } catch (e) {
    LogService.warn('[Settings] "$what" did not persist: $e');
  }
}
