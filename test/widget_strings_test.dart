// `tool/widget_strings.dart`, the generator behind the home-screen widget's
// Android string resources.
//
// This tests the real implementation rather than a likeness of it, which is
// the whole reason the generator is Dart and not Kotlin inside
// `android/app/build.gradle.kts`. It was Kotlin first. `analysis_options.yaml`
// excludes `android/**`, nothing here runs Kotlin tests, and the Android build
// runs only at release time (#35) - so the rule sat where no test could reach
// it, and the guard test beside this one re-derived the same rule in Dart and
// compared its own copy against the *callers*. Breaking the generator's own
// `resourceName` left every case green.
//
// Two of the cases below are regressions for defects that draft shipped, both
// found by review rather than by reading, and both measured against the real
// toolchain before being written down:
//
//  * `es_419` was spelled `values-es-r419`, which the resource merger refuses
//    with `Unrecognized part 'r419' in configuration es-r419`;
//  * ICU quoting was passed through, so `"Can''t"` reached the widget as
//    `Can''t` beside an app showing `Can't`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/widget_strings.dart';

void main() {
  group('resourceName', () {
    test('drops the android marker and snake-cases the rest', () {
      expect(resourceName('androidWidgetDescription'), 'widget_description');
      expect(resourceName('androidWidgetChooseKey'), 'widget_choose_key');
      expect(
        resourceName('androidWidgetStateConnecting'),
        'widget_state_connecting',
      );
      expect(
        resourceName('androidWidgetErrorNoDevice'),
        'widget_error_no_device',
      );
    });

    test('refuses a key that is not the widget\'s', () {
      // The prefix is the selector, so a key without it reaching here is a
      // caller that stopped filtering rather than a name to guess at.
      expect(
        () => resourceName('widgetGroupTheme'),
        throwsA(isA<WidgetStringsError>()),
      );
    });
  });

  group('resourceDirectory', () {
    test('English is the default values/', () {
      expect(resourceDirectory('en'), 'values');
    });

    test('a bare language is a bare qualifier', () {
      // What `crowdin.yml` already chose for the filename - the main variant
      // of every family keeps the bare code - and what Android asks for, so
      // that a ru-KZ phone resolves ru directly.
      expect(resourceDirectory('ru'), 'values-ru');
      expect(resourceDirectory('uk'), 'values-uk');
      expect(resourceDirectory('be'), 'values-be');
    });

    test('a two-letter region takes the legacy -r form', () {
      expect(resourceDirectory('pt_BR'), 'values-pt-rBR');
      expect(resourceDirectory('es_MX'), 'values-es-rMX');
      expect(resourceDirectory('fr_CA'), 'values-fr-rCA');
    });

    test('a numeric region can only be BCP 47', () {
      // The regression. `values-es-r419` is not a stricter qualifier, it is a
      // broken one: `Unrecognized part 'r419' in configuration es-r419`, from
      // `:app:mergeDebugResources`. Crowdin's "Spanish, Latin America" is
      // `es-419`, and `crowdin.yml` already maps the same shape for pt-BR, so
      // this is one enabled language away rather than hypothetical.
      expect(resourceDirectory('es_419'), 'values-b+es+419');
      expect(resourceDirectory('pt_001'), 'values-b+pt+001');
    });

    test('a script can only be BCP 47', () {
      expect(resourceDirectory('sr_Latn'), 'values-b+sr+Latn');
      expect(resourceDirectory('zh_Hans'), 'values-b+zh+Hans');
    });

    test('a script and a region together', () {
      expect(resourceDirectory('zh_Hant_TW'), 'values-b+zh+Hant+TW');
    });

    test('three languages keep the spelling Android resolves', () {
      // Hebrew, Indonesian and Yiddish. None is enabled; the day one is,
      // `values-he/` would be a directory the platform never consults.
      expect(resourceDirectory('he'), 'values-iw');
      expect(resourceDirectory('id'), 'values-in');
      expect(resourceDirectory('yi'), 'values-ji');
      // And the legacy code applies to the language part only.
      expect(resourceDirectory('he_IL'), 'values-iw-rIL');
    });
  });

  group('unescapeIcu', () {
    test('a doubled apostrophe is one apostrophe', () {
      // `l10n.yaml` sets `use-escaping: true`, and nine strings in
      // app_en.arb already rely on it. gen-l10n renders `Can''t find my
      // device` as `Can't find my device`; so does this.
      expect(unescapeIcu("Can''t find my device"), "Can't find my device");
      // Belarusian needs the apostrophe inside ordinary words, and app_be.arb
      // already holds eleven of them written this way.
      expect(unescapeIcu("Гэты камп''ютар"), "Гэты камп'ютар");
    });

    test('a matched pair quotes its contents', () {
      // How `"'{z}/{x}'"` reaches the app as literal braces rather than as
      // placeholders.
      expect(unescapeIcu("'{z}/{x}/{y}', plus '{s}'"), '{z}/{x}/{y}, plus {s}');
    });

    test('text with no apostrophe is unchanged', () {
      expect(unescapeIcu('Flipper not found'), 'Flipper not found');
      expect(unescapeIcu('Connecting…'), 'Connecting…');
    });

    test('a trailing quote is quoting, and contributes nothing', () {
      // The boundary no other case reaches: with the quote last,
      // `i + 1 < value.length` is false, so this is the only input that
      // exercises that arm. The doubled form at the same position is the
      // other one.
      expect(unescapeIcu("ends with one'"), 'ends with one');
      expect(unescapeIcu("ends with one''"), "ends with one'");
    });
  });

  group('escapeForAndroid', () {
    test('escapes XML and Android in an order that does not eat itself', () {
      // The backslash first, so the ones added for the quotes are not escaped
      // again; `&` before the brackets, so `&lt;` survives as `&amp;lt;`.
      expect(escapeForAndroid('a\\b'), 'a\\\\b');
      expect(escapeForAndroid('Rock & roll'), 'Rock &amp; roll');
      expect(escapeForAndroid('<b>'), '&lt;b&gt;');
      expect(escapeForAndroid('&lt;'), '&amp;lt;');
      expect(escapeForAndroid("Can't"), "Can\\'t");
      expect(escapeForAndroid('say "x"'), 'say \\"x\\"');
    });

    test('a leading @ or ? is escaped, because it is a reference', () {
      expect(escapeForAndroid('@home'), '\\@home');
      expect(escapeForAndroid('?theme'), '\\?theme');
      // Only leading.
      expect(escapeForAndroid('at @home'), 'at @home');
    });
  });

  group('renderResources', () {
    test('names are sorted, so the file does not churn', () {
      final xml = renderResources('app_en.arb', {
        'widget_state_sent': 'Sent',
        'widget_choose_key': 'Choose a key',
      });
      expect(
        xml.indexOf('widget_choose_key'),
        lessThan(xml.indexOf('widget_state_sent')),
      );
    });

    test('says which ARB it came from, and not to edit it', () {
      final xml = renderResources('app_ru.arb', {'widget_state_sent': 'x'});
      expect(xml, contains('app_ru.arb'));
      expect(xml, contains('Do not edit'));
    });

    test('a per-cent sign makes the string not a format string', () {
      // aapt2 reads `%` as the start of a format specifier and refuses a
      // string with more than one non-positional substitution - a translator's
      // typo breaking the release build, days later and nowhere near them.
      // Nothing calls getString with arguments, so this is simply true.
      final xml = renderResources('app_en.arb', {'widget_x': '100% done'});
      expect(xml, contains('<string name="widget_x" formatted="false">'));
      final plain = renderResources('app_en.arb', {'widget_x': 'done'});
      expect(plain, contains('<string name="widget_x">'));
      expect(plain, isNot(contains('formatted')));
    });
  });

  group('widgetResources', () {
    test('takes the widget keys and leaves everything else', () {
      final found = widgetResources('app_en.arb', {
        'androidWidgetStateSent': 'Sent',
        '@androidWidgetStateSent': {'description': 'ignored'},
        'widgetGroupTheme': 'Theme',
        'homeWidgetPin': 'Home screen',
        '@@locale': 'en',
      });
      expect(found, {'widget_state_sent': 'Sent'});
    });

    test('unescapes as it goes', () {
      final found = widgetResources('app_be.arb', {
        'androidWidgetErrorBusy': "Flipper не з''явіўся",
      });
      expect(found['widget_error_busy'], "Flipper не з'явіўся");
    });

    test('a widget key that is not a string is a defect, not a fallback', () {
      // Absence is the designed fallback. A key that is present carrying a
      // plural or a map is the pipeline having changed under us, and dropping
      // it silently is how the widget goes back to English without saying so.
      expect(
        () => widgetResources('app_ru.arb', {
          'androidWidgetStateSent': {'other': 'x'},
        }),
        throwsA(isA<WidgetStringsError>()),
      );
    });

    test('two keys cannot claim one resource name', () {
      // Last-wins would drop a string with nothing said, and a set comparison
      // on the other side collapses the pair and still agrees.
      expect(
        () => widgetResources('app_en.arb', {
          'androidWidgetFooBar': 'a',
          'androidWidgetFoo_bar': 'b',
        }),
        throwsA(isA<WidgetStringsError>()),
      );
    });
  });

  group('generate', () {
    late Directory work;
    late Directory arb;
    late Directory out;

    setUp(() {
      work = Directory.systemTemp.createTempSync('widget-strings-test');
      arb = Directory('${work.path}/translations')..createSync();
      out = Directory('${work.path}/out');
    });

    tearDown(() => work.deleteSync(recursive: true));

    void writeArb(String locale, String body) {
      File('${arb.path}/app_$locale.arb').writeAsStringSync(body);
    }

    void writeWidgetArb(String locale, Map<String, String> strings) {
      final entries = strings.entries
          .map((e) => '  "${e.key}": "${e.value}"')
          .join(',\n');
      writeArb(locale, '{\n  "@@locale": "$locale",\n$entries\n}\n');
    }

    test('English fills the unqualified values/', () {
      writeWidgetArb('en', {'androidWidgetStateSent': 'Sent'});
      final results = generate(arbDir: arb, outDir: out);
      expect(
        File('${out.path}/values/widget_strings.xml').readAsStringSync(),
        contains('<string name="widget_state_sent">Sent</string>'),
      );
      expect(results.single.locale, 'en');
      expect(results.single.written, 1);
    });

    test('a translation lands under its own qualifier', () {
      writeWidgetArb('en', {'androidWidgetStateSent': 'Sent'});
      writeWidgetArb('ru', {'androidWidgetStateSent': 'Отправлено'});
      generate(arbDir: arb, outDir: out);
      expect(
        File('${out.path}/values-ru/widget_strings.xml').readAsStringSync(),
        contains('Отправлено'),
      );
    });

    test('a locale with none of them gets no file, and is reported', () {
      // The state this change shipped in: the keys are new, so no translation
      // has them yet. Android then takes every string from values/, which is
      // correct - but it has to be *said*, because it is indistinguishable
      // from the pipeline having broken, and that is #319 itself.
      writeWidgetArb('en', {'androidWidgetStateSent': 'Sent'});
      writeArb('ru', '{"@@locale": "ru", "somethingElse": "x"}');
      final results = generate(arbDir: arb, outDir: out);
      expect(Directory('${out.path}/values-ru').existsSync(), isFalse);
      final russian = results.firstWhere((r) => r.locale == 'ru');
      expect(russian.written, 0);
      expect(russian.absent, ['widget_state_sent']);
    });

    test('a half-translated locale reports what falls back', () {
      writeWidgetArb('en', {
        'androidWidgetStateSent': 'Sent',
        'androidWidgetErrorBusy': 'Flipper is busy',
      });
      writeWidgetArb('ru', {'androidWidgetStateSent': 'Отправлено'});
      final results = generate(arbDir: arb, outDir: out);
      final russian = results.firstWhere((r) => r.locale == 'ru');
      expect(russian.written, 1);
      expect(russian.absent, ['widget_error_busy']);
      // The one it has, and not the one it does not: Android fills the gap
      // from values/ per string.
      final xml = File('${out.path}/values-ru/widget_strings.xml')
          .readAsStringSync();
      expect(xml, contains('widget_state_sent'));
      expect(xml, isNot(contains('widget_error_busy')));
    });

    test('a locale dropped from Crowdin loses its resources', () {
      writeWidgetArb('en', {'androidWidgetStateSent': 'Sent'});
      writeWidgetArb('ru', {'androidWidgetStateSent': 'Отправлено'});
      generate(arbDir: arb, outDir: out);
      expect(Directory('${out.path}/values-ru').existsSync(), isTrue);

      File('${arb.path}/app_ru.arb').deleteSync();
      generate(arbDir: arb, outDir: out);
      expect(
        Directory('${out.path}/values-ru').existsSync(),
        isFalse,
        reason:
            'a stale directory nothing regenerates keeps its last translation '
            'for ever, and ships it',
      );
    });

    test('no English ARB is a failure that names it', () {
      writeWidgetArb('ru', {'androidWidgetStateSent': 'Отправлено'});
      expect(
        () => generate(arbDir: arb, outDir: out),
        throwsA(
          isA<WidgetStringsError>().having(
            (e) => e.message,
            'message',
            contains('app_en.arb'),
          ),
        ),
      );
    });

    test('English without the strings is a failure, not an empty build', () {
      // Otherwise the build goes on and fails at `@string/widget_description`,
      // naming a resource rather than the reason it is missing.
      writeArb('en', '{"@@locale": "en", "somethingElse": "x"}');
      expect(
        () => generate(arbDir: arb, outDir: out),
        throwsA(isA<WidgetStringsError>()),
      );
    });

    test('malformed JSON names the file it could not read', () {
      // A decoder's own message names an offset in a file it does not
      // identify, and there are eight of them.
      writeWidgetArb('en', {'androidWidgetStateSent': 'Sent'});
      writeArb('ru', '{"@@locale": "ru", ');
      expect(
        () => generate(arbDir: arb, outDir: out),
        throwsA(
          isA<WidgetStringsError>().having(
            (e) => e.message,
            'message',
            contains('app_ru.arb'),
          ),
        ),
      );
    });

    test('a missing ARB directory says so', () {
      expect(
        () => generate(arbDir: Directory('${work.path}/nope'), outDir: out),
        throwsA(isA<WidgetStringsError>()),
      );
    });

    test('an ARB directory with no app_*.arb says so', () {
      File('${arb.path}/notes.txt').writeAsStringSync('x');
      expect(
        () => generate(arbDir: arb, outDir: out),
        throwsA(isA<WidgetStringsError>()),
      );
    });
  });
}
