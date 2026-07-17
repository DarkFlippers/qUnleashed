import 'package:flipperlib/flipperlib.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted configuration for the embedded VirtualFlipper emulator. The
/// emulator is a developer feature: off by default, revealed by a settings
/// toggle. This service is the single source of truth for the runtime engine —
/// it feeds [VirtualFlipperEngine.enabled] (discovery gate) and
/// [VirtualFlipperEngine.deviceName] (the name provisioned into the emulated
/// firmware's OTP and shown in the device picker).
class EmulatorSettings {
  EmulatorSettings._();

  static final EmulatorSettings instance = EmulatorSettings._();

  static const _prefEnabled = 'emulator.enabled';
  static const _prefName = 'emulator.name';

  /// OTP names are `[a-zA-Z0-9.]`, up to 8 chars (scripts/otp.py).
  static const int nameMaxLength = 8;
  static const String defaultName = 'Darked';

  /// Whether the host can run the emulator at all (macOS + engine bundle).
  bool get isSupported => VirtualFlipperEngine.isSupported;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) ?? false;
  }

  Future<String> name() async {
    final prefs = await SharedPreferences.getInstance();
    return sanitizeName(prefs.getString(_prefName));
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, value);
    VirtualFlipperEngine.enabled = value;
  }

  Future<void> setName(String value) async {
    final clean = sanitizeName(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefName, clean);
    VirtualFlipperEngine.deviceName = clean;
  }

  /// Pushes persisted config into the engine's static gates. Called once at
  /// startup so discovery and the OTP name reflect the saved settings.
  Future<void> apply() async {
    VirtualFlipperEngine.enabled = await isEnabled();
    VirtualFlipperEngine.deviceName = await name();
  }

  /// Keeps only OTP-legal characters and clamps to 8; empty falls back to the
  /// default so the picker/firmware always carry a real name.
  static String sanitizeName(String? raw) {
    if (raw == null) return defaultName;
    final filtered = raw.replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '');
    if (filtered.isEmpty) return defaultName;
    return filtered.length > nameMaxLength
        ? filtered.substring(0, nameMaxLength)
        : filtered;
  }
}
