import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/models/device_info.dart';
import 'package:qunleashed/pages/devices/widgets/flipper_mockup.dart';
import 'package:qunleashed/pages/devices/widgets/page_header.dart';
import 'package:qunleashed/services/localization/gen/l10n_generated.dart';
import 'package:qunleashed/theme/theme.dart';

/// Built once: `buildAppTheme` runs an HSL loop per call, and every case here
/// would pay it again for the same answer.
final ThemeData _theme = buildAppTheme(
  Brightness.dark,
  const Color(0xFFCC241D),
);

/// That the device page's header fits the phone it is drawn on.
///
/// `DevicePageHeader` has two layouts, and **width alone decides which**.
/// `DeviceTab` passes `infoEntries: wide ? ctrl.deviceInfoEntries : const []`
/// off `MediaQuery`, and `DeviceInfoReader.infoEntries` returns three entries
/// whatever is in the map - `-` for each value when nothing is connected - so
/// the hero's `infoEntries.isNotEmpty` is a second reading of the same width
/// and never a reading of the device. #411 supposed otherwise, and so did the
/// first draft of this file.
///
/// So the narrow row is what is drawn whenever the header's own constraints
/// are under 560: every phone, and a window wide enough for the rail whose
/// *page* the rail leaves narrower than that. Above 560 it is unreachable,
/// which is why the sweep below stops at 559.
///
/// That layout is a `Row` of a fixed 238-wide mockup beside a column of two
/// `Text`s, and the column carried no flex factor - so it asked for its
/// intrinsic width, the row asked for more than it had, and the title lost its
/// tail. Debug paints the stripes and throws; release reports nothing, and
/// `Flex.clipBehavior` being `Clip.none` the text is not clipped by the row
/// either - it is painted past its edge and cut off at the window's. Either
/// way the tail is gone with nothing to say so, which is how it survived to
/// #411.
///
/// ## The font here is wider than the real one, and that comes first
///
/// `flutter_test` renders every ASCII glyph of its test font as a square of
/// the font size, so "Flipper Zero" measures 144 px at 12 px - 147 with the
/// theme's 0.25 of letter spacing - where a proportional font gives roughly
/// half that, and a line is 1.44 times the font size against about 1.17.
///
/// **Every width and every scale in this file is therefore pessimistic**, and
/// so is every measurement quoted in it. That is what makes it a useful gate:
/// a layout that fits here fits the real font with room over, and a
/// translation that is merely long cannot be what broke it. It is also why
/// none of these numbers is a statement about a user's screen - for that, see
/// the comment in `lib/pages/devices/widgets/page_header.dart`, which works
/// from real metrics.
///
/// Measured through the whole app before the fix, in this font, with the
/// default English strings: the row overflowed by 83 px at 320 dp, 43 px at
/// 360 dp, 13 px at 390 dp and 1 px at 402 dp, and fitted from 403.
///
/// The other side of that is what this file does **not** claim.
///
///  * Nothing here asserts the title is *readable* at a given width, because
///    with this font it would not be and the assertion would say nothing about
///    the shipped app. The claim is the one the bug was about: the layout is
///    legal, so what does not fit is ellipsised rather than clipped away
///    unannounced.
///  * For the hero branch, "nothing was thrown" is weaker than it reads. Its
///    full-info button is a `Positioned` in a `Stack`, and a `Stack` reports no
///    overflow - a long `deviceFullInfo` paints over the UID line instead,
///    silently. That overlap is real today and filed as #417 rather than fixed
///    here, so do not read a green hero case as "the hero fits".
void main() {
  /// What a connected Flipper's info map carries that the header reads.
  ///
  /// `deviceInfo` is the raw map and the hero consults it **first**, falling
  /// back to `infoEntries` only when a key is missing - so a fixture that
  /// passes entries alone renders a hero with an empty `Wrap` and no UID,
  /// which is how the first draft of this file gated nothing. #411.
  const info = {
    'hardware_name': 'MyFlip42',
    'firmware_version': '1.3.4',
    'firmware_build_date': '2026-10-26',
    'hardware_uid': 'A1B2C3D4E5F60718293A4B5C6D7E',
  };

  /// Builds the header at [width] and [textScale] and returns what it threw.
  ///
  /// [infoEntries] is the branch's other half and is passed rather than
  /// defaulted, because what the page sends depends on the *window* while
  /// [width] here is the header's own: `const []` below 560, three entries
  /// above it, connected or not.
  Future<Object?> render(
    WidgetTester tester,
    double width, {
    required String title,
    double textScale = 1,
    Locale? locale,
    List<MapEntry<String, String>> infoEntries = const [],
    Map<String, String> deviceInfo = const {},
  }) async {
    // **From an empty tree every time.** A `RenderFlex` reports its overflow
    // once per render object - `_overflowReportNeeded` in
    // `DebugOverflowIndicatorMixin` goes false after the first report and only
    // `reassemble` sets it back - and `pumpWidget` updates the existing
    // elements rather than rebuilding them, so without this a second
    // overflowing width in the same case throws nothing at all and reads as a
    // pass. Found by measuring: the sweep came back non-monotonic.
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        // The hero's own strings are translated - `fw {version}`,
        // `built {date}`, `UID {uid}` and the button - and `context.l10n`
        // falls back to the global locale without a scope, so the sweep below
        // would have run eight times in English.
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        // A column with the header at the top of it, which is what the page
        // is: the header gets the window's width and as much height as it
        // asks for, and nothing promises it a number. The inset is 0 because
        // a test view has no status bar.
        home: Scaffold(
          body: Column(
            children: [
              DevicePageHeader(
                topInset: 0,
                title: title,
                // Hard-coded in `DeviceTab`, never translated, and wider than
                // the English title - so it sets the floor on its own.
                subtitle: 'Flipper Zero',
                active: deviceInfo.isNotEmpty,
                infoEntries: infoEntries,
                deviceInfo: deviceInfo,
                // Non-null exactly when `ctrl.isConnected`, which is exactly
                // when the entries arrive, so it travels with them.
                onOpenFullInfo: deviceInfo.isEmpty ? null : () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.takeException();
  }

  // 256 is the floor the row has whatever flex the column carries - the mockup
  // is a `SizedBox(height: 100)` over a 238:100 `AspectRatio` given unbounded
  // width, so it claims 238 plus 18 of padding and nothing can shrink it. No
  // phone reaches it, but no desktop runner sets a minimum window size either,
  // so a dragged window does. 320 is the narrowest phone the project declares,
  // 360 is the common Android baseline, 390 the iPhone 12-14 and 412 the
  // Pixel. 520 is the reachable wide case: a window over 560 whose page the
  // rail leaves under it. 559 is the last width this layout is drawn at.
  const widths = [256.0, 320.0, 360.0, 390.0, 412.0, 520.0, 559.0];

  group('the narrow header fits', () {
    // **One locale, not eight.** This layout renders no translated string of
    // its own - the title is a parameter and the subtitle is the hard-coded
    // 'Flipper Zero' - so sweeping the locales would only be sweeping the
    // length of one string, and `Flexible` over a bounded `Text` makes the
    // layout legal at any length by construction. The longest of the eight is
    // Spanish's "Sin dispositivo", 15 characters against the English nine and
    // two thirds wider in a font whose every glyph is a fixed square; the name
    // case below is wider still, so that is the one that stresses this. The
    // hero group does sweep the locales, because its strings are built inside
    // the widget rather than passed in.
    testWidgets('with the longest no-device title', (tester) async {
      const es = Locale('es');
      final title = lookupL10n(es).deviceStateNoDevice;
      for (final width in widths) {
        expect(
          await render(tester, width, title: title, locale: es),
          isNull,
          reason: '$title at $width',
        );
      }
    });

    // The firmware caps a name at 8 characters
    // (`FURI_HAL_VERSION_NAME_LENGTH`) and `DeviceInfoReader.deviceName`
    // returns `hardware_name` verbatim - so the cap is the device's promise
    // and not this app's, and a name arriving over RPC is as long as it likes.
    testWidgets('with a name longer than the firmware allows', (tester) async {
      for (final width in widths) {
        expect(
          await render(tester, width, title: 'Flipper-Zero-Of-Mine'),
          isNull,
          reason: 'a 20-character name at $width',
        );
      }
    });

    // The axis the fix moved. A wrapped title is two lines where it used to
    // be forced onto one, so the header's height became the binding
    // constraint instead of its width - and against the page's old fixed
    // reservation of 114 it overflowed the *bottom* from a scale of 2, which
    // is iOS AX1. The header sizes to its content now, so these hold at any
    // scale: 1.3 is the top of Android's ordinary font-size slider and 3.1
    // the top of the iOS accessibility sizes.
    for (final scale in const [1.3, 2.0, 3.1]) {
      testWidgets('at a text scale of $scale', (tester) async {
        for (final width in const [320.0, 360.0, 412.0]) {
          expect(
            await render(
              tester,
              width,
              title: lookupL10n(const Locale('es')).deviceStateNoDevice,
              textScale: scale,
            ),
            isNull,
            reason: 'scale $scale at $width',
          );
        }
      });
    }
  });

  group('the hero header fits', () {
    // `DeviceInfoReader.infoEntries` is what the page passes
    // (`ctrl.deviceInfoEntries`), so the branch is selected the way the page
    // selects it rather than by a hand-written list.
    final entries = DeviceInfoReader.infoEntries(info);

    // Every locale here, because the hero builds its own strings -
    // `fw {version}`, `built {date}`, `UID {uid}` and the button's label -
    // and the longest of them is what breaks a `Wrap` onto another run. 560
    // is the narrowest it is ever drawn at and 900 a desktop window; 1200 and
    // 1600 only give the same `Wrap` more room than it needs.
    for (final locale in L10n.supportedLocales) {
      testWidgets('with ${locale.languageCode}\'s metadata', (tester) async {
        for (final width in const [560.0, 600.0, 900.0]) {
          expect(
            await render(
              tester,
              width,
              title: 'MyFlip42',
              locale: locale,
              infoEntries: entries,
              deviceInfo: info,
            ),
            isNull,
            reason: '${locale.languageCode} at $width',
          );
        }
      });
    }

    testWidgets('at the branch boundary, with its metadata on screen', (
      tester,
    ) async {
      expect(
        await render(
          tester,
          560,
          title: 'MyFlip42',
          locale: const Locale('en'),
          infoEntries: entries,
          deviceInfo: info,
        ),
        isNull,
      );

      // **The fixture is checked, not assumed.** Every claim in this group is
      // that nothing overflowed, and a hero with no metadata in it cannot
      // overflow - which is exactly what the first draft gated: it passed
      // `infoEntries` keyed `'Firmware version'` where the lookup is
      // `l10n.infoFirmwareVersion`, `'Firmware Version'`, and left
      // `deviceInfo` empty, so the `Wrap` and the UID line were absent and
      // the sweep above was measuring an empty column.
      expect(find.text('fw 1.3.4'), findsOneWidget);
      expect(find.text('built 2026-10-26'), findsOneWidget);
      expect(find.textContaining('UID A1B2C3D4'), findsOneWidget);
      expect(find.text('Full Info'), findsOneWidget);
    });

    // The hero was the worse of the two for text scale and it was already
    // broken before this change: four lines of metadata beside the mockup
    // overflowed the page's fixed 114 from a scale of **1.3**, which no
    // accessibility setting is needed to reach, at every width from 560 to
    // 1600. It is a `Wrap`, so its height steps when a run breaks - nothing
    // proportional could have tracked that, which is half of why the page
    // reserves nothing now.
    for (final scale in const [1.3, 2.0, 3.1]) {
      testWidgets('at a text scale of $scale', (tester) async {
        for (final width in const [560.0, 600.0, 900.0]) {
          expect(
            await render(
              tester,
              width,
              title: 'MyFlip42',
              textScale: scale,
              locale: const Locale('en'),
              infoEntries: entries,
              deviceInfo: info,
            ),
            isNull,
            reason: 'scale $scale at $width',
          );
        }
      });
    }
  });

  // `Flexible` and not `Expanded`, which is the difference between giving the
  // column the room it needs and giving it all of it. `Expanded` would pin the
  // mockup to the left edge at every width the text fits in, which is a
  // redesign of the header rather than a fix to it.
  //
  // At 520 with the entries a disconnected wide window sends - three of them,
  // values `-` - because that is the widest the narrow row is reachable at and
  // it leaves 117 px of slack for the assertion to read. It is also the only
  // case here that holds the branch itself: three entries present and the row
  // drawn anyway, which is what "width alone decides" means.
  testWidgets('the narrow header stays centred while the text fits', (
    tester,
  ) async {
    expect(
      await render(
        tester,
        520,
        title: 'No device',
        infoEntries: DeviceInfoReader.infoEntries(const {}),
      ),
      isNull,
    );

    expect(
      find.byType(FlipperMockupHero),
      findsNothing,
      reason: 'the hero was drawn below 560',
    );
    expect(
      tester.getTopLeft(find.byType(FlipperMockupWidget)).dx,
      greaterThan(0),
      reason: 'the mockup is flush left, so the column took the whole row',
    );
  });

  // Fitting is not the whole of it, because a `Text` whose word is wider than
  // its box raises nothing - it clips, and the row around it stays legal. So
  // the flex factor alone would pass every case above while the title still
  // lost characters. These are what hold the bounds that turn that into an
  // ellipsis.
  group('the narrow header truncates rather than clips', () {
    bool exceeded(WidgetTester tester, String text) =>
        tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

    testWidgets('at a width neither line fits', (tester) async {
      expect(await render(tester, 320, title: 'No device'), isNull);

      expect(exceeded(tester, 'No device'), isTrue);
      expect(exceeded(tester, 'Flipper Zero'), isTrue);
      // The witness is `didExceedMaxLines`, which is the paragraph's own
      // answer and goes false the moment either bound is dropped. What cannot
      // be read back is *how* it truncated, because the framework exposes
      // nothing for it - so ellipsis against `clip` is the one structural line
      // here, and it is the difference between a visible tail and a word that
      // simply stops.
      for (final text in const ['No device', 'Flipper Zero']) {
        expect(
          tester.widget<Text>(find.text(text)).overflow,
          TextOverflow.ellipsis,
          reason: '"$text" would truncate with nothing to show for it',
        );
      }
    });

    testWidgets('and not at a width they do', (tester) async {
      expect(await render(tester, 412, title: 'No device'), isNull);

      expect(exceeded(tester, 'No device'), isFalse);
      expect(exceeded(tester, 'Flipper Zero'), isFalse);
    });
  });
}

// ── What this does not pin ───────────────────────────────────────────────────
//
// Eleven mutations run, ten killed:
//
//  * dropping the flex factor, against the longest title and the long name -
//    which the whole app catches too, since `test/shell_rebuild_test.dart`
//    pumps at 360 and `flutter_test` turns the overflow into a failure;
//  * `Expanded` in place of `Flexible`;
//  * unbounding the title, unbounding the subtitle, and swapping the ellipsis
//    for a clip;
//  * giving the header a fixed height again, against the narrow case and the
//    hero separately - the mutation the page's old `Stack` *was*;
//  * inverting the fitting case's `didExceedMaxLines`, so it cannot pass by
//    asserting nothing;
//  * misspelling a key in the hero's `deviceInfo`, which is the failure the
//    boundary case's content assertions exist for.
//
// One survives, and it is not an oversight: **`maxLines: 2` on the title
// narrowed to 1.** Two lines is what lets a translation of two words wrap
// instead of ellipsising - "Sin dispositivo" reads whole over two lines and as
// "Sin dis..." over one. Both are legal layouts and the difference is only
// visible with real font metrics, so there is nothing here that can tell them
// apart; asserting `maxLines == 2` would restate the source rather than test
// it.
//
// What is still unpinned is the hero's full-info button - **#417**. It is a
// `Positioned` over a `Stack`, so no amount of overlap throws, and it paints
// over the UID line at 560-600 dp today. A case for it needs a geometric
// assertion rather than `takeException`, and the fix is a change to the hero's
// own layout rather than to the row this file is about.
