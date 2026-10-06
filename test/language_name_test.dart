import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/localization/controller.dart';
import 'package:qunleashed/services/localization/l10n.dart';

/// What the language picker writes on each row.
///
/// The names used to live in a map in `controller.dart`, so a language arriving
/// from Crowdin was listed by its code - `uk` rather than `Українська` - until
/// someone noticed and added it. They come from `languageName` now, which the
/// translator writes alongside every other string.
///
/// The expected values are read from the ARB files rather than written here. A
/// translator may reasonably change how their language spells its own name, and
/// that is not a reason for this repository's suite to go red; what is being
/// checked is that the picker shows their answer, not which answer it is.
void main() {
  String? nameIn(Locale locale) {
    final file = File('translations/app_${locale.languageCode}.arb');
    final arb = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return arb['languageName'] as String?;
  }

  test('there is something to check', () {
    // Both of the tests below pass over an empty list in silence, and
    // `supportedLocales` is generated from whatever ARB files exist.
    expect(L10n.supportedLocales, isNotEmpty);
  });

  test('every supported language is named as its own ARB names it', () {
    for (final locale in L10n.supportedLocales) {
      expect(
        QLocaleController.nameOf(locale),
        nameIn(locale),
        reason:
            'the picker should show what app_${locale.languageCode}.arb says, '
            'and that file should say something',
      );
    }
  });

  test('a supported language is not named by its code', () {
    // The fallback and the answer are both strings, so a `nameOf` that silently
    // stopped reading the ARB would still return something plausible for every
    // locale. This is what tells the two apart.
    for (final locale in L10n.supportedLocales) {
      expect(
        QLocaleController.nameOf(locale),
        isNot(locale.toLanguageTag()),
        reason: '$locale fell back to its tag, so its name was not found',
      );
    }
  });

  test('a language the app does not speak falls back to its tag', () {
    // `lookupL10n` throws for these rather than returning null, so the point
    // is that nothing reaches it.
    expect(QLocaleController.nameOf(const Locale('de')), 'de');
    expect(QLocaleController.nameOf(const Locale('pt', 'BR')), 'pt-BR');
  });
}
