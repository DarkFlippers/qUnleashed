import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/logging.dart';
import 'directory.dart';

/// Remembers the update channel and build variant the user picked, per
/// firmware.
///
/// The controller that owns these is created in a widget's `initState` and
/// disposed with it, so without this the choice was lost on leaving the page,
/// not merely on restart - and the fallback then quietly reselected the
/// release channel and the packaged variant next time.
///
/// Stored as one preference per firmware per field, following the convention
/// the rest of the app uses for per-entity settings. A single JSON blob would
/// mean one unreadable value could take every other firmware's settings down
/// with it on the next write.
class UpdateSettingsStore {
  UpdateSettingsStore._();

  static final UpdateSettingsStore instance = UpdateSettingsStore._();

  static const String _prefix = 'firmware.update';

  static String _channelPref(String shortName) => '$_prefix.$shortName.channel';

  static String _variantPref(String shortName) => '$_prefix.$shortName.variant';

  final Map<String, String> _channels = {};
  final Map<String, UnleashedVariant> _variants = {};
  Future<void>? _loading;

  /// Reads once per process; later callers await the same read.
  Future<void> load() => _loading ??= _load();

  String? channelFor(String shortName) => _channels[shortName];

  UnleashedVariant? variantFor(String shortName) => _variants[shortName];

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (!key.startsWith('$_prefix.')) continue;
        // Per key, so a value of the wrong type - or one this build cannot
        // make sense of - costs that one setting rather than the whole read.
        try {
          _read(prefs, key);
        } catch (e) {
          LogService.log('[UpdateSettings] "$key" unreadable: $e');
        }
      }
    } catch (e) {
      LogService.log('[UpdateSettings] load failed: $e');
    }
  }

  void _read(SharedPreferences prefs, String key) {
    final rest = key.substring(_prefix.length + 1);
    final dot = rest.lastIndexOf('.');
    if (dot <= 0) return;
    final shortName = rest.substring(0, dot);
    final value = prefs.getString(key);
    if (value == null || value.isEmpty) return;
    switch (rest.substring(dot + 1)) {
      case 'channel':
        _channels[shortName] = value;
      case 'variant':
        // A variant this build no longer has drops the variant and keeps the
        // channel, rather than losing both.
        final variant = UnleashedVariant.fromName(value);
        if (variant != null) _variants[shortName] = variant;
    }
  }

  /// Records whichever of [channelId] and [variant] is given.
  ///
  /// Only what the caller passes is written, so a fallback-derived channel the
  /// user never chose is not persisted by a tap on the variant selector.
  ///
  /// Never throws: a preference that will not persist is worth one line in the
  /// log and nothing more, and the caller has already applied the choice to
  /// what is on screen.
  Future<void> remember(
    String shortName, {
    String? channelId,
    UnleashedVariant? variant,
  }) async {
    await load();
    if (channelId != null) _channels[shortName] = channelId;
    if (variant != null) _variants[shortName] = variant;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (channelId != null) {
        await prefs.setString(_channelPref(shortName), channelId);
      }
      if (variant != null) {
        await prefs.setString(_variantPref(shortName), variant.name);
      }
    } catch (e) {
      LogService.log('[UpdateSettings] save failed: $e');
    }
  }

  /// Forgets what was read, so one test does not inherit another's choices.
  ///
  /// Only the memo: the preferences themselves are the test's to set up, and
  /// nothing else can un-memoise [load].
  @visibleForTesting
  void reset() {
    _channels.clear();
    _variants.clear();
    _loading = null;
  }
}
