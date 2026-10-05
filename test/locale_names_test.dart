import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/localization/controller.dart';
import 'package:qunleashed/services/localization/l10n.dart';

/// That every language the app ships can be named in the picker.
///
/// `supportedLocales` is generated from the ARB files, so a translation
/// arriving from Crowdin adds a locale on its own - no code change, nothing to
/// register. `_localeNames` is the one thing that does not follow: it is a hand
/// written map, and `nameOf` falls back to the language tag when a locale is
/// missing from it.
///
/// So a new language is offered as "uk" instead of "Українська", and nothing
/// fails - not the analyzer, not the l10n codegen, not a widget test. The
/// Ukrainian translation shipped that way in #141, which is why this exists.
void main() {
  test('every supported locale has a name written in its own language', () {
    final unnamed = [
      for (final locale in L10n.supportedLocales)
        if (QLocaleController.nameOf(locale) == locale.toLanguageTag())
          locale.toLanguageTag(),
    ];

    expect(
      unnamed,
      isEmpty,
      reason:
          'add an entry to _localeNames in '
          'lib/services/localization/controller.dart, written in that '
          'language rather than in English',
    );
  });

  // The fallback is still wanted - it is better than throwing - so this pins
  // that it is a fallback and not the normal path.
  test('an unknown locale falls back to its tag', () {
    expect(QLocaleController.nameOf(const Locale('xx')), 'xx');
  });

  test('the names are not just the tags', () {
    expect(QLocaleController.nameOf(const Locale('uk')), 'Українська');
    expect(QLocaleController.nameOf(const Locale('ru')), 'Русский');
    expect(QLocaleController.nameOf(const Locale('en')), 'English');
  });
}
