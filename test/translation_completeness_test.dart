import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A ratchet on languages the app offers but does not speak.
///
/// `L10n.supportedLocales` is generated from whatever ARB files are present, so
/// a file arriving from Crowdin adds a language to the picker on its own. That
/// is the right design - until the file is not a translation.
///
/// Crowdin fills an untranslated string with the source language unless
/// `skip_untranslated_strings` is set, and it was not. Enabling Ukrainian in
/// the project therefore produced `app_uk.arb` with 1293 strings, every one of
/// them English, and #141 merged it: the picker offered Українська and the app
/// went on showing English.
///
/// Nothing else notices. The file parses, `gen-l10n` succeeds, the analyzer is
/// clean, the suite passes, and `check_translation_sources.sh` checks who
/// edited a file rather than what is in it.
///
/// **What this does not police is incompleteness.** A half-translated language
/// is wanted, and so is falling back to English for the rest - with
/// `skip_untranslated_strings` set, an early translation is a short file of
/// real strings and `gen-l10n` fills the gaps from the template. That is the
/// intended behaviour, not a defect, and a file with nothing in it yet is the
/// same thing earlier.
///
/// What it catches is the English source arriving *as* the translation, which
/// is not a fallback: those 1293 strings asserted they were Ukrainian.
///
/// **A real translation shares some strings with English** - product names,
/// protocol names, units. Russian shares 82 of 1293, six per cent. A file that
/// is 100% English is not a translation in any language, so the line is drawn
/// at 90%: far from both, and assuming nothing about script, since a
/// Latin-script language still rewrites its sentences.
///
/// ## Why this has a budget rather than simply failing
///
/// `app_uk.arb` is in the tree and is entirely English *now*, and it cannot be
/// deleted from here: `check_translation_sources.sh` refuses a hand edit to a
/// file Crowdin owns, and it is right to - Crowdin exports the whole file, so
/// the next sync would put it back. Removing it means either disabling
/// Ukrainian in the Crowdin project until it is worked on, or letting a sync
/// re-export it once the option above is set.
///
/// So the known one is named here, and a second cannot appear unnoticed. When
/// Ukrainian is translated, or the language is disabled, this entry goes and
/// the list is empty again - which is the only direction it is allowed to move.
const Set<String> kUntranslated = {
  // 1293 of 1293 strings are the English source. #141, and the option that
  // caused it is fixed in crowdin-rx.yml in the same change as this comment.
  'app_uk.arb',
};

void main() {
  final dir = Directory('translations');

  Map<String, String> stringsOf(File file) {
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return {
      for (final entry in decoded.entries)
        if (!entry.key.startsWith('@') && entry.value is String)
          entry.key: entry.value as String,
    };
  }

  late Map<String, String> english;
  late List<File> others;

  setUpAll(() {
    english = stringsOf(File('${dir.path}/app_en.arb'));
    others = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb') && !f.path.endsWith('app_en.arb'))
        .toList();
  });

  test('there is something to check', () {
    // A directory that stopped matching would otherwise pass this file in
    // silence, which is how a guard becomes decoration.
    expect(english, isNotEmpty);
    expect(others, isNotEmpty, reason: 'expected at least one translation');
  });

  /// Which locales are the English source wearing another name.
  Map<String, String> untranslated() {
    final verdicts = <String, String>{};
    for (final file in others) {
      final name = file.uri.pathSegments.last;
      final strings = stringsOf(file);
      // A language that has been started and not finished is fine, and
      // falling back to English for the rest is the behaviour this project
      // wants. With `skip_untranslated_strings` set, that is exactly what an
      // early translation looks like: a short file of real strings, and
      // `gen-l10n` filling the gaps from the template. An empty one is the
      // same thing with nothing done yet.
      //
      // So incompleteness is not what this counts. What it counts is the
      // English source arriving *as* the translation, which is a different
      // thing and is not a fallback - it is 1293 strings asserting they are
      // Ukrainian.
      if (strings.isEmpty) continue;
      final shared = strings.entries
          .where((e) => english[e.key] == e.value)
          .length;
      final percent = shared * 100 / strings.length;
      if (percent > 90) {
        verdicts[name] =
            '${percent.toStringAsFixed(0)}% of ${strings.length} strings are '
            'the English source';
      }
    }
    return verdicts;
  }

  test('no language is offered that the app does not speak', () {
    final found = untranslated();
    final unexpected = {
      for (final entry in found.entries)
        if (!kUntranslated.contains(entry.key)) entry.key: entry.value,
    };

    expect(
      unexpected,
      isEmpty,
      reason:
          'a locale whose strings are the English source is not a translation, '
          'and offering it in the picker promises a language the app does not '
          'speak.\n'
          'Crowdin fills untranslated strings with the source language unless '
          '`skip_untranslated_strings` is set on the download in '
          '.github/workflows/crowdin-rx.yml.\n'
          'A language enabled in Crowdin but not yet worked on should not be '
          'exported at all. If this one is deliberate, add it to '
          'kUntranslated with the reason.',
    );
  });

  test('the budget does not outlive what it covers', () {
    final stale = kUntranslated.difference(untranslated().keys.toSet());

    expect(
      stale,
      isEmpty,
      reason:
          'these are listed as untranslated and are not any more - remove them '
          'from kUntranslated. The list only shrinks.',
    );
  });
}
