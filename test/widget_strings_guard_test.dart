// Ties the home-screen widget's Android resources to the ARB keys they are
// generated from, the generator to the build that has to run it, and the
// widget's text to the app's.
//
// `tool/widget_strings.dart` is the generator and says why the widget's text
// has to be Android resources at all. `test/widget_strings_test.dart` tests
// that file directly. What neither can see is the wiring: whether the Gradle
// task still runs, whether the names the Kotlin asks for are the names the ARB
// produces, and whether a hand-written translation has come back.
//
// ## Why these are asserted from Dart
//
// Nothing else notices before a merge. `flutter analyze` and `flutter test`
// do not read Gradle - `analysis_options.yaml` excludes `android/**` outright
// - and no Android build runs on a pull request, which is what #35 is open
// about: `ci.yml`'s `pull_request` jobs are analyze and test, and
// `build-android` lives in `auto-release.yml`.
//
// That workflow does run on a push to `main`, and its `paths-ignore` covers
// only docs, markdown, issue templates, fastlane and LICENSE - so a change
// under `android/` or `translations/` is built on every merge. A break here
// therefore lands in the dev build minutes after the merge rather than days
// later in a release. Loud, and still after the fact: nothing says so while
// the change can still be reviewed.
//
// That makes the four wiring assertions below a stand-in for a build nobody
// runs on a pull request, and they pin Kotlin *spelling* rather than Kotlin
// behaviour. The honest fix is one job running `:app:processDebugResources` -
// which would also have caught both defects this change found, since each was
// found by running that task by hand. It is #35's to make, and until then
// this is the cheap half.
//
// `arb_locale_guard_test.dart` reads a shell script and a workflow from Dart
// for the same kind of seam. The gap is not the same one - a break in its
// subject is caught by the five jobs that run `pub get`, and its worry is a
// guard quietly becoming decoration - but the means are, and so is the
// reason: a repository invariant enforced by configuration no test reads.
//
// ## What is deliberately not asserted
//
// Which locales have the widget's strings yet. It is a statement about today's
// Crowdin progress, not an invariant, and it has no stable form: a
// half-translated language is correct and intended, so any threshold is
// arbitrary. A named budget of the waiting locales - the shape
// `translation_completeness_test.dart` uses for a different fact - was written
// and removed, because every one of the seven would be in it on day one (no
// signal), and it would then go red when a translation *succeeded*. The sync
// runs `pub get` and `analyze` and never `flutter test`, and its pull requests
// arrive as `github-actions[bot]` without triggering CI (#40), so the first
// thing to notice would be `ci.yml`'s `push: main` run, after the merge - and
// the entry could only be removed by committing to `l10n/crowdin`, which is
// the second-owner cost ADR 0016 exists to refuse and the very reason nothing
// generated here is checked in.
//
// The fact is reported where it belongs instead: `tool/widget_strings.dart`
// names every locale that has none, by name, on every build, and
// `crowdin_summary.py` puts per-language percentages in the sync's own pull
// request.
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/localization/gen/l10n_generated.dart';

import '../tool/widget_strings.dart';
import 'arb.dart';
import 'source_files.dart';

/// The generated getter for each of the widget's strings.
///
/// Hand-written because Dart has no reflection here, and checked for
/// completeness against the ARB below - so a key added without a line here
/// fails rather than going unchecked.
final Map<String, String Function(L10n)> _getters =
    <String, String Function(L10n)>{
      'androidWidgetDescription': (l) => l.androidWidgetDescription,
      'androidWidgetChooseKey': (l) => l.androidWidgetChooseKey,
      'androidWidgetStateConnecting': (l) => l.androidWidgetStateConnecting,
      'androidWidgetStateEmulating': (l) => l.androidWidgetStateEmulating,
      'androidWidgetStateSending': (l) => l.androidWidgetStateSending,
      'androidWidgetStateSent': (l) => l.androidWidgetStateSent,
      'androidWidgetErrorNoDevice': (l) => l.androidWidgetErrorNoDevice,
      'androidWidgetErrorBusy': (l) => l.androidWidgetErrorBusy,
      'androidWidgetErrorFile': (l) => l.androidWidgetErrorFile,
      'androidWidgetErrorFailed': (l) => l.androidWidgetErrorFailed,
    };

/// The attribute that declares a string resource, however it is spelled.
///
/// Any attribute order, any spacing, either quote: all three are legal XML
/// that aapt2 accepts, and a pattern matching only the tidy spelling let the
/// untidy one through.
const String _stringNameAttribute = '<string\\b[^>]*\\bname\\s*=\\s*["\']';

final RegExp _anyStringDeclaration = RegExp(_stringNameAttribute);

/// The same rule, narrowed to the names the generator owns. Built from the
/// pattern above rather than restated, so a fix to the attribute matching is
/// made once.
final RegExp _widgetStringDeclaration = RegExp(
  '${_stringNameAttribute}widget_',
);

/// Strings that already carry ICU quoting, with their generated getters.
///
/// The agreement check below would be worthless without them: none of the ten
/// widget strings carries an apostrophe yet - English has none, and no
/// translation has the keys - so an `unescapeIcu` that simply returned its
/// input would pass. These six carry both of ICU's cases between them, in
/// every locale:
///
///  * `''` for a literal apostrophe - `"Can''t find my device"`,
///    `"Гэты камп''ютар"`, `"Цей комп''ютер"`;
///  * a matched pair quoting its contents, which is how `"'{z}/{x}/{y}'"`
///    reaches the app with its braces intact instead of as placeholders -
///    `mapCustomUrlHint` and `mapSubdomainsEmpty`, in all eight.
///
/// They are not the widget's strings and are not generated into resources.
/// They are here because they are the evidence that this file's unescaping and
/// `gen-l10n`'s agree, which is the property the widget depends on.
final Map<String, String Function(L10n)> _icuWitnesses =
    <String, String Function(L10n)>{
      'pickerCantFindDevice': (l) => l.pickerCantFindDevice,
      'firmwareWhatsNew': (l) => l.firmwareWhatsNew,
      'firmwareChangelogUnstyled': (l) => l.firmwareChangelogUnstyled,
      'fliblerGroupThisComputer': (l) => l.fliblerGroupThisComputer,
      'mapCustomUrlHint': (l) => l.mapCustomUrlHint,
      'mapSubdomainsEmpty': (l) => l.mapSubdomainsEmpty,
    };

Set<String>? _referencedCache;

/// The `widget_*` string resources the Android sources ask for.
///
/// Both spellings, because the two callers use different ones:
/// `KeyWidgetRenderer` says `R.string.widget_state_sent`, and
/// `res/xml/key_widget_info.xml` - the provider XML the merged manifest points
/// at - says `@string/widget_description`.
///
/// Restricted to `widget_` so that `app_name`, which is deliberately not in
/// the ARB, is not swept in. `R.dimen.widget_corner_radius` is excluded by the
/// `R.string.` prefix rather than by this, whatever its name looks like.
///
/// Memoized: three cases read it, and each call is two `git ls-files` spawns
/// plus forty files.
Set<String> resourcesReferenced() => _referencedCache ??= _scanReferences();

Set<String> _scanReferences() {
  final referenced = <String>{};
  final patterns = [
    RegExp(r'R\.string\.(widget_[a-z0-9_]+)'),
    RegExp(r'@string/(widget_[a-z0-9_]+)'),
  ];
  final paths = [
    ...gitVisibleFiles('android/app/src/*.kt'),
    ...gitVisibleFiles('android/app/src/*.xml'),
  ];
  for (final path in paths) {
    final text = File(path).readAsStringSync();
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        referenced.add(match.group(1)!);
      }
    }
  }
  return referenced;
}

/// `build.gradle.kts` with its comments removed.
///
/// This file explains itself at length and names the task in prose several
/// times over, so an assertion matched against the whole text can be satisfied
/// by the paragraph above the thing it was meant to find. That is not
/// hypothetical: `arb_locale_guard_test.dart`'s header records the same guard
/// going green through a deleted step.
///
/// Block comments as well as line comments, and a trailing `//` as well as a
/// whole line of one. Stripping only whole-line `//` left two ways past:
/// "comment the block out", which an editor does in one keystroke, and a
/// trailing comment that quotes the very text an assertion looks for.
///
/// `native_struct_mirror_test.dart` has a sibling stripper with the same block
/// pattern and a different `//` rule. Sharing them means choosing one
/// behaviour for both and re-checking what that test detects, so it is a task
/// of its own rather than a change made in passing.
String gradleCode() =>
    File('android/app/build.gradle.kts')
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'//.*$'), ''))
        .join('\n');

/// The ARB a locale's strings are read from.
File arbFor(Locale locale) {
  final country = locale.countryCode;
  final suffix = country == null || country.isEmpty ? '' : '_$country';
  return File('$kArbDir/app_${locale.languageCode}$suffix.arb');
}

void main() {
  late Set<String> fromArb;
  late Map<String, String> english;

  setUpAll(() {
    english = arbStrings(File('$kArbDir/app_en.arb'));
    // Through the generator's own selector rather than a second copy of the
    // prefix-and-rename rule. A third definition is what let the first draft
    // of this change pass while its generator was broken.
    fromArb = widgetResources('app_en.arb', english).keys.toSet();
  });

  test('there is something to check', () {
    // Most of what follows is a set comparison or an `isEmpty`, and two empty
    // sets are equal: a glob that stopped matching, or a prefix nobody uses
    // any more, would otherwise pass this whole file in silence.
    expect(english, isNotEmpty);
    expect(
      fromArb,
      isNotEmpty,
      reason:
          'no $keyPrefix* key in app_en.arb, so this file proves nothing - '
          'either the prefix changed on both sides or the strings are gone',
    );
    expect(
      resourcesReferenced(),
      isNotEmpty,
      reason:
          'the scan found no widget_* resource reference under '
          'android/app/src, so it found nothing to compare',
    );
    expect(
      gitVisibleFiles('android/app/src/*/res/values-*/*.xml'),
      isNotEmpty,
      reason:
          'the qualified-resource glob resolves to nothing, so the case below '
          'that asserts those files are clean asserts about an empty list',
    );
  });

  test('every resource the widget asks for is an ARB key', () {
    final missing = resourcesReferenced().difference(fromArb);
    expect(
      missing,
      isEmpty,
      reason:
          'the Kotlin or the provider XML asks for a string the generator '
          'will not write, so the resource does not exist - and no build that '
          'would say so runs on a pull request (#35). Add the key to '
          'translations/app_en.arb: widget_error_busy is '
          'androidWidgetErrorBusy',
    );
  });

  test('every ARB key the generator writes is asked for', () {
    final unused = fromArb.difference(resourcesReferenced());
    expect(
      unused,
      isEmpty,
      reason:
          'an $keyPrefix* string nothing reads is shipped in every APK and '
          'sent to seven languages to translate. Either the Kotlin lost its '
          'read - in which case the widget silently stopped saying something '
          '- or the key outlived its caller and belongs deleted',
    );
  });

  test('the build still generates them', () {
    final code = gradleCode();
    // Four separate failures with one symptom: a task that is not registered
    // does not compile; one nothing consumes writes a directory no variant
    // reads; one pointed at another script writes nothing; and a generator
    // that is not there cannot run. All four end at a resource missing from
    // the APK.
    expect(
      code,
      contains(
        'tasks.register<GenerateWidgetStrings>("generateWidgetStrings")',
      ),
      reason: 'the generator is gone, and with it every widget string',
    );
    expect(
      code,
      stringContainsInOrder([
        'addGeneratedSourceDirectory(',
        'generateWidgetStrings,',
        'GenerateWidgetStrings::outputDirectory',
      ]),
      reason:
          'the generated directory is no longer registered on the variant, so '
          'the task runs and nothing reads what it wrote',
    );
    expect(
      code,
      contains(
        'generator.set(File(repositoryRoot, "tool/widget_strings.dart"))',
      ),
      reason:
          'the task no longer runs the generator this suite tests. Matched on '
          'the assignment rather than on the path, because the path also '
          "appears in the task's own failure message - a string literal in "
          'code - and a bare contains() was satisfied by that: the mutation '
          'pointing the task at another script survived until this was '
          'tightened',
    );
    expect(
      File('tool/widget_strings.dart').existsSync(),
      isTrue,
      reason: 'the generator the task names is not there',
    );
  });

  test('no translation is written by hand again', () {
    // #319's actual defect. `check_translation_sources.sh` refuses a hand edit
    // to a Crowdin-owned ARB; there was no equivalent here, so
    // `values-ru/strings.xml` sat beside the pipeline from the day the widget
    // landed - four days before that guard existed at all - and the other
    // languages were simply never done.
    //
    // Every `.xml` in a qualified directory, not just `strings.xml`: Android
    // reads them all, and a second writer is one whatever it is called. A
    // `<string>` has no business in any of them now - the app's come from the
    // ARB through `gen-l10n`, the widget's are generated, and `app_name` lives
    // in the unqualified `values/`.
    final declaring = gitVisibleFiles('android/app/src/*/res/values-*/*.xml')
        .where(
          (p) => _anyStringDeclaration.hasMatch(File(p).readAsStringSync()),
        )
        .toList();
    expect(
      declaring,
      isEmpty,
      reason:
          'a hand-written Android translation is a second writer that Crowdin '
          'never sees and nothing reverts. Add the string to '
          'translations/app_en.arb and translate it in Crowdin instead',
    );
  });

  test('no widget string is declared in a checked-in resource file', () {
    // Measured, because the obvious assumption is wrong: a hand-written copy
    // of a generated string does **not** fail the build. From a clean merge
    // state `:app:mergeDebugResources` accepts the pair and exits 0, and which
    // copy reaches the resource table depends on the order AGP consults its
    // data sets - the generated directory is a separate, earlier set than
    // `src/main/res`. Two runs here disagreed on the winner.
    //
    // So nothing downstream reliably catches this. That is the reason this
    // case exists, not a reason it is redundant.
    final declaring = gitVisibleFiles('android/app/src/*/res/*.xml')
        .where(
          (p) => _widgetStringDeclaration.hasMatch(File(p).readAsStringSync()),
        )
        .toList();
    expect(
      declaring,
      isEmpty,
      reason:
          'these files declare a widget_* string the generator also writes, '
          'and the build will not refuse the pair. app_name is the only '
          'string that belongs in res/values/strings.xml, because it is the '
          'one that is never translated',
    );
  });

  test('app_name is still there to be the exception', () {
    // The product's name, in every language. It is the reason
    // res/values/strings.xml still exists at all, and the file was emptied
    // down to it - so "it is still there" is the assertion worth having.
    // Without it `AndroidManifest.xml`'s `android:label="@string/app_name"`
    // fails to link - in the dev build, after the merge.
    expect(
      File('android/app/src/main/res/values/strings.xml').readAsStringSync(),
      contains('name="app_name"'),
      reason: 'app_name is the one string the generator does not write',
    );
    expect(
      english.keys,
      isNot(contains('${keyPrefix}AppName')),
      reason:
          'putting the product name in the ARB offers it to seven languages '
          'to translate, which is the one thing it must never be',
    );
  });

  group('the widget draws what the app would', () {
    test('every widget string has a getter named here', () {
      // The map below is hand-written, so this is what stops it going stale:
      // a key added to the ARB without a line there would otherwise be
      // excluded from the comparison rather than failing it.
      expect(_getters.keys.map(resourceName).toSet(), fromArb);
    });

    test('the generator unescapes exactly as gen-l10n does', () {
      // `unescapeIcu` is a second implementation of ICU quoting in this
      // repository; `gen-l10n` owns the first, and the two have to agree per
      // string per locale or the widget says something the app does not.
      // Passing the raw text through is the defect this change fixed, and it
      // is invisible in English, where no translator looks.
      //
      // Asserted against the authority rather than a table of expected
      // values, which would be the same "re-derived the rule" mistake the
      // Kotlin draft made.
      var compared = 0;
      var carriedQuoting = 0;
      for (final locale in L10n.supportedLocales) {
        final file = arbFor(locale);
        if (!file.existsSync()) continue;
        final strings = arbStrings(file);
        final l10n = lookupL10n(locale);
        for (final entry in {..._getters, ..._icuWitnesses}.entries) {
          final raw = strings[entry.key];
          // Absent means untranslated, and gen-l10n fills the getter from
          // English while the generator writes nothing - so there is nothing
          // to compare, by design.
          if (raw == null) continue;
          compared++;
          if (raw.contains("'")) carriedQuoting++;
          expect(
            unescapeIcu(raw),
            entry.value(l10n),
            reason:
                '${entry.key} in ${file.uri.pathSegments.last} reaches the '
                'widget differently from how it reaches the app',
          );
        }
      }
      expect(
        compared,
        greaterThan(0),
        reason:
            'nothing was compared at all - arbFor stopped finding the files, '
            'or supportedLocales is empty',
      );
      expect(
        carriedQuoting,
        greaterThan(0),
        reason:
            'every string compared was free of apostrophes, so this case '
            'would pass with an unescapeIcu that returned its input. The '
            'witnesses above have been reworded in Crowdin; pick new ones '
            'rather than leaving the check toothless',
      );
    });
  });
}
