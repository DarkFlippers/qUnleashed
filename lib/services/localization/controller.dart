import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging.dart';
import '../prefs_reader.dart';
import '../settings/persist.dart';
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

  /// What the app renders in when it has nothing better: the ARB template's
  /// own language.
  ///
  /// It has to be named rather than taken from the head of the list.
  /// `basicLocaleListResolution` answers with the *first* entry of whatever it
  /// is given - both when nothing matches and when the device offers no
  /// preference at all (`app.dart:154` and `:237` in the framework) - and
  /// `gen-l10n` emits `supportedLocales` sorted, so the head of that list is
  /// whichever language sorts first. It was `en` until Belarusian arrived from
  /// Crowdin and silently became `be`, which would have rendered the whole app
  /// in Belarusian on every device whose language it does not speak.
  static const Locale fallback = Locale('en');

  /// [supported], with [fallback] first, for anything that resolves a device
  /// language. The picker uses [supported] instead, where sorted is what a
  /// reader wants.
  ///
  /// This list is what `MaterialApp.supportedLocales` is given as well, because
  /// the framework runs the same resolution for the widget tree and would
  /// otherwise fall back to the sorted head on its own.
  static final List<Locale> resolutionOrder = <Locale>[
    fallback,
    ...L10n.supportedLocales.where((locale) => locale != fallback),
  ];

  /// Locale the app actually renders in, with the device language mapped onto
  /// a supported one.
  Locale get resolved {
    final chosen = _locale;
    if (chosen != null) return chosen;
    try {
      return basicLocaleListResolution(
        WidgetsBinding.instance.platformDispatcher.locales,
        resolutionOrder,
      );
    } catch (_) {
      return fallback;
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
      // installUncaughtHandlers would still record the error - and now that
      // ADR 0013 §1 has made Sentry the only channel, it would even be
      // reported. What it would not carry is which load failed: an uncaught
      // rejection arrives as `[uncaught]` with nothing naming the operation,
      // which is the same argument `guarded` makes. Caught here, it carries
      // its area. #124.
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
    // Through persistSetting rather than SharedPreferences directly. The
    // language page wraps this in a VoidCallback, which discards the future,
    // so before #313 a store that would not open reached the zone as an
    // unlabelled `[uncaught]` naming no setting, and a store that refused the
    // write said nothing at all.
    //
    // Following the system is an absent preference, not a stored "system",
    // so the null case removes rather than writes - one of the two per call,
    // never both. A refused removal reads as "locale.code did not persist"
    // and means the old language is still on disk and comes back at the next
    // launch.
    await persistSetting(
      _prefLocale,
      (prefs) => locale == null
          ? prefs.remove(_prefLocale)
          : prefs.setString(_prefLocale, locale.languageCode),
    );
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_locale == null) notifyListeners();
  }
}
