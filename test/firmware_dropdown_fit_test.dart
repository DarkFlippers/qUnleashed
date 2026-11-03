import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/widgets/firmware_card.dart';
import 'package:qunleashed/theme/theme.dart';

/// Built once. `ThemeData()` is not free and nothing here varies it, so every
/// case would otherwise pay for the same answer.
final ThemeData _theme = buildAppTheme(
  Brightness.dark,
  const Color(0xFFCC241D),
);

/// The gap `SettingsDropdown` keeps between the title and the dropdown, and
/// the room it insists on before it will keep both on one line. Its own
/// `_gap` is private; this is the number that one has to be.
const double _gap = 8;

/// The channel title #463's screenshot was taken with.
///
/// It is **server data** - `directory.dart` reads it out of the firmware
/// feed - which is why no width picked in the widget and no ARB kept short
/// would have fixed this: nothing in `translations/` or in this repository
/// decides how long it is. Nothing pins the longest one the feed can ship
/// either, so this is a length that has been seen rather than a bound.
const String _longChannel = 'Stable Release Channel';

/// That the firmware card's two setting rows keep both of their strings whole
/// at every text size.
///
/// The title was an `Expanded` beside an inflexible dropdown, so the dropdown
/// took its full intrinsic width - its value plus 22 of padding and border,
/// the 6 before the chevron and the chevron's 18, none of which follows the
/// text scaler - and the title got what was left. At a scaler of 2 that was
/// about one glyph, and `Text` with no `maxLines` wrapped per character:
/// "Update Channel" drawn as a vertical column of letters, tall enough to
/// push the build-variant row and the update button off the screen. #463.
///
/// ## No width here is a phone's
///
/// `flutter_test` renders every glyph as a square of the font size, about
/// twice what Roboto gives at the same size - `nav_bar_label_fit_test.dart`
/// has the measurement that ratio comes from. So the boxes here are chosen
/// through it rather than as phone widths: 600 is roughly what this font
/// spends where Roboto spends the ~292 dp of card interior on a 320 dp phone,
/// and 900 is deliberately wider than any phone's card, as the width where a
/// row has room to spare. Neither mapping is derived anywhere; they are two
/// widths far enough apart that the arrangement differs between them.
///
/// It also means the eight locale cases are eight label-*length* cases with
/// diagnostic names, since width here is exactly proportional to glyph count.
/// That is the trade, and it is why they are named after locales rather than
/// claiming to render like them.
///
/// What the file checks is the contract, which holds in any font:
///
///  * nothing overflows at any scaler;
///  * the title and the value share a line while both fit it whole, with
///    [_gap] to spare and no more;
///  * below that the title moves **above** the dropdown rather than being
///    squeezed, and is still a word rather than a column of letters.
void main() {
  /// Pumps one dropdown with [title] and [value] in a [box]-wide slot.
  ///
  /// A null [value] is the placeholder path, which is what the card shows on
  /// every cold open - `firmwareLoading` while the directory is in flight,
  /// then `firmwareUnavailable` if it never arrives.
  ///
  /// `SettingsDropdown` is `@visibleForTesting` and takes its strings as
  /// plain `String`s, so no localization delegate is wired up here: the
  /// per-locale group below passes the ARB values in directly, which is also
  /// what the card does.
  Future<void> pump(
    WidgetTester tester, {
    required String title,
    required String? value,
    String placeholder = 'Unavailable',
    double box = 600,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: box,
              child: SettingsDropdown<String>(
                title: title,
                value: value,
                items: const ['one', 'two'],
                labelOf: (item) => item,
                descriptionOf: (item) => 'about $item',
                accent: const Color(0xFFCC241D),
                placeholder: placeholder,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// How many lines [text] was laid out over. One glyph per line is what the
  /// bug looked like.
  ///
  /// The height it took over the height it would take with room for one line,
  /// because `RenderParagraph` keeps its `TextPainter` private and so answers
  /// no line count directly. Its intrinsics are public, and
  /// `getMinIntrinsicHeight(infinity)` is one line of this exact span - font,
  /// scaler and strut included - rather than a number modelled here. It is
  /// measured on a painter of its own, so asking does not disturb the one
  /// that painted.
  ///
  /// A hard break would defeat it - `'\n'` survives an unbounded layout, so
  /// the denominator would be two lines and the answer half the truth. No
  /// string in this file or in `translations/` has one; the assert is what
  /// says the helper knows it cannot take one.
  int lines(WidgetTester tester, String text) {
    assert(!text.contains('\n'), 'lines() cannot measure a hard break');
    final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    return (paragraph.size.height /
            paragraph.getMinIntrinsicHeight(double.infinity))
        .round();
  }

  /// The most lines [text] can take without being broken mid-word: one per
  /// place a line may break, which is each space and each hyphen, plus one.
  ///
  /// This is the contract that says the bug is gone, and it holds in any
  /// font: "Update Channel" may take two lines and took fourteen. It is a
  /// bound rather than a count, because how many words fit a line is the
  /// font's business and none of these widths is a phone's.
  ///
  /// The one thing it does not cover is a single word wider than the line it
  /// is on - "actualización" at a scaler of 3.1 in the narrower of the two
  /// boxes here - which every layout breaks mid-word and this fix does not
  /// change. Giving the title its own line is what makes that rare rather
  /// than the normal case.
  int wrapSlots(String text) =>
      1 + text.split('').where((c) => c == ' ' || c == '-').length;

  /// The dropdown's border box, which is what the title keeps its gap from.
  ///
  /// Its value text would be the wrong edge: the 10 of padding inside the
  /// border would stand in for the gap and leave every arithmetic mistake
  /// looking like a pass.
  Rect chipOf(WidgetTester tester) => tester.getRect(
    find.descendant(of: find.byType(InkWell), matching: find.byType(Container)),
  );

  /// Whether the title sits above the dropdown rather than beside it.
  ///
  /// Read off the painted rects rather than off the widget tree: which
  /// arrangement the `Wrap` chose is the thing under test, and a finder for
  /// `Row` or `Column` would match the ones the card puts this inside.
  ///
  /// Discriminating in both directions, the bug's shape included: a row whose
  /// title has wrapped to fourteen lines is still centred on the dropdown, so
  /// its bottom is below the dropdown's top and this correctly reads "not
  /// stacked".
  bool stacked(WidgetTester tester, String title) =>
      tester.getRect(find.text(title)).bottom <= chipOf(tester).top;

  group('while both strings fit', () {
    // Also the premise for "the title goes above the dropdown" below, which
    // pumps these same two strings in this same box at a scaler of 2: this is
    // what says the scaler is what moved it and not the strings.
    testWidgets('they share a line', (tester) async {
      await pump(tester, title: 'Update Channel', value: 'Stable');
      expect(tester.takeException(), isNull);
      expect(stacked(tester, 'Update Channel'), isFalse);
      expect(lines(tester, 'Update Channel'), 1);
      expect(lines(tester, 'Stable'), 1);
    });

    // The dropdown is held against the trailing edge while the two share a
    // run, which is what the `Expanded` the fix removed used to do.
    testWidgets('the dropdown stays against the trailing edge', (tester) async {
      await pump(tester, title: 'Update Channel', value: 'Stable', box: 600);
      final slot = tester.getRect(find.byType(SettingsDropdown<String>));
      // The widget's own 2 of horizontal padding is the only thing between
      // them.
      expect(chipOf(tester).right, closeTo(slot.right - 2, 0.01));
    });

    // **The boundary, which is where everything about the fit is decided.**
    // Anywhere else there is slack, and slack hides an arithmetic that is a
    // few pixels out - which is what the draft before this one was, by the
    // two pixels of `Border.all` that `Container` adds outside its padding.
    //
    // So the narrowest width the row survives is searched for rather than
    // written down - it is a property of the font, and no number here is a
    // phone's - and the claims are made there. The gap one is **signed**: a
    // fit that reserved too much would leave more than [_gap] at the width it
    // called the last fitting one, and one that reserved too little would
    // leave less.
    //
    // At two scalers, because the dropdown's chrome does not follow the
    // scaler and the strings do. One is not enough to say that: a fit that
    // scaled the chrome with the text would pass the whole file at 1.
    for (final scale in const [1.0, 2.0]) {
      testWidgets('and the narrowest row at $scale still has room to read', (
        tester,
      ) async {
        const title = 'Update Channel';
        const value = 'Stable';
        Future<void> at(double box) => pump(
          tester,
          title: title,
          value: value,
          box: box,
          textScale: scale,
        );

        // The arrangement is monotone in the width - `Wrap` opens a new run
        // on one comparison - so a bisection lands on the boundary. Both ends
        // are asserted: without them a widget that always stacked, or never
        // did, would make this case about nothing.
        var stacks = 100.0;
        var fits = 2000.0;
        await at(fits);
        expect(stacked(tester, title), isFalse, reason: 'premise at $fits');
        await at(stacks);
        expect(stacked(tester, title), isTrue, reason: 'premise at $stacks');
        while (fits - stacks > 0.01) {
          final mid = (stacks + fits) / 2;
          await at(mid);
          // Inside the loop as well as outside it: an overflow at a width the
          // search walked through fails the case either way, but only this
          // says which width it was.
          expect(tester.takeException(), isNull, reason: 'at $mid');
          if (stacked(tester, title)) {
            stacks = mid;
          } else {
            fits = mid;
          }
        }

        await at(fits);
        expect(lines(tester, title), 1, reason: 'the title wraps at $fits');
        expect(lines(tester, value), 1, reason: 'the value wraps at $fits');
        final gap =
            chipOf(tester).left - tester.getRect(find.text(title)).right;
        expect(gap, closeTo(_gap, 0.02), reason: 'the gap at $fits');
      });
    }
  });

  group('once they do not', () {
    // The case the issue is: at a scaler of 2 the row has about a glyph left
    // for the title, and the old layout spent it a letter at a time. Its
    // premise is "they share a line", which pumps the same two strings in the
    // same box at a scaler of 1.
    testWidgets('the title goes above the dropdown', (tester) async {
      await pump(
        tester,
        title: 'Update Channel',
        value: 'Stable',
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(stacked(tester, 'Update Channel'), isTrue);
      expect(lines(tester, 'Update Channel'), lessThanOrEqualTo(2));
      expect(lines(tester, 'Stable'), 1);
      // With the run gap between them, and exactly it: each run here holds
      // one child, so its cross extent is that child's own height and
      // `runSpacing` is the whole distance.
      final title = tester.getRect(find.text('Update Channel'));
      expect(chipOf(tester).top - title.bottom, closeTo(6, 0.01));
    });

    // **A tripwire, not a measurement.** Both strings are whole at every
    // width in this file for a structural reason - neither `Text` sets
    // `maxLines` or an `overflow`, so nothing can be cut - and that is the
    // claim worth pinning, because it is what the two cheaper fixes the issue
    // weighed would have changed. An ellipsised value brings the #425 trap
    // here, where a cut string cannot be told from another cut string; a
    // clamped title leaves the user reading "Upd..." for the setting they are
    // changing.
    //
    // Asserted on the widgets rather than through `didExceedMaxLines`, which
    // the engine only ever sets when `maxLines` is non-null: against this
    // tree that flag is false by construction, so a case built on it is green
    // for any layout - the bug included.
    testWidgets('neither of the fixes the issue rejected was taken', (
      tester,
    ) async {
      await pump(
        tester,
        title: 'Update Channel',
        value: _longChannel,
        textScale: 2,
      );
      for (final text in const ['Update Channel', _longChannel]) {
        final widget = tester.widget<Text>(find.text(text));
        expect(widget.maxLines, isNull, reason: text);
        expect(widget.overflow, isNull, reason: text);
      }
    });

    // A longer channel title shipped upstream narrows the title on every
    // locale at once, at a scaler nobody raised. That is what a layout
    // decision gets right and what a width threshold would have missed.
    testWidgets('a long channel title alone is enough', (tester) async {
      await pump(
        tester,
        title: 'Update Channel',
        value: _longChannel,
        box: 360,
      );
      expect(tester.takeException(), isNull);
      expect(stacked(tester, 'Update Channel'), isTrue);
      // The premise: the same title in the same box at the same scaler still
      // shares a line when the value is short, so this is the value's length
      // and not the box's.
      await pump(tester, title: 'Update Channel', value: 'Dev', box: 360);
      expect(stacked(tester, 'Update Channel'), isFalse);
    });

    // The placeholder goes through the fit exactly as a channel title does,
    // and it is the string the card shows on every cold open. German's is the
    // longest of the eight.
    testWidgets('the placeholder is measured too', (tester) async {
      await pump(
        tester,
        title: 'Update-Kanal',
        value: null,
        placeholder: 'Nicht verfügbar',
        textScale: 3.1,
      );
      expect(tester.takeException(), isNull);
      expect(stacked(tester, 'Update-Kanal'), isTrue);
      expect(lines(tester, 'Update-Kanal'), lessThanOrEqualTo(2));
      expect(find.text('Nicht verfügbar'), findsOneWidget);
    });

    // The dropdown's value is `Flexible`, so a value too long for the card
    // wraps inside it instead of overflowing it. `Wrap` hands each child its
    // own maxWidth, which is what makes that legal.
    testWidgets('a value too long for the card wraps instead of overflowing', (
      tester,
    ) async {
      const long = 'Release Candidate Nightly Experimental';
      await pump(
        tester,
        title: 'Update Channel',
        value: long,
        box: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(lines(tester, long), greaterThan(1));
    });
  });

  // The `Expanded` this widget used to open with is `FlexFit.tight`, and a
  // tight flex child under an unbounded width constraint is the `RenderFlex`
  // assertion - so before the fix, putting one of these in a `Row` threw
  // outright. Nothing in the app does, which is why nothing caught it.
  //
  // It does not any more: `Wrap` wants no bound, and the `Flexible` left
  // inside the dropdown is loose under a `MainAxisSize.min` row, the
  // combination that assertion's own hint recommends. This is the case that
  // says so, because the claim is in the class doc and no other case can
  // reach it.
  testWidgets('an unbounded width is a layout rather than an assertion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        home: Scaffold(
          body: Row(
            children: [
              SettingsDropdown<String>(
                title: 'Update Channel',
                value: _longChannel,
                items: const ['one', 'two'],
                labelOf: (item) => item,
                descriptionOf: (item) => 'about $item',
                accent: const Color(0xFFCC241D),
                placeholder: 'Unavailable',
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(lines(tester, 'Update Channel'), 1);
    expect(lines(tester, _longChannel), 1);
  });

  // Every locale, because what fits is a property of the translations, and
  // four scalers because the chrome does not follow them.
  //
  // Both of the card's rows are here. The channel's label is the longer of
  // the two in half of the eight locales - en, fr, be and ru - level in hr
  // and uk, and the *shorter* one in de and es, which is why neither row
  // stands in for the other.
  group('every locale', () {
    // `firmwareUpdateChannel`, `firmwareBuildVariant` and the longer of
    // `firmwareUnavailable` and `firmwareLoading`, read out of
    // `translations/*.arb`. Copied rather than looked up so that a
    // translator's edit reports here as a fit to re-check rather than as a
    // silent change of subject.
    const strings = <String, List<String>>{
      'en': ['Update Channel', 'Build Variant', 'Unavailable'],
      'de': ['Update-Kanal', 'Build-Variante', 'Nicht verfügbar'],
      'es': [
        'Canal de actualización',
        'Variante de compilación',
        'No disponible',
      ],
      'fr': ['Canal de mise à jour', 'Variante de build', 'Indisponible'],
      'hr': ['Kanal ažuriranja', 'Varijanta builda', 'Učitavanje…'],
      'be': ['Канал абнаўленняў', 'Варыянт зборкі', 'Недаступна'],
      'ru': ['Канал обновлений', 'Вариант сборки', 'Недоступно'],
      'uk': ['Канал оновлень', 'Варіант збірки', 'Завантаження…'],
    };

    // Four scalers spanning what the platforms offer, not all of them: 1.0
    // and 1.3 are Android steps, 2.0 is the one #463's screenshot was taken
    // at, and 3.1 is the largest this repository tests anywhere - see
    // `nav_bar_label_fit_test.dart`. The steps left out are interior to the
    // range. Nothing below 1 is here because nothing in this widget has a
    // floor to behave differently under, which is the one place the nav bar's
    // file does go there.
    const scales = [1.0, 1.3, 2.0, 3.1];

    for (final entry in strings.entries) {
      testWidgets('in ${entry.key}', (tester) async {
        final titles = entry.value.take(2);
        // Both the longest channel title the directory ships and this
        // locale's own placeholder, which is the value on a cold open.
        final values = <String?>[_longChannel, null];
        for (final title in titles) {
          for (final value in values) {
            for (final box in const [600.0, 900.0]) {
              for (final scale in scales) {
                await pump(
                  tester,
                  title: title,
                  value: value,
                  placeholder: entry.value[2],
                  box: box,
                  textScale: scale,
                );
                final shown = value ?? entry.value[2];
                final where = '"$title" / "$shown" at $box, scale $scale';
                expect(tester.takeException(), isNull, reason: where);
                // The title, against its own break points rather than a line
                // count. Stacked it gets the card's full width, so every one
                // of these labels has room for its longest word and a
                // mid-word break would be the bug.
                //
                // The value is varied here but not asserted on: it is what
                // squeezes the title, which is the point of varying it, and
                // its own promise is different - it wraps inside a bordered
                // chip roughly 46 narrower than the card, so at 3.1 a single
                // 13-glyph word does not fit the line and breaks. That it
                // wraps rather than overflows is the case above; that it is
                // never cut is the tripwire case.
                expect(
                  lines(tester, title),
                  lessThanOrEqualTo(wrapSlots(title)),
                  reason: '"$title" broke mid-word, $where',
                );
              }
            }
          }
        }
      });
    }
  });
}

// ## Mutations
//
// Eleven against `SettingsDropdown`. Nine caught; the two that survive could
// not do otherwise, and that is the point of the rewrite.
//
// | mutation | killed by |
// |---|---|
// | **the pre-fix row**, faithfully - `Expanded` title, drawn gap, inflexible dropdown | 16 of the 18, all eight locales and the unbounded-width case among them |
// | the value is inflexible again | 14 of the 18, all eight locales |
// | the title and the dropdown swap places | 10 of the 18 |
// | the gap is dropped (`spacing: 0`) | both bisections, and nothing else |
// | the gap is doubled | both bisections, and nothing else |
// | `WrapAlignment.start` for `spaceBetween` | "stays against the trailing edge" **alone** |
// | the run gap is dropped | "the title goes above the dropdown" **alone** |
// | the title clamped to one line with an ellipsis | "neither of the fixes the issue rejected" **alone** |
// | an absent value draws `''` rather than the placeholder | "the placeholder is measured too" **alone** |
// | the dropdown's 10 of padding is dropped | **survives** |
// | the chevron drawn at size 0 | **survives** |
//
// The last two change what the dropdown looks like and nothing about which
// arrangement it gets, because the fit is the layout's own: a narrower
// dropdown is simply a narrower dropdown, and the bisection finds the
// boundary wherever it has moved to. Under the measured fit this file
// replaced, both would have been arithmetic errors and both would have been
// caught here - which is the trade this made deliberately. A padding or a
// chevron is a visual regression, and the file for that is one that looks at
// the card, not at the fit.
//
// **The pre-fix row is run as it really was** - `Expanded`, a drawn gap and
// an inflexible dropdown - rather than as a `Row` of two plain children,
// which is a different bug with a different shape. An earlier draft of this
// note claimed four locales could not catch it; a probe that reproduced the
// arrangement properly showed all eight do, because at a scaler of 2 the
// dropdown alone wants more than the box and the title's slot goes to zero in
// every language.
