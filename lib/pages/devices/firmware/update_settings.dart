import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/logging.dart';
import 'directory.dart';

/// What the user last chose for one firmware.
typedef UpdateSelection = ({String? channelId, UnleashedVariant? variant});

/// Remembers the update channel and build variant the user picked, per
/// firmware.
///
/// The controller that owns these is created in a widget's `initState` and
/// disposed with it, so without this the choice was lost on leaving the page,
/// not merely on restart - and the fallback then quietly reselected the
/// release channel and the packaged variant next time.
class UpdateSettingsStore {
  UpdateSettingsStore._();

  static final UpdateSettingsStore instance = UpdateSettingsStore._();

  static const String _prefsKey = 'firmware_update_settings_v1';

  final Map<String, UpdateSelection> _byFirmware = {};
  Future<void>? _loading;

  /// Loads once per process; later callers await the same read.
  Future<void> load() => _loading ??= _load();

  UpdateSelection? selectionFor(String shortName) => _byFirmware[shortName];

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        final channelId = value['channel'] as String?;
        _byFirmware[entry.key] = (
          channelId: channelId != null && channelId.isNotEmpty
              ? channelId
              : null,
          variant: _variantByName(value['variant'] as String?),
        );
      }
    } catch (e) {
      LogService.log('[UpdateSettings] load failed: $e');
    }
  }

  /// Records a choice. Never throws: a preference that will not persist is
  /// worth one line in the log and nothing more, and the caller has already
  /// applied the choice to what is on screen.
  Future<void> remember(
    String shortName, {
    required String? channelId,
    required UnleashedVariant? variant,
  }) async {
    await load();
    _byFirmware[shortName] = (channelId: channelId, variant: variant);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          for (final entry in _byFirmware.entries)
            if (entry.value.channelId != null || entry.value.variant != null)
              entry.key: {
                if (entry.value.channelId != null)
                  'channel': entry.value.channelId,
                if (entry.value.variant != null)
                  'variant': entry.value.variant!.name,
              },
        }),
      );
    } catch (e) {
      LogService.log('[UpdateSettings] save failed: $e');
    }
  }

  /// Forgets everything, for tests: the instance outlives any one controller,
  /// so a test that did not clear it would inherit the previous one's choices.
  Future<void> clear() async {
    _byFirmware.clear();
    _loading = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  static UnleashedVariant? _variantByName(String? name) {
    if (name == null) return null;
    for (final variant in UnleashedVariant.values) {
      if (variant.name == name) return variant;
    }
    // A variant this build no longer has: fall back rather than fail the whole
    // read and lose the channel with it.
    return null;
  }
}
