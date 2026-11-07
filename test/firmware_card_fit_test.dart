// That the whole firmware card fits, at every width and text size.
//
// #471. The carousel was `SizedBox(height: 110)` around a `PageView`, and 110
// was never measured: a slide's 22pt name wraps as soon as its slot gets
// narrow, so a slide's height is set by how many lines that name takes - which
// depends on which of the two firmwares the slide is for, and on the text
// scaler. Pumped at a 360 dp window it overflowed by 10 pixels at a scaler of
// 1.3, 163 at 2.0 and 555 at 3.1, and by 73 at 1.3 on a 320. **1.3 is one step
// up from the default in Android's own settings.**
//
// Those four are the card in its `firmwareChecking` state. The right-edge
// figures the header and the chip carry - 102 at 360/3.1 and 9.5 at 320/2.0 -
// are the settled state, where the "What's new" chip exists at all. Both sets
// are real and they are not measurements of the same tree.
//
// ## Why no screenshot showed it
//
// Neither reason is the other, and both are why this file exists at all:
//
//  * the overflow report lives in an `assert` in `RenderFlex.paint`, so a
//    release build says nothing whether or not anything clips;
//  * the excess was clipped anyway - by the `PageView`'s viewport and by the
//    card's `Clip.antiAlias` - so it was cut off at a rounded corner rather
//    than drawn over the card below. **Not by the slide's own `Column`**:
//    `Flex.clipBehavior` defaults to `Clip.none`, so an overflowing `Column`
//    paints straight past its bounds. `main`'s version of this comment said
//    `Clip.hardEdge` and was wrong.
//
// `device_header_fit_test.dart` records the same trap one card over, and
// #463's "same card, not confirmed" was this bug read off a screenshot.
//
// ## What is pinned here that the per-widget files cannot pin
//
// `page_card_header_fit_test.dart` has the header's two trailing slots and
// `firmware_dropdown_fit_test.dart` the two setting rows, both against
// stand-ins. This file mounts the real `FirmwareCard`, so it is the only place
// the real `_WhatsNewButton` and the real carousel are measured - both are
// private - and the only place their heights are added together.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/pages/devices/widgets/firmware_card.dart';

import 'firmware_fixture.dart';
import 'view_size.dart';

/// The two firmwares the app ships, by the name a slide renders.
///
/// Their lengths are the premise of 'one height whichever slide is showing':
/// 17 glyphs against 9 is a different number of wrapped lines in a slide's
/// slot, so the two slides really do want different heights.
const String _shortName = 'Unleashed';
const String _longName = 'Official firmware';

/// `_FirmwareSlide`'s own padding, which [main]'s `longSlide` uses to tell one
/// slide's widgets from another's.
///
/// `EdgeInsets.fromLTRB(14, 8, 14, 6)` in `firmware_card.dart`. A second copy,
/// like [_imageSide] below and for the same reason: a case that has to pick a
/// slide out of a `Stack` of them needs something to pick it by.
const EdgeInsets _slidePadding = EdgeInsets.fromLTRB(14, 8, 14, 6);

/// The side `_FirmwareSlide` draws the firmware image at.
///
/// `_imageSide` in `firmware_card.dart`, which this is the other copy of on
/// purpose: a case asserting the image kept its size has to say the size.
const double _imageSide = 62;

/// The window widths the sweep runs at, narrowest first.
///
/// `flutter_test` renders every glyph as a square of the font size, about
/// twice what Roboto gives, so these are not phone widths. The ratio is
/// measured in `nav_bar_label_fit_test.dart`, which
/// `firmware_dropdown_fit_test.dart` cites for it. 320 and 360 are the two
/// narrow cases #471 measured the overflow at, and 412 is its third.
///
/// The conversion is **not a scalar over the window**, which is the mistake
/// easiest to make here: the 62 image, the two 28 nav buttons and every
/// padding are the same number of pixels in either font, so only the name's
/// own width doubles. Where a real width matters, `firmware_card.dart`'s
/// `_FirmwareSlide` carries it in device pixels instead.
const List<double> _widths = [320.0, 360.0, 412.0];

/// The scalers it runs at. 1.3 is the one the bug started at.
const List<double> _scales = [1.0, 1.3, 2.0, 3.1];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DeviceController device;

  setUp(() {
    resetFirmwareState();
    (device, _) = mountedDevice();
  });

  /// Pumps the card at [width] and [scale] and returns what it threw.
  ///
  /// **From an empty tree every time**, because a `RenderFlex` reports its
  /// overflow once per render object and `pumpWidget` reuses elements - so a
  /// second overflowing size in one case would throw nothing and read as a
  /// pass. `device_header_fit_test.dart` found that by measuring.
  ///
  /// The scaler goes on inside `home` rather than through `MaterialApp.builder`
  /// because `wrapWithDevice` already uses that slot, for `DeviceScope`.
  ///
  /// In a `SingleChildScrollView`, which is what the device page gives this
  /// card, and which is load-bearing here rather than faithful decoration: at
  /// a scaler of 3.1 the card is taller than any test window, so a bounded
  /// parent would make the *test* overflow and read as a card fault.
  Future<Object?> render(
    WidgetTester tester, {
    required double width,
    double scale = 1,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    sizeView(tester, Size(width, 800));
    await tester.pumpWidget(
      wrapWithDevice(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: SingleChildScrollView(
              child: FirmwareCard(deviceVersion: '1.0.0', deviceInfo: const {}),
            ),
          ),
        ),
        device,
      ),
    );
    await tester.pumpAndSettle();
    return tester.takeException();
  }

  /// The long slide's image and its name, both from the same slide.
  ///
  /// Through the `Wrap` they share rather than `find.byType(Image).first` and
  /// `find.text(_longName).first`, which are a different slide's image and
  /// this one's name: every slide draws its image at [_imageSide], so those
  /// did discriminate, but only by a coincidence nothing asserts. Each name is
  /// built twice - once in the `Stack` that measures and once in the viewport -
  /// and `.first` is the measuring copy.
  (Rect, Rect) longSlide(WidgetTester tester) {
    // Anchored on the slide's own padding rather than on the `Wrap` it holds:
    // the `Wrap` is the thing under test, so a mutation that takes it away
    // would make this helper fail on a missing finder instead of on the
    // geometry the case is about.
    final slide = find
        .ancestor(
          of: find.text(_longName).first,
          matching: find.byWidgetPredicate(
            (w) => w is Padding && w.padding == _slidePadding,
          ),
        )
        .first;
    return (
      tester.getRect(find.descendant(of: slide, matching: find.byType(Image))),
      tester.getRect(
        find.descendant(of: slide, matching: find.text(_longName)),
      ),
    );
  }

  /// The carousel's height, which is what #471 is about.
  ///
  /// The `PageView`'s own box: it is `Positioned.fill` inside the `Stack` that
  /// measures the slides, so its height *is* the height that `Stack` worked
  /// out. Not the card's - `_FirmwareControls` adds a second dropdown for a
  /// firmware with variants, so the card is legitimately 78 pixels shorter on
  /// the page showing one without, and a case reading the card cannot tell
  /// that from the carousel moving. Measured, which is how this file got it
  /// wrong first.
  double carouselHeight(WidgetTester tester) =>
      tester.getSize(find.byType(PageView)).height;

  group('the card fits', () {
    for (final scale in _scales) {
      for (final width in _widths) {
        testWidgets('at $width and a scaler of $scale', (tester) async {
          expect(await render(tester, width: width, scale: scale), isNull);
        });
      }
    }
  });

  testWidgets('the image does not grow with the text', (tester) async {
    // The slide is a `Wrap` now, so the image and the name are siblings with
    // no flex between them: the name taking two lines must not be able to
    // squeeze or stretch the image. Measured at the extreme, where a slide is
    // several times its default height.
    for (final scale in _scales) {
      expect(await render(tester, width: 320, scale: scale), isNull);
      expect(
        tester.getSize(find.byType(Image).first),
        const Size(_imageSide, _imageSide),
        reason: 'at a scaler of $scale',
      );
    }
  });

  testWidgets('the card grows with the text instead of clipping it', (
    tester,
  ) async {
    // The positive half of the sweep above, and **measured to be the only
    // thing that catches the original bug.** Putting `SizedBox(height: 110)`
    // back around the carousel's `Stack` fails this case and *nothing else* in
    // this file or the header's - the slides are inside a `Stack` that clips,
    // so the sweep's `takeException` stays null while the text is cut off.
    // Which is the trap the whole file is written around: a release build
    // neither throws nor clips either, so "no exception" is also what a card
    // silently losing its text reports. Without this case, any constant tall
    // enough for the default scale would pass.
    expect(await render(tester, width: 360), isNull);
    final atDefault = carouselHeight(tester);

    expect(await render(tester, width: 360, scale: 2), isNull);
    expect(carouselHeight(tester), greaterThan(atDefault));
  });

  testWidgets('gives the name the full width rather than a narrow column', (
    tester,
  ) async {
    // **The half `takeException` cannot see.** The slide was a `Row` of the
    // image and an `Expanded` column, and that arrangement does not overflow
    // once the carousel measures its slides - it just hands the name a slot
    // about 174 dp wide on a phone and lets `Text` spend it a few letters at a
    // time. That is #463's defect exactly, one widget over, and a sweep
    // asserting `takeException` is null passes straight through it.
    //
    // So this is the `Wrap`'s own claim: a name too long for the room beside
    // the image goes *below* it and gets the whole width.
    //
    // Measured the same way as the case above: restoring the `Row` and its
    // `Expanded` column fails this case alone, and leaves every sweep case
    // green.
    expect(await render(tester, width: 320, scale: 2), isNull);

    final (image, name) = longSlide(tester);

    expect(
      name.left,
      lessThan(image.right),
      reason: 'the name dropped below the image rather than beside it',
    );
    // And it is wider than the slot it used to get, which is what "not a
    // column of letters" means in a number: the beside-the-image slot is the
    // carousel less the image and the gap between them.
    final carousel = tester.getRect(find.byType(PageView));
    expect(name.width, greaterThan(carousel.width - image.width));
  });

  testWidgets('leaves the name beside the image while it fits', (tester) async {
    // The other side of the `Wrap`, and the reason it is a `Wrap` rather than
    // a `Column`: with room for both, the slide looks exactly as it did.
    expect(await render(tester, width: 900), isNull);

    final (image, name) = longSlide(tester);

    expect(name.left, greaterThanOrEqualTo(image.right));
    expect(name.top, lessThan(image.bottom));
  });

  testWidgets('is one height whichever slide is showing', (tester) async {
    // **The reason the carousel measures every slide and not the current
    // one.** Sizing to the current slide is less whitespace and the wrong
    // trade: the card would change height under the finger mid-swipe, moving
    // the update button and the two setting rows while the slide is still
    // moving.
    expect(await render(tester, width: 320), isNull);

    // The premise, asserted rather than assumed: the two slides want
    // different heights at this width, so "the same height on both pages" is
    // a claim about the fix rather than a coincidence of two equal slides.
    // `.first` is the copy inside the `Stack` that does the measuring; each
    // name is built twice, once there and once in the viewport.
    final short = tester.getSize(find.text(_shortName).first).height;
    final long = tester.getSize(find.text(_longName).first).height;
    expect(long, greaterThan(short), reason: 'premise');

    final onFirst = carouselHeight(tester);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(carouselHeight(tester), onFirst);
  });
}
