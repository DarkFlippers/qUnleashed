import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gen/l10n_generated.dart';

/// Language names written in the language itself, so every entry of the picker
/// stays readable no matter which language the app currently runs in.
const Map<String, String> _localeNames = {'en': 'English', 'ru': 'Русский'};

class QLocaleController extends ChangeNotifier with WidgetsBindingObserver {
  QLocaleController._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static const String _prefLocale = 'locale.code';

  static final QLocaleController instance = QLocaleController._();

  Locale? _locale;

  /// Locale the user picked, or null while the app follows the device.
  Locale? get locale => _locale;

  bool get followsSystem => _locale == null;

  static List<Locale> get supported => L10n.supportedLocales;

  /// Locale the app actually renders in, with the device language mapped onto
  /// a supported one.
  Locale get resolved =>
      _locale ??
      basicLocaleListResolution(
        WidgetsBinding.instance.platformDispatcher.locales,
        L10n.supportedLocales,
      );

  static String nameOf(Locale locale) =>
      _localeNames[locale.languageCode] ?? locale.toLanguageTag();

  Future<void> loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefLocale);
    if (raw == null || raw.isEmpty) return;
    for (final locale in L10n.supportedLocales) {
      if (locale.languageCode == raw) {
        if (locale != _locale) {
          _locale = locale;
          notifyListeners();
        }
        return;
      }
    }
  }

  Future<void> setLocale(Locale? locale) async {
    if (locale == _locale) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_prefLocale);
    } else {
      await prefs.setString(_prefLocale, locale.languageCode);
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_locale == null) notifyListeners();
  }
}
