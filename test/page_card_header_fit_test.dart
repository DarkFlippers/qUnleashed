// That `FlipperPageCard`'s header fits, and that its two trailing slots do
// different things with the room they are given.
//
// #474. The header was `Row(children: [Expanded(Text(title)), ?trailing])`,
// and an inflexible trailing takes its whole intrinsic width - so where the
// trailing is text in a chip, which follows the text scaler while the card's
// width does not, the title's slot shrank and then the row overflowed: 102
// pixels off the right at a 360 dp window and a scaler of 3.1, reached at 2.0
// on a 320.
//
// **A fix was written for this once and reverted**, which is why this file
// covers both shapes rather than only the one that overflowed. The first
// attempt made the header a `Wrap` unconditionally, and that regressed
// `cards/auto_connect_hint.dart` at the *default* text size: a soft-wrapping
// `Text` reports the whole offered `maxWidth` as its width once it wraps, and
// `Wrap` offers each child its full `maxWidth`, so a title that took two lines
// claimed the entire run and the close button dropped to a run of its own -
// at the leading edge, because `spaceBetween` with one child on a run puts it
// there. An "X" at the bottom-left of a card is not a dismiss affordance any
// more, and `auto_connect_hint_test.dart` could not see it: what that file
// pins is that the button dismisses the card, which it still did.
//
// So the two slots are the fix, and the two groups below are their contracts:
//
//  * `trailing` keeps the corner, and the title takes what is left;
//  * `trailingValue` shares the line while both fit and drops below the title
//    when they do not.
//
// ## The stand-ins
//
// The widgets passed here are built in this file rather than imported.
// `_PinnedStandIn` is the `IconButton` shape `auto_connect_hint.dart` passes -
// a 40x40 tap target that does not follow the text scaler, which is why that
// card never overflowed. `_ValueStandIn` is `_WhatsNewButton`'s shape, which
// is private to `firmware_card.dart`: a bordered chip holding an icon and a
// `Flexible` label. The real one is exercised by `firmware_card_fit_test.dart`
// at the same widths and scalers, and that is also where the `Flexible` half
// is pinned - this file is the header's contract, not the chip's.
//
// ## Widths
//
// `flutter_test` renders every glyph as a square of the font size, about twice
// what Roboto gives, so no width here is a phone's. The ratio is measured in
// `nav_bar_label_fit_test.dart`; `firmware_dropdown_fit_test.dart` cites it and
// carries the reasoning. The four widths below are a subset of that file's six
// - it also brackets with 100 and 2000 - chosen so the two files' middle cases
// line up.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/widgets/page_card.dart';
import 'package:qunleashed/theme/theme.dart';

import 'view_size.dart';

/// Built once. `ThemeData()` is not free and nothing here varies it.
final ThemeData _theme = buildAppTheme(
  Brightness.dark,
  const Color(0xFFCC241D),
);

/// The header's own padding, which is what "in the corner" is measured
/// against.
///
/// `EdgeInsets.fromLTRB(12, 12, 12, 6)` in `page_card.dart`; this is the 12 a
/// side.
const double _pad = 12;

/// `FlipperPageCard`'s horizontal margin, so a case can work out where the
/// card's edges are from the window's.
const double _margin = 14;

const Key _trailingKey = Key('trailing');

/// A title long enough to want the whole header at every width here.
///
/// The shape `fmAutoConnectFailedTitle` has - a sentence with the user's own
/// device name interpolated into it - which is the one title in the five call
/// sites that no translation bounds the length of.
const String _title = 'Could not connect to MyFlipper42 automatically';

/// The window widths every sweep runs at, narrowest first.
const List<double> _widths = [320.0, 360.0, 600.0, 900.0];

/// The scalers every sweep runs at.
///
/// 1.3 is one step up from the default in Android's own settings, 2.0 and 3.1
/// are the two above it that `device_header_fit_test.dart` uses, and 1.0 is
/// here because the reverted attempt's regression was at the default size -
/// a sweep that starts at 1.3 would have missed it.
const List<double> _scales = [1.0, 1.3, 2.0, 3.1];

void main() {
  /// Pumps one card and returns what it threw, or null.
  ///
  /// **From an empty tree every time.** A `RenderFlex` reports its overflow
  /// once per render object - `_overflowReportNeeded` goes false after the
  /// first report - and `pumpWidget` updates existing elements rather than
  /// rebuilding them, so a second overflowing width in one case would throw
  /// nothing and read as a pass. `device_header_fit_test.dart` found that by
  /// measuring; this file inherits the fix rather than the bug.
  Future<Object?> render(
    WidgetTester tester, {
    required double width,
    double scale = 1,
    String title = _title,
    Widget? trailing,
    Widget? trailingValue,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    sizeView(tester, Size(width, 800));
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        // In a scroll view, which is how every page holds these - the device
        // page is a `Column` inside one. Not decoration: the window is 800
        // tall and this title at a scaler of 3.1 is taller than that, so
        // without it the *test* overflowed vertically by 161 pixels and the
        // case read as a header fault. The card still gets the window's full
        // width, which is what every assertion here is about.
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                FlipperPageCard(
                  title: title,
                  trailing: trailing,
                  trailingValue: trailingValue,
                  child: const SizedBox(height: 20, width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.takeException();
  }

  Rect rectOf(WidgetTester tester, Finder finder) {
    final topLeft = tester.getTopLeft(finder);
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      tester.getSize(finder).width,
      tester.getSize(finder).height,
    );
  }

  Rect titleRect(WidgetTester tester, [String title = _title]) =>
      rectOf(tester, find.text(title));
  Rect trailingRect(WidgetTester tester) =>
      rectOf(tester, find.byKey(_trailingKey));

  group('the pinned trailing keeps the corner', () {
    for (final scale in _scales) {
      for (final width in _widths) {
        testWidgets('at $width and a scaler of $scale', (tester) async {
          expect(
            await render(
              tester,
              width: width,
              scale: scale,
              trailing: const _PinnedStandIn(),
            ),
            isNull,
          );

          final title = titleRect(tester);
          final button = trailingRect(tester);

          // **Against the trailing edge**, which is the half the reverted
          // attempt lost. The card is the window less its two margins, so
          // this is the header's padding and nothing else.
          expect(button.right, closeTo(width - _margin - _pad, 0.5));
          // **On the title's line**, not under it: the two overlap
          // vertically. A stacked button would clear the title's bottom,
          // which is what the reverted `Wrap` did at 320, 360 and 600 at this
          // scale - #474 records the last two; 320 is this sweep's own
          // narrowest and the title wraps harder there.
          expect(button.top, lessThan(title.bottom));
          // And the title is to its left rather than through it - the
          // overlap a `Stack` would have allowed and a `Row` cannot, pinned
          // because the first version of this header painted the two on top
          // of each other at every width (#417, one card over).
          expect(title.right, lessThanOrEqualTo(button.left + 0.5));
        });
      }
    }
  });

  group('a value shares the line or drops below it', () {
    for (final scale in _scales) {
      for (final width in _widths) {
        testWidgets('fits at $width and a scaler of $scale', (tester) async {
          expect(
            await render(
              tester,
              width: width,
              scale: scale,
              trailingValue: const _ValueStandIn(),
            ),
            isNull,
          );

          final card = rectOf(tester, find.byType(FlipperPageCard));
          final value = trailingRect(tester);

          // Inside the card whichever run it landed on, which is the claim
          // `takeException` cannot make on its own: the card clips with
          // `Clip.antiAlias`, so a chip hanging off the right would be cut at
          // the rounded corner rather than drawn over a neighbour, and a
          // release build reports neither.
          expect(value.left, greaterThanOrEqualTo(card.left + _pad - 0.5));
          expect(value.right, lessThanOrEqualTo(card.right - _pad + 0.5));
        });
      }
    }

    // A short title, because the long one does not fit beside the chip at any
    // width this file sweeps: 46 glyphs at 16 is about 736 of this font's
    // pixels, the chip 157.5 measured, and a 900 window leaves the header 848.
    // So the sharing case is about a title with room beside it - which is what
    // three of the five call sites pass: `deviceFirmwareTab`,
    // `firmwareUpdateTitle` and `deviceRawData`. The fourth title is the long
    // one this file uses, and the fifth card has no title at all.
    const shortTitle = 'Firmware';

    testWidgets('shares it when both fit, held to the trailing edge', (
      tester,
    ) async {
      expect(
        await render(
          tester,
          width: 900,
          title: shortTitle,
          trailingValue: const _ValueStandIn(),
        ),
        isNull,
      );

      final title = titleRect(tester, shortTitle);
      final value = trailingRect(tester);

      expect(value.top, lessThan(title.bottom), reason: 'one line');
      expect(title.right, lessThanOrEqualTo(value.left + 0.5));
      expect(value.right, closeTo(900 - _margin - _pad, 0.5));
    });

    testWidgets('drops below the title when they do not', (tester) async {
      expect(
        await render(
          tester,
          width: 320,
          scale: 3.1,
          trailingValue: const _ValueStandIn(),
        ),
        isNull,
      );

      final title = titleRect(tester);
      final value = trailingRect(tester);

      // A run of its own, and at the leading edge - `spaceBetween` has
      // nothing to space with one child on a run. That is the placement
      // `trailing` must not have and a value may: `page_card.dart`'s two docs
      // are where the difference is argued.
      expect(value.top, greaterThanOrEqualTo(title.bottom - 0.5));
      expect(value.left, closeTo(_margin + _pad, 0.5));
    });
  });

  test('a header takes one trailing slot, not both', () {
    expect(
      () => FlipperPageCard(
        title: _title,
        trailing: const _PinnedStandIn(),
        trailingValue: const _ValueStandIn(),
        child: const SizedBox.shrink(),
      ),
      throwsAssertionError,
    );
  });
}

/// The shape `cards/auto_connect_hint.dart` passes as `trailing`.
///
/// 40x40 at every scaler, from `_IconButtonDefaultsM3.minimumSize` - a
/// literal in Material, not `kMinInteractiveDimension`, which is 48 and is the
/// padded tap target around that box. Either way the width does not move with
/// the text scaler, which is the property the pinned slot's contract depends
/// on.
class _PinnedStandIn extends StatelessWidget {
  const _PinnedStandIn();

  @override
  Widget build(BuildContext context) => IconButton(
    key: _trailingKey,
    icon: const Icon(Icons.close, size: 20),
    tooltip: 'Close',
    onPressed: () {},
  );
}

/// The shape `firmware_card.dart`'s `_WhatsNewButton` passes as
/// `trailingValue`.
///
/// Text in a border, so its width follows the text scaler - and the label is
/// `Flexible`, which is what lets the chip wrap itself inside the width the
/// header's `Wrap` hands it rather than demanding its single-line width. The
/// real chip is pinned in `firmware_card_fit_test.dart`; dropping the
/// `Flexible` there is one of that file's mutations.
class _ValueStandIn extends StatelessWidget {
  const _ValueStandIn();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      key: _trailingKey,
      decoration: BoxDecoration(
        border: Border.all(color: colors.divider),
        borderRadius: BorderRadius.circular(30),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 13, color: colors.textSecondary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              "What's new",
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
