import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/widgets/firmware_card.dart';
import 'package:qunleashed/theme/theme.dart';

/// Built once: `buildAppTheme` runs an HSL loop per call, and every case here
/// would pay it again for the same answer.
final ThemeData _theme = buildAppTheme(
  Brightness.dark,
  const Color(0xFFCC241D),
);

/// A channel title as long as the firmware directory really ships.
///
/// It is **server data**, which is the whole reason the widget measures
/// instead of switching on a width: nothing in `translations/` or in this
/// repository decides how long it is.
const String _longChannel = 'Release Candidate';

/// That the firmware card's two setting rows keep both of their strings whole
/// at every text size.
///
/// The title was an `Expanded` beside an inflexible dropdown, so the dropdown
/// took its full intrinsic width - its own value plus 44 of padding, gap and
/// chevron, none of which follows the scaler - and the title got what was
/// left. At a scaler of 2 that was about one glyph, and `Text` with no
/// `maxLines` wrapped per character: "Update Channel" drawn as a vertical
/// column of letters, tall enough to push the build-variant row and the
/// update button off the screen. #463.
///
/// ## No width here is a phone's
///
/// `flutter_test` renders every glyph as a square of the font size, about
/// twice what Roboto gives at the same size. So these boxes are chosen
/// through that ratio rather than as phone widths: 600 is what this font
/// spends where Roboto spends a 320 dp phone's room, and 900 where it spends
/// a large one's. The same note in `nav_bar_label_fit_test.dart` has the
/// measurement it comes from.
///
/// What the file checks is the contract, which holds in any font:
///
///  * nothing overflows at any scaler;
///  * the title and the value share a line while both fit it whole;
///  * below that the title moves **above** the dropdown rather than being
///    squeezed, and is still a word rather than a column of letters.
void main() {
  /// Pumps one dropdown with [title] and [value] in a [box]-wide slot.
  ///
  /// `SettingsDropdown` is `@visibleForTesting` and takes both strings as
  /// plain `String`s, so no localization delegate is wired up here: the
  /// per-locale group below passes the ARB values in directly, which is also
  /// what the card does.
  Future<void> pump(
    WidgetTester tester, {
    required String title,
    required String value,
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
                placeholder: 'Unavailable',
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
  /// scaler and strut included - rather than a number modelled here.
  int lines(WidgetTester tester, String text) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    return (paragraph.size.height /
            paragraph.getMinIntrinsicHeight(double.infinity))
        .round();
  }

  /// Whether the title sits above the dropdown rather than beside it.
  ///
  /// Read off the two painted rects rather than off the widget tree: which
  /// arrangement was built is the thing under test, and a `Column` or a `Row`
  /// in the finder would pass on the ones the card wraps this in.
  bool stacked(WidgetTester tester, String title, String value) =>
      tester.getRect(find.text(title)).bottom <=
      tester.getRect(find.text(value)).top;

  group('while both strings fit', () {
    testWidgets('they share a line', (tester) async {
      await pump(tester, title: 'Update Channel', value: 'Stable');
      expect(tester.takeException(), isNull);
      expect(stacked(tester, 'Update Channel', 'Stable'), isFalse);
      expect(lines(tester, 'Update Channel'), 1);
      expect(lines(tester, 'Stable'), 1);
    });

    // The title keeps the gap as well as the glyphs: "fits" is "fits with
    // room to read", not "the two strings touch". Dropping the gap from the
    // fit leaves this case green and only moves the boundary, which is why
    // the number is also drawn.
    testWidgets('the gap between them is drawn', (tester) async {
      await pump(tester, title: 'Update Channel', value: 'Stable');
      final title = tester.getRect(find.text('Update Channel'));
      final chip = tester.getRect(find.text('Stable'));
      // The chip's own left padding is on top of the gap, so this is a lower
      // bound rather than the gap itself.
      expect(chip.left - title.right, greaterThanOrEqualTo(8));
    });
  });

  group('once they do not', () {
    // The case the issue is: at a scaler of 2 the row has about a glyph left
    // for the title, and the old layout spent it a letter at a time.
    testWidgets('the title goes above the dropdown', (tester) async {
      await pump(
        tester,
        title: 'Update Channel',
        value: 'Stable',
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(stacked(tester, 'Update Channel', 'Stable'), isTrue);
      expect(lines(tester, 'Update Channel'), lessThanOrEqualTo(2));
      expect(lines(tester, 'Stable'), 1);
    });

    // Both strings whole, which is the reason this fix and not the two
    // cheaper ones: an ellipsised value brings back #425 - two channels
    // whose titles share a prefix reading as the same channel - and a
    // clamped title leaves the user reading "Upd..." for the setting they
    // are changing.
    testWidgets('neither string is cut', (tester) async {
      await pump(
        tester,
        title: 'Update Channel',
        value: _longChannel,
        textScale: 2,
      );
      for (final text in const ['Update Channel', _longChannel]) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(paragraph.didExceedMaxLines, isFalse, reason: text);
      }
    });

    // A longer channel title shipped upstream narrows the title on every
    // locale at once, at a scaler nobody raised. That is what the
    // measurement is for and what a width threshold would have missed.
    testWidgets('a long channel title alone is enough', (tester) async {
      await pump(
        tester,
        title: 'Update Channel',
        value: _longChannel,
        box: 360,
      );
      expect(tester.takeException(), isNull);
      expect(stacked(tester, 'Update Channel', _longChannel), isTrue);
      // The premise: the same title at the same scaler still shares a line
      // when the value is short, so this is the value's length and not the
      // box's.
      await pump(tester, title: 'Update Channel', value: 'Dev', box: 360);
      expect(stacked(tester, 'Update Channel', 'Dev'), isFalse);
    });

    // Stacked, the dropdown has a bounded width, so a value too long for the
    // card wraps inside it instead of overflowing. In the row arrangement the
    // same `Flexible` would be a `RenderFlex` assertion - an inflexible slot
    // hands its child an unbounded constraint - which is why the widget takes
    // a flag rather than always flexing.
    testWidgets('a value too long for the card wraps instead of overflowing', (
      tester,
    ) async {
      await pump(
        tester,
        title: 'Update Channel',
        value: 'Release Candidate Nightly Experimental',
        box: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(
        lines(tester, 'Release Candidate Nightly Experimental'),
        greaterThan(1),
      );
    });
  });

  // Every locale and every scaler Android offers, because what fits is a
  // property of the translations. Both of the card's rows are here: the
  // channel's label is the longer of the two in seven of the eight locales,
  // but both wrapped and both are drawn by this widget.
  group('every locale', () {
    // `firmwareUpdateChannel` and `firmwareBuildVariant`, read out of
    // `translations/*.arb`. Copied rather than looked up so that a
    // translator's edit reports here as a fit to re-check rather than as a
    // silent change of subject.
    const labels = <String, List<String>>{
      'en': ['Update Channel', 'Build Variant'],
      'de': ['Update-Kanal', 'Build-Variante'],
      'es': ['Canal de actualización', 'Variante de compilación'],
      'fr': ['Canal de mise à jour', 'Variante de build'],
      'hr': ['Kanal ažuriranja', 'Varijanta builda'],
      'be': ['Канал абнаўленняў', 'Варыянт зборкі'],
      'ru': ['Канал обновлений', 'Вариант сборки'],
      'uk': ['Канал оновлень', 'Варіант збірки'],
    };

    for (final entry in labels.entries) {
      testWidgets('in ${entry.key}', (tester) async {
        for (final title in entry.value) {
          for (final box in const [600.0, 900.0]) {
            for (final scale in const [1.0, 1.3, 2.0, 3.1]) {
              await pump(
                tester,
                title: title,
                value: _longChannel,
                box: box,
                textScale: scale,
              );
              final where = '"$title" at $box, scale $scale';
              expect(tester.takeException(), isNull, reason: where);
              expect(lines(tester, title), lessThanOrEqualTo(2), reason: where);
              expect(
                tester
                    .renderObject<RenderParagraph>(find.text(title))
                    .didExceedMaxLines,
                isFalse,
                reason: where,
              );
            }
          }
        }
      });
    }
  });
}
