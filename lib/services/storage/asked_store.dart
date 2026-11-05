import 'package:shared_preferences/shared_preferences.dart';

import '../logging.dart';
import '../settings/persist.dart';

/// Remembers, across launches, that the storage prompt has been shown.
///
/// This is what lets a standing storage denial be known at startup. Held per
/// process the flag could not do that: every fresh launch read "not asked", so
/// `readAndroidStoragePermission` answered `unknown`, which draws nothing —
/// and the notice could only appear after something re-fired the raw
/// `MANAGE_EXTERNAL_STORAGE` ask, which is the unannounced settings dump the
/// explainer exists to replace. The three screens behind the storage path
/// therefore stayed silent on exactly the launch where the user had already
/// said no, which is the bug #351 is about.
///
/// A tiny object rather than two more statics in `permissions.dart`: it has a
/// cache to keep honest and a reset hook the tests need, and that file already
/// carries more process-wide state than it should.
///
/// Never throws. A store that will not open answers "not asked", which keeps
/// the notice off rather than putting up a gate on a guess.
class StorageAskedStore {
  StorageAskedStore();

  static const String _key = 'permission.storage.asked';

  bool? _cached;

  /// Whether this install has shown the system prompt.
  ///
  /// Cached after the first read: this is reached from the resume probe, and
  /// the answer only ever changes through [markAsked] on this same object.
  Future<bool> wasAsked() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      return _cached = prefs.getBool(_key) ?? false;
    } catch (e, st) {
      // `caught`, not `info`: while this fails the storage notice cannot
      // appear at all, and nothing else would say why three screens are
      // silent about a permission the user refused. Not cached, so a store
      // that opens later still works.
      LogService.caught(
        '[Storage] could not read whether the permission was asked, so a '
        'standing denial stays silent: ${LogService.describe(e, st)}',
      );
      return false;
    }
  }

  /// Records that the prompt was shown. Idempotent.
  Future<void> markAsked() async {
    if (_cached == true) return;
    _cached = true;
    await persistSetting(
      'that the storage permission prompt was shown',
      (prefs) => prefs.setBool(_key, true),
    );
  }

  /// Drops the cache, for a test. The stored value is left alone —
  /// `SharedPreferences.setMockInitialValues` is what controls that.
  void debugReset() => _cached = null;
}

/// The one instance, which `permissions.dart` reaches through.
///
/// A library-level final rather than a parameter threaded through
/// `appDocumentsDirectory` and every storage path above it. ADR 0002 asks for
/// constructor parameters in new code and this is a deliberate exception: the
/// call chain this sits under is `paths.dart`'s free functions, reached from
/// the home-screen widget's isolate and a dozen unit tests, and giving all of
/// them a parameter to pass a flag store is a worse trade than one seam with a
/// reset hook.
final StorageAskedStore storageAskedStore = StorageAskedStore();
