// The home-screen widget's Android string resources, written from the ARB.
//
// ## Why the widget's text cannot be a Flutter string
//
// `android/app/src/main/res/xml/key_widget_info.xml` points
// `android:description` at `@string/widget_description`, and the launcher
// reads it out of the merged manifest to draw its widget picker - before this
// app has run, and without starting the Flutter engine. The nine captions go
// into a `RemoteViews` that the launcher's own process inflates. So the
// widget's text has to exist as Android resources; `L10n` cannot reach it.
//
// ## Why it is generated
//
// The ten strings used to be written by hand, in `res/values/strings.xml` with
// a hand-made Russian copy in `res/values-ru/`. `crowdin.yml` tracks one file,
// `/translations/app_en.arb`, so neither was ever in the translation pipeline:
// the app was translated and the widget beside it was English in seven of the
// eight locales. #319. A hand-written resource is also a second writer for
// translations, which is the failure `check_translation_sources.sh` exists to
// refuse for the ARB files - here with no guard to catch it.
//
// So `translations/app_en.arb` holds the source, Crowdin owns the rest exactly
// as for every other string, and this writes the resources. `flutter gen-l10n`
// already compiles those same files into `lib/services/localization/gen/`;
// this is the second output of the one source.
//
// ## Why this is Dart, and not the Gradle task that calls it
//
// It was Kotlin inside `android/app/build.gradle.kts` first, and a review
// found the hole: `analysis_options.yaml` excludes `android/**`, nothing in
// this repository runs Kotlin tests, and no Android build runs on a pull
// request (#35). So the rule lived where nothing could reach it before a
// merge, and a guard test that re-derived the same rule in Dart compared its
// own copy against the *callers* rather than against the generator - breaking
// the generator's own `resourceName` left all of it green.
//
// Here there is one copy, `flutter test` runs it, and
// `test/widget_strings_test.dart` tests this file rather than a likeness of
// it. Two of the defects below were found that way and are regression cases
// there now.
//
// Nothing it writes is checked in. The alternative - commit the XML and have
// CI refuse a stale copy - has to be regenerated whenever a translation lands,
// which happens on `l10n/crowdin`, and a second committer on that branch is
// what ADR 0016 collapsed to one owner after #321 left every nightly sync
// opening a pull request with two commits that cancelled each other (#323).
//
// ## The other reader of translations/
//
// `test/arb.dart` is the shared ARB reader for the test suite, and this file
// deliberately does not use it: `arbFiles()` reaches `gitVisibleFiles`, which
// shells out to `git ls-files` and calls `expect()` from `flutter_test`, and
// neither belongs in a build step that must read the directory it was pointed
// at. The filters differ on purpose too - `arbStrings` is tolerant because
// every test has to agree on one rule, while `widgetResources` below throws on
// a widget key that is not a string, because for these ten that is a pipeline
// defect rather than a fallback.
//
//   dart tool/widget_strings.dart --arb-dir translations --out <dir>
import 'dart:convert';
import 'dart:io';

/// The prefix that marks an ARB key as the Android widget's.
///
/// It is the whole selector, and it has to be a prefix no other key starts
/// with: `widgetGroupTheme` and the rest of the widget *settings* strings are
/// the app's own and must not become resources.
const String keyPrefix = 'androidWidget';

/// The ARB that is the source, and the one that fills the default `values/`.
const String sourceLocale = 'en';

/// Its filename, which `generate` both looks for and compares against.
const String sourceName = 'app_$sourceLocale.arb';

/// Android spells three languages the way they were spelled in 1989 and
/// resolves a device's modern code to the old one, not the other way round.
///
/// None is enabled today. The day one is, `values-he/` would be a directory no
/// Hebrew phone ever reads.
const Map<String, String> legacyLanguageCodes = <String, String>{
  'he': 'iw',
  'id': 'in',
  'yi': 'ji',
};

/// Raised for anything that should stop the build, with a sentence that names
/// the file rather than the symptom.
class WidgetStringsError implements Exception {
  WidgetStringsError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// `androidWidgetErrorNoDevice` -> `widget_error_no_device`.
///
/// The leading `android` is the marker that the string is Android's and is
/// dropped; the rest is the resource name the Kotlin and the provider XML
/// already use. Only `android` comes off and not the whole of [keyPrefix], so
/// the `Widget` survives into the name - this is not a general
/// `android<Surface>*` rule, and there is no other such prefix. A second
/// native surface wanting the same treatment wants its own selector, not a
/// looser one here.
String resourceName(String key) {
  if (!key.startsWith(keyPrefix)) {
    throw WidgetStringsError('$key is not a $keyPrefix* key.');
  }
  final tail = key.substring('android'.length);
  return tail[0].toLowerCase() +
      tail.substring(1).replaceAllMapped(
        RegExp('[A-Z]'),
        (match) => '_${match[0]!.toLowerCase()}',
      );
}

/// The resource directory an ARB locale's strings belong in.
///
/// `en` is the default `values/`, and everything else carries a qualifier:
/// `values-ru`, `values-pt-rBR`, `values-b+es+419`.
///
/// Bare language wherever the ARB name is bare, which is both what
/// `crowdin.yml` already decided for the filename - the main variant of every
/// family keeps the bare code - and what Android's guidance asks for:
/// resources belong under the most widely spoken parent dialect so that
/// resolution is direct rather than a walk over a region-pinned directory's
/// siblings.
///
/// **The legacy `-r` form takes a two-letter ISO 3166-1 region and nothing
/// else.** Everything else - a script, a UN M.49 numeric region, both at once
/// - can only be spelled in the BCP 47 `b+` form. `es_419` spelled
/// `values-es-r419` is not a stricter qualifier, it is a broken one, and the
/// resource merger says so: `Unrecognized part 'r419' in configuration
/// es-r419`. Measured, and the reason this takes the region's length into
/// account rather than its position.
String resourceDirectory(String locale) {
  if (locale == sourceLocale) return 'values';
  final parts = locale.split('_');
  final language = legacyLanguageCodes[parts.first] ?? parts.first;
  if (parts.length == 1) return 'values-$language';
  // A two-letter region is the only thing the `-r` form accepts.
  if (parts.length == 2 && RegExp(r'^[A-Za-z]{2}$').hasMatch(parts[1])) {
    return 'values-$language-r${parts[1].toUpperCase()}';
  }
  return 'values-b+$language+${parts.skip(1).join('+')}';
}

/// An ARB value as text, with ICU's quoting removed.
///
/// `l10n.yaml` sets `use-escaping: true`, so an ARB value is an ICU message
/// and the apostrophe is its escape character. Nine strings in `app_en.arb`
/// already rely on it - `"Can''t find my device"` - and `gen-l10n` renders
/// that as one apostrophe. Passing the raw text through would put **two** on
/// the widget beside an app showing one, with no build error and no failing
/// test. Belarusian needs apostrophes inside ordinary words and `app_be.arb`
/// holds eleven of them.
///
/// Two cases, and only two:
///
///  * `''` is a literal apostrophe.
///  * a matched pair quotes its contents, which is how `"'{z}/{x}'"` reaches
///    the app as `{z}/{x}` with the braces intact rather than as placeholders.
///
/// An *unmatched* apostrophe cannot reach here: `gen-l10n` refuses the file
/// with `ICU Lexing Error: Unmatched single quotes`, and it runs inside
/// `flutter pub get`, so the failure lands on every build and every pull
/// request. Measured, rather than assumed - it is the reason this does not try
/// to guess whether a lone apostrophe was meant literally.
String unescapeIcu(String value) {
  final out = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    if (value[i] != "'") {
      out.write(value[i]);
      continue;
    }
    if (i + 1 < value.length && value[i + 1] == "'") {
      out.write("'");
      i++;
    }
    // A single quote is ICU's quoting and contributes no character.
  }
  return out.toString();
}

/// XML's escapes and Android's, in the order that does not corrupt its own
/// output: the backslash first, so the ones added below are not escaped again,
/// then `&` before the brackets, so `&lt;` survives.
String escapeForAndroid(String value) {
  final text = value
      .replaceAll('\\', '\\\\')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll("'", "\\'")
      .replaceAll('"', '\\"');
  // A leading `@` or `?` is a reference to another resource or to a theme
  // attribute. No string here starts with either; a translation could.
  if (text.startsWith('@') || text.startsWith('?')) return '\\$text';
  return text;
}

/// The widget's strings in [decoded], keyed by resource name.
///
/// The prefix test is what drops the `@key` descriptors: a descriptor is named
/// `@androidWidgetDescription`, which does not start with the prefix, so the
/// value test never sees one. What the value test is for is a key that *is*
/// one of ours carrying something other than a string - a plural, a map,
/// whatever Crowdin starts emitting next. That is a pipeline defect wearing
/// the fallback's clothes, and is raised rather than dropped.
Map<String, String> widgetResources(String fileName, Map<String, Object?> decoded) {
  final found = <String, String>{};
  final from = <String, String>{};
  for (final entry in decoded.entries) {
    if (!entry.key.startsWith(keyPrefix)) continue;
    final value = entry.value;
    if (value is! String) {
      throw WidgetStringsError(
        '$fileName: ${entry.key} is a ${value.runtimeType}, not a string. '
        'A widget string cannot be a plural or a placeholder message - the '
        'launcher draws it with no arguments.',
      );
    }
    final name = resourceName(entry.key);
    // Two keys cannot share a resource name. `associate`-style last-wins would
    // drop one string with nothing said, and a set comparison on the other
    // side collapses the pair and still agrees.
    final earlier = from[name];
    if (earlier != null) {
      throw WidgetStringsError(
        '$fileName: ${entry.key} and $earlier both become @string/$name.',
      );
    }
    from[name] = entry.key;
    found[name] = unescapeIcu(value);
  }
  return found;
}

/// A `strings.xml` holding [strings], noting which ARB it came from.
String renderResources(String source, Map<String, String> strings) {
  final names = strings.keys.toList()..sort();
  final out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<!-- Generated from translations/$source by')
    ..writeln('     tool/widget_strings.dart. Do not edit, and do not check')
    ..writeln('     in: add or change a string in translations/app_en.arb,')
    ..writeln('     then translate it in Crowdin. -->')
    ..writeln('<resources>');
  for (final name in names) {
    // `formatted="false"` whenever the text holds a per-cent sign. aapt2 reads
    // one as the start of a format specifier and refuses a string with more
    // than one non-positional substitution - a translator's typo in Crowdin
    // breaking the Android release build days later and nowhere near them.
    // Nothing calls `getString` with arguments here, so saying these are not
    // format strings is simply true.
    final formatted = strings[name]!.contains('%') ? ' formatted="false"' : '';
    out.writeln(
      '    <string name="$name"$formatted>'
      '${escapeForAndroid(strings[name]!)}'
      '</string>',
    );
  }
  out.writeln('</resources>');
  return out.toString();
}

/// What one ARB file contributed.
class LocaleResult {
  LocaleResult(this.locale, this.written, this.absent);

  final String locale;

  /// How many of the widget's strings this locale carried.
  final int written;

  /// The resource names it did not, which Android takes from `values/`.
  final List<String> absent;

  /// Derived rather than stored: a field here could disagree with the function
  /// that is supposed to define it.
  String get directory => resourceDirectory(locale);
}

/// Reads [arbDir] and writes a `strings.xml` per locale under [outDir].
///
/// English is read first and its key set is the expectation every other locale
/// is reported against. Without that there is nothing to compare a translation
/// to, and "this locale has none of the ten" - which is a locale that was not
/// generated - is indistinguishable from the per-string fallback that is the
/// intended behaviour.
List<LocaleResult> generate({
  required Directory arbDir,
  required Directory outDir,
}) {
  if (!arbDir.existsSync()) {
    throw WidgetStringsError(
      '${arbDir.path} is not a directory. It is where l10n.yaml points '
      'arb-dir, and where the widget strings are read from.',
    );
  }

  final files = arbDir
      .listSync()
      .whereType<File>()
      .where((f) {
        final name = f.uri.pathSegments.last;
        return name.startsWith('app_') && name.endsWith('.arb');
      })
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (files.isEmpty) {
    throw WidgetStringsError('No app_*.arb files in ${arbDir.path}.');
  }

  Map<String, Object?> decode(File file) {
    final name = file.uri.pathSegments.last;
    final Object? parsed;
    try {
      parsed = jsonDecode(file.readAsStringSync());
    } on FormatException catch (error) {
      // Named, because the message a JSON decoder produces names an offset in
      // a file it does not identify, and there are eight of them.
      throw WidgetStringsError('$name is not valid JSON: ${error.message}');
    }
    if (parsed is! Map<String, Object?>) {
      throw WidgetStringsError(
        '$name is a ${parsed.runtimeType}, not a JSON object.',
      );
    }
    return parsed;
  }

  final source = files.firstWhere(
    (f) => f.uri.pathSegments.last == sourceName,
    orElse: () => throw WidgetStringsError(
      'No $sourceName in ${arbDir.path}. It is the source every other '
      'language is translated from, and the default values/ comes from it - '
      'without it the widget has no strings at all.',
    ),
  );
  final expected = widgetResources(sourceName, decode(source));
  if (expected.isEmpty) {
    throw WidgetStringsError(
      '$sourceName holds no $keyPrefix* string, so no widget resource would '
      'be written and @string/widget_description would not resolve. The '
      'strings live there.',
    );
  }

  if (outDir.existsSync()) {
    // A locale dropped from Crowdin has to stop having resources, or it keeps
    // its last translation for ever from a file nothing regenerates.
    outDir.deleteSync(recursive: true);
  }

  final results = <LocaleResult>[];
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final locale = name.substring('app_'.length, name.length - '.arb'.length);
    // English is already read: it is where `expected` came from, and nothing
    // mutates it. Decoding it again is a second pass over the largest file
    // here for a map that is identical.
    final strings = name == sourceName
        ? expected
        : widgetResources(name, decode(file));
    final absent = expected.keys.where((k) => !strings.containsKey(k)).toList()
      ..sort();

    if (strings.isNotEmpty) {
      final target = Directory('${outDir.path}/${resourceDirectory(locale)}')
        ..createSync(recursive: true);
      File('${target.path}/widget_strings.xml')
          .writeAsStringSync(renderResources(name, strings));
    }
    results.add(LocaleResult(locale, strings.length, absent));
  }
  return results;
}

/// The CLI the Gradle task calls.
void main(List<String> args) {
  String? arbDir;
  String? outDir;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--arb-dir':
        if (i + 1 < args.length) arbDir = args[++i];
      case '--out':
        if (i + 1 < args.length) outDir = args[++i];
      default:
        stderr.writeln('Unknown argument ${args[i]}.');
        exit(2);
    }
  }
  if (arbDir == null || outDir == null) {
    stderr.writeln(
      'usage: dart tool/widget_strings.dart --arb-dir <dir> --out <dir>',
    );
    exit(2);
  }

  final List<LocaleResult> results;
  try {
    results = generate(
      arbDir: Directory(arbDir),
      outDir: Directory(outDir),
    );
  } on WidgetStringsError catch (error) {
    stderr.writeln('Widget strings: $error');
    exit(1);
  }

  // Named, not counted. A count cannot say which locale was dropped, and
  // "the widget is English there" is the whole defect #319 was. This is the
  // only place that fact is reported, and it is the right one: it is a
  // statement about today's Crowdin progress rather than an invariant, so it
  // belongs in the build log and not in an assertion.
  for (final result in results) {
    if (result.written == 0) {
      stdout.writeln(
        'Widget strings: ${result.locale} has no $keyPrefix* string, so the '
        'widget is English there until Crowdin sends one.',
      );
      continue;
    }
    final fallback = result.absent.isEmpty
        ? ''
        : ', English for ${result.absent.join(', ')}';
    stdout.writeln(
      'Widget strings: ${result.locale} -> ${result.directory} '
      '(${result.written}$fallback)',
    );
  }
}
