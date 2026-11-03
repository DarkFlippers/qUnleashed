import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/widgets/page_card.dart';
import 'package:qunleashed/theme/theme.dart';

/// Built once. `ThemeData()` is not free and nothing here varies it.
final ThemeData _theme = buildAppTheme(
  Brightness.dark,
  const Color(0xFFCC241D),
);

/// That `FlipperPageCard`'s header keeps its title and its trailing widget on
/// the card at every text size.
///
/// The header was an `Expanded` title beside an inflexible `trailing`, which
/// is #463's shape one level up from the row that issue is named for - and in
/// the same screenshot. Every `trailing` the five call sites pass is text in a
/// bordered chip, so it grows with the scaler while the card does not: the
/// title's slot shrinks to nothing and the row overflows to the right.
/// Measured on the firmware card before the fix, 102 pixels at a 360 dp
/// window at a scaler of 3.1, and reached at 2.0 on a 320.
///
/// The five callers are `devices/page.dart`, `cards/auto_connect_hint.dart`,
/// `cards/connect_card.dart`, `firmware_card.dart` and `full_info_sheet.dart`.
/// This pins the widget rather than any of them, which is the point of fixing
/// it here: one `Wrap` answers all five.
///
/// Widths here are this font's, not a phone's - every glyph is a square of the
/// font size, about twice what Roboto gives. `nav_bar_label_fit_test.dart` has
/// the measurement.
void main() {
  /// Pumps a card with [title] and a chip of [trailing] in a [box]-wide slot.
  ///
  /// From an empty tree each time: a `RenderFlex` reports an overflow once per
  /// render object and `pumpWidget` reuses elements, so a second overflowing
  /// width in the same case would throw nothing and read as a pass.
  /// `device_header_fit_test.dart` is where that is written down.
  Future<void> pump(
    WidgetTester tester, {
    required String title,
    String? trailing,
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
              child: FlipperPageCard(
                title: title,
                trailing: trailing == null
                    ? null
                    : DecoratedBox(
                        key: const ValueKey('chip'),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF888888)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(trailing),
                        ),
                      ),
                child: const SizedBox(height: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// How many lines [text] was laid out over: the height it took over the
  /// height one line of the same span would take. `RenderParagraph` keeps its
  /// `TextPainter` private and answers no line count, and its intrinsics are
  /// measured on a painter of their own, so asking does not disturb the one
  /// that painted.
  int lines(WidgetTester tester, String text) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    return (paragraph.size.height /
            paragraph.getMinIntrinsicHeight(double.infinity))
        .round();
  }

  // The real string from the firmware card, which is the call site the
  // overflow was measured on, and its real trailing label.
  const title = 'Firmware';
  const trailing = "What's new";

  testWidgets('a title and a trailing chip that fit share a line', (
    tester,
  ) async {
    await pump(tester, title: title, trailing: trailing);
    expect(tester.takeException(), isNull);
    final titleRect = tester.getRect(find.text(title));
    expect(
      titleRect.bottom,
      greaterThan(tester.getRect(find.text(trailing)).top),
    );
    expect(lines(tester, title), 1);
  });

  testWidgets('and the chip is on the trailing edge', (tester) async {
    await pump(tester, title: title, trailing: trailing);
    // The card's own 14 of margin and the header's 12 of padding are all
    // that is beyond it. `getRect` on the card is the `Container`, so its
    // rect includes that margin - and the chip is read by its key rather
    // than through its text, whose own 6 of padding would otherwise have to
    // be written into the number.
    final card = tester.getRect(find.byType(FlipperPageCard));
    expect(
      tester.getRect(find.byKey(const ValueKey('chip'))).right,
      closeTo(card.right - 14 - 12, 0.01),
    );
  });

  // The case the fix is for. Before it, this is a right overflow rather than a
  // second run.
  testWidgets('a chip that no longer fits drops below the title', (
    tester,
  ) async {
    await pump(tester, title: title, trailing: trailing, textScale: 3.1);
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.text(title)).bottom,
      lessThanOrEqualTo(tester.getRect(find.text(trailing)).top),
    );
  });

  // A header with no trailing widget is the other four call sites' usual
  // shape, and it must still take the whole width rather than shrink to its
  // glyphs - `spaceBetween` with one child on a run puts it on the leading
  // edge, which is what the `Expanded` did.
  testWidgets('a title with no chip sits on the leading edge', (tester) async {
    await pump(tester, title: title);
    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byType(FlipperPageCard));
    expect(
      tester.getRect(find.text(title)).left,
      closeTo(card.left + 14 + 12, 0.01),
    );
  });

  // Every width and scaler the card can be drawn at, with a title long enough
  // to be the one that runs out of room.
  //
  // Nothing may overflow at any of them. The title may also take one line per
  // place it can break - two for this one - but only where its longest word
  // fits the line at all: at 320 and a scaler of 3.1, "Firmware" alone is
  // about 397 wide in this font against 268 of card interior, so it breaks
  // mid-word whatever the layout does. That is the limit of giving the title
  // its own line rather than a defect of it, and it is the reason the bound is
  // asserted at the two widths where a word fits.
  group('nothing overflows', () {
    for (final box in const [320.0, 600.0, 900.0]) {
      for (final scale in const [1.0, 1.3, 2.0, 3.1]) {
        testWidgets('at $box, scale $scale', (tester) async {
          await pump(
            tester,
            title: 'Firmware update',
            trailing: trailing,
            box: box,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          if (box > 320) {
            expect(lines(tester, 'Firmware update'), lessThanOrEqualTo(2));
          }
        });
      }
    }
  });
}
