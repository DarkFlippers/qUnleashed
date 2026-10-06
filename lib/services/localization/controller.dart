import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging.dart';
import '../prefs_reader.dart';
import 'gen/l10n_generated.dart';

class QLocaleController extends ChangeNotifier with WidgetsBindingObserver {
  QLocaleController._() {
    // Plain unit tests never initialize a binding, and a service that only
    // wants a string must not force one into existence.
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
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
  Locale get resolved {
    final chosen = _locale;
    if (chosen != null) return chosen;
    try {
      return basicLocaleListResolution(
        WidgetsBinding.instance.platformDispatcher.locales,
        L10n.supportedLocales,
      );
    } catch (_) {
      return L10n.supportedLocales.first;
    }
  }

  /// The language's own name, written in that language, so every entry of the
  /// picker stays readable whichever language the app is running in.
  ///
  /// This was a map kept by hand here, which meant a language arriving from
  /// Crowdin was listed by its code until someone remembered to add it.
  /// `languageName` is the same answer from the only people who know it, and
  /// it costs this repository nothing.
  ///
  /// `isSupported` is asked first because `lookupL10n` throws for a locale it
  /// does not know rather than returning null, and this takes any `Locale` a
  /// caller has. Asking keeps a bare catch out of the count as well.
  ///
  /// There is deliberately nothing here for an ARB that left `languageName`
  /// untranslated: `gen-l10n` inherits the template, so the picker would call
  /// that language "English", and the only check possible here - comparing
  /// every name against the English one - would hide it rather than report it.
  /// `translation_completeness_test` fails on the sync's pull request instead,
  /// which is both earlier and where the fix is.
  static String nameOf(Locale locale) => L10n.delegate.isSupported(locale)
      ? lookupL10n(locale).languageName
      : locale.toLanguageTag();

  Future<void> loadLocale() async {
    final PrefsReader reader;
    try {
      reader = PrefsReader(await SharedPreferences.getInstance());
    } catch (e, st) {
      // `_initCore` awaits this, and both entry points await that: `main`
      // ahead of `runApp`, `widgetMain` with no UI at all. So a rejection
      // here is not a locale that falls back - it is an app that never
      // appears, or a widget engine whose link keeper never comes up.
      //
      // installUncaughtHandlers would still keep the error, but `history` is
      // in memory and there is no log screen to read it from, so the record
      // dies with the process. Caught, it survives into a session someone
      // can look at. #124.
      LogService.warn('[Locale] load failed: ${LogService.describe(e, st)}');
      return;
    }
    final raw = reader.orNull<String>(_prefLocale);
    reader.report('[Locale]');
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

  /// Null follows the system.
  ///
  /// Asserted rather than filtered because [l10n] resolves through this and
  /// `lookupL10n` throws for a language it was not generated for - and
  /// several callers reach `l10n` outside any try, `MapSettings._load` among
  /// them, where a throw would latch a rejection into its memo (#123).
  Future<void> setLocale(Locale? locale) async {
    assert(
      locale == null || L10n.supportedLocales.contains(locale),
      'setLocale takes a locale L10n was generated for; '
      '$locale is not one of ${L10n.supportedLocales}',
    );
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
