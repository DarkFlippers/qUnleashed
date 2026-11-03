import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/widgets/firmware_card.dart';
import 'package:qunleashed/services/localization/gen/l10n_generated.dart';
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
/// Server data, read out of the firmware feed - the class doc is where that
/// matters. Nothing pins the longest title the feed can ship, so this is a
/// length that has been seen rather than a bound.
const String _longChannel = 'Stable Release Channel';

/// That the firmware card's two setting rows keep both of their strings whole
/// at every text size.
///
/// `SettingsDropdown`'s own doc has the mechanism and why the fix is a `Wrap`
/// rather than a measurement; in one line, the title was an `Expanded` beside
/// an inflexible dropdown, so at a scaler of 2 it had about one glyph to work
/// with and `Text` spent it a letter at a time. #463.
///
/// ## No width here is a phone's
///
/// `flutter_test` renders every glyph as a square of the font size, about
/// twice what Roboto gives at the same size - `nav_bar_label_fit_test.dart`
/// has the measurement that ratio comes from. So the widths here are chosen
/// through it rather than as phone widths, and there are six of them, none a
/// device size:
///
///  * **600** is roughly what this font spends where Roboto spends the ~292 dp
///    of card interior on a 320 dp phone, and **900** is deliberately wider
///    than any phone's card. Neither mapping is derived anywhere; they are two
///    widths far enough apart that the arrangement differs between them.
///  * **360** and **320** are two narrow cases, chosen to make a long value
///    and a long value at a scaler the thing that runs out of room. In this
///    font they are *narrower* than the phones whose numbers they look like.
///  * **100** and **2000** are the bisection's brackets, one arrangement each,
///    and it asserts that before it searches.
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
    // From an empty tree each time, and the bisection depends on it: a
    // `RenderFlex` reports an overflow once per render object, and
    // `pumpWidget` reuses the elements - so a second overflowing width in the
    // same case would throw nothing and read as a pass.
    // `device_header_fit_test.dart` is where that is written down.
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
  // n separators yield n + 1 parts, which is the plus one. The trailing
  // hyphen in the class is literal and needs no escape.
  int wrapSlots(String text) => text.split(RegExp(r'[ -]')).length;

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
    // `maxLines` or an `overflow`, so nothing can be cut. That is worth
    // pinning because it is exactly what the two cheaper fixes the issue
    // weighed would have changed; the class doc says why each was refused.
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
    // wraps inside it instead of overflowing it.
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

  // **The row fills the width it is offered rather than hugging its content.**
  //
  // A `Row` with no `mainAxisSize` takes the width it is given; a `Wrap` takes
  // the width of its children. The card puts these in a `Column`, which
  // centres anything narrower than itself - so the rewrite would have left the
  // two settings rows hugging their text and sitting in the middle of the
  // card, which the fit cases cannot see because they pump in a tight box.
  // `width: double.infinity` is what keeps it, and this is the case that says
  // so.
  testWidgets('the row fills a loose width instead of hugging its text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        home: Scaffold(
          body: SizedBox(
            width: 600,
            // Loose, and centring, which is what `Column` does by default and
            // what `_FirmwareControls` hands these rows.
            child: Column(
              children: [
                SettingsDropdown<String>(
                  title: 'Update Channel',
                  value: 'Stable',
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
      ),
    );
    expect(tester.takeException(), isNull);
    // The title on the leading edge and the dropdown on the trailing one, 600
    // apart less the widget's own 2 of horizontal padding - not 'Update
    // Channel' and 'Stable' side by side somewhere in the middle.
    final row = tester.getRect(find.byType(SettingsDropdown<String>));
    expect(row.width, closeTo(600, 0.01));
    expect(chipOf(tester).right, closeTo(row.right - 2, 0.01));
  });

  // Every locale, because what fits is a property of the translations, and
  // four scalers because the dropdown's padding and chevron do not follow
  // them while the strings do.
  group('every locale', () {
    // Four scalers spanning what the platforms offer, not all of them: 1.0
    // and 1.3 are Android steps, 2.0 is the one #463's screenshot was taken
    // at, and 3.1 is the largest this repository tests anywhere - see
    // `nav_bar_label_fit_test.dart`. The steps left out are interior to the
    // range. Nothing below 1 is here because nothing in this widget has a
    // floor to behave differently under, which is the one place the nav bar's
    // file does go there.
    const scales = [1.0, 1.3, 2.0, 3.1];

    // Through `lookupL10n`, as `nav_bar_label_fit_test.dart` and
    // `device_header_fit_test.dart` do, rather than copied into a table here.
    // A copy looks safer and is the opposite: nothing would compare it with
    // `translations/`, so a translation that grew past what fits would leave
    // this file measuring the retired string and passing. Read from the ARB,
    // that edit is exactly what fails - and a ninth locale arrives covered
    // instead of silently uncovered.
    for (final locale in L10n.supportedLocales) {
      testWidgets('in ${locale.languageCode}', (tester) async {
        final strings = lookupL10n(locale);
        // Both of the card's rows. The channel's label is the longer of the
        // two in half of the eight locales, level in hr and uk, and the
        // shorter one in de and es, so neither stands in for the other.
        final titles = [
          strings.firmwareUpdateChannel,
          strings.firmwareBuildVariant,
        ];
        // The longest channel title the directory ships, and this locale's
        // own placeholder, which is the value on a cold open. Picked by
        // length rather than by hand: in this font every glyph is a square of
        // the font size, so the longer string is the wider one.
        final placeholder = [
          strings.firmwareUnavailable,
          strings.firmwareLoading,
        ].reduce((a, b) => a.length >= b.length ? a : b);
        final values = <String?>[_longChannel, null];
        for (final title in titles) {
          for (final value in values) {
            for (final box in const [600.0, 900.0]) {
              for (final scale in scales) {
                await pump(
                  tester,
                  title: title,
                  value: value,
                  placeholder: placeholder,
                  box: box,
                  textScale: scale,
                );
                final shown = value ?? placeholder;
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
// Twelve against `SettingsDropdown`. Ten caught; the two that survive could
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
// | the `SizedBox(width: double.infinity)` dropped | "fills a loose width" **alone** |
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
