// Reading the ARB files the way every test that reads them needs to.
//
// An ARB file is JSON where the translatable strings sit beside their own
// metadata: a key beginning with `@` describes the key next to it, and a key
// whose value is not a string is one of those descriptors or a resource
// attribute. Every test that walks a translation has to know that, and three
// of them had worked it out separately - `translation_completeness_test.dart`,
// `reserved_name_chars_test.dart` and `language_name_test.dart` - before
// `font_glyph_coverage_test.dart` would have been the fourth.
//
// It matters that they agree. The filter decides how much each test actually
// examines, and a test that quietly narrows it still passes: the font coverage
// check would simply see fewer characters and report no offender. So the rule
// lives here, where teaching it something new - a metadata prefix Crowdin
// starts emitting, a plural arriving as a Map rather than a String - teaches
// every caller at once.
import 'dart:convert';
import 'dart:io';

import 'source_files.dart';

/// Where `l10n.yaml` points `arb-dir`.
const String kArbDir = 'translations';

/// The ARB files git can see, English included.
List<File> arbFiles() =>
    gitVisibleFiles('$kArbDir/*.arb').map(File.new).toList();

/// The translatable strings in [file], without the metadata keys.
Map<String, String> arbStrings(File file) {
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final entry in decoded.entries)
      if (!entry.key.startsWith('@') && entry.value is String)
        entry.key: entry.value as String,
  };
}
