import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../prefs_reader.dart';

/// The read-once-and-remember half of a preferences-backed settings store.
///
/// Three stores had this identical thirty lines - `DeviceSettings`,
/// `HomeWidgetSettings` and `MapSettings` - and it had already drifted
/// between them once. What is shared is the mechanism and nothing else: the
/// memo, the single attempt, releasing it so the next caller may try again,
/// and the order of `_loaded` against the fields.
///
/// What is deliberately **not** here is the logging. [onLoadFailed] is
/// abstract rather than a default that takes a tag and calls
/// `LogService.warn` itself, because [LogService.info]'s own doc says there
/// is no catch-all to reach for and the level is a decision per site - and
/// these three do differ in what a failure costs them. Abstract keeps each
/// store writing its own line, with the analyzer making sure it writes one.
///
/// Composition would have done as well, and keeps `notifyListeners()` at the
/// store. It needed four callbacks to say what three abstract members say
/// here, so this is a base class - and `lib/` has no app-authored mixins to
/// be consistent with either way. #126.
abstract class PrefsBackedSettings extends ChangeNotifier {
  bool _loaded = false;
  Future<void>? _loading;

  /// Whether a read has finished. False after a failed one, which is what
  /// [HomeWidgetSettings] gates its push on.
  bool get loaded => _loaded;

  /// Reads once per process; later callers await the same read.
  ///
  /// Never throws. Every one of these memoises and has at least one caller
  /// that does not await it, so a rejection would be an unlabelled uncaught
  /// error and then be handed to every later caller. The initialisers are a
  /// working fallback.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _read();
  }

  Future<void> _read() async {
    final PrefsReader reader;
    try {
      reader = PrefsReader(await SharedPreferences.getInstance());
    } catch (e, st) {
      // The only throw on this path. Everything [readFrom] does goes through
      // PrefsReader, which cannot throw, so the fields are either all read or
      // all left at their initialisers and "load failed" always means the
      // second.
      //
      // The memo is released rather than latched, so the next caller reads
      // again. Until #124 it was latched, on the argument that main() read
      // preferences through three unguarded controllers before runApp - a
      // store that would not open meant an app that never started, and there
      // was nothing left to retry. #124 caught those three, the app starts
      // now, and `getInstance` drops its own memo on failure for exactly
      // this.
      _loading = null;
      onLoadFailed(e, st);
      return;
    }
    readFrom(reader);
    _loaded = true;
    notifyListeners();
  }

  /// Fills the fields from [reader], and reports whatever it skipped.
  ///
  /// The report belongs here rather than in [_read] because it carries the
  /// store's own tag, which is the same reason [onLoadFailed] is abstract.
  @protected
  void readFrom(PrefsReader reader);

  /// Says that nothing was read. What that costs differs per store, so the
  /// line - and its level - is the store's to write.
  @protected
  void onLoadFailed(Object error, StackTrace stack);

  /// Puts every field back to its initialiser.
  @protected
  void resetFields();

  /// Forgets what was read, so one test does not inherit another's state.
  ///
  /// Without this the first test to drive a failure fixes the result for
  /// every test after it in the same isolate - see [load].
  @visibleForTesting
  void reset() {
    resetFields();
    _loaded = false;
    _loading = null;
  }
}
