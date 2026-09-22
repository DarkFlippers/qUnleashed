import 'package:shared_preferences/shared_preferences.dart';

/// Reads preferences without the cast that [SharedPreferences.getBool] and its
/// siblings perform, and remembers which keys did not match.
///
/// `getBool`, `getString` and `getDouble` are each
/// `_preferenceCache[key] as T?` — a cast, not a checked read. A value stored
/// under the wrong type throws: an older build that wrote the key differently,
/// a platform-side migration, an edited plist. In a settings store that reads
/// a dozen keys in a row, that one stale key costs every key after it, so a
/// whole screen reverts to its defaults because of one.
///
/// Scalars only, and [orNull] asserts it. `getStringList` is the one
/// accessor that is *not* a plain cast: it re-casts the elements, because
/// most backends hand a list back as `List<dynamic>` — the JSON ones on
/// Linux and Windows, the pigeon one on iOS and macOS. Read through here a
/// good list would fail `value is List<String>` and be *reported* as the
/// wrong type, which is worse than not supporting it. Lists want
/// `getStringList`; no caller needs one yet.
///
/// [SharedPreferences.get] does no cast, so checking the type here costs the
/// one key instead. That is the shape `UpdateSettingsStore` already reaches
/// for with a per-key `try`; this is the same idea without the try.
///
/// The mismatches are collected rather than logged, so a store reports once
/// per load naming the keys it ignored instead of once per key — the tally at
/// a batch boundary that `LogService.info`'s doc asks for.
class PrefsReader {
  PrefsReader(this._prefs);

  final SharedPreferences _prefs;
  final List<String> _mismatched = <String>[];

  /// Keys whose stored value was not the type the caller asked for, in the
  /// order they were read. Empty on an ordinary load, including a first run.
  List<String> get mismatched => List.unmodifiable(_mismatched);

  /// The stored value, or [fallback] when the key is absent or the wrong type.
  T or<T extends Object>(String key, T fallback) => orNull<T>(key) ?? fallback;

  /// The stored value, or null when the key is absent or the wrong type.
  ///
  /// Separate from [or] for two kinds of caller: settings that are genuinely
  /// optional, where absence is the answer rather than something to replace —
  /// an API key nobody has entered, a design nobody has picked — and settings
  /// stored as a `String` that is then parsed into something else, where [or]
  /// cannot express the fallback because its type is not the stored type.
  T? orNull<T extends Object>(String key) {
    final value = _prefs.get(key);
    assert(
      value is! List,
      'PrefsReader is scalars only: a stored list arrives as List<dynamic> on '
      'most backends and would be reported as the wrong type. Use '
      'SharedPreferences.getStringList.',
    );
    if (value is T) return value;
    // A whole number asked for as a double. Android's legacy plugin passes
    // non-String values straight through, so a native putInt or an older
    // build's setInt under the same key arrives here as an int, and `12` and
    // `12.0` are the same setting. (JSON is not a source: the Linux and
    // Windows backends round-trip a double as `19.0` and decode it back as
    // one.) Exact below 2^53, which every setting read through here is.
    //
    // The `0.0 is T` half is load-bearing, not a tidiness check: without it
    // `1.toDouble() as bool` throws out of here and out of the caller's [or],
    // and the stores catch only their read - so it would escape _load
    // entirely, latch a rejection into the memo, and surface as an unlabelled
    // uncaught error. One stale key costing every key, which is the whole
    // thing this class exists to prevent, by the worst available route.
    if (value is int && 0.0 is T) return value.toDouble() as T;
    // Absent is not a mismatch: a key nobody has written yet is the ordinary
    // case on a first run, and reporting it would make every fresh install
    // look like a fault.
    if (value != null) _mismatched.add(key);
    return null;
  }
}
