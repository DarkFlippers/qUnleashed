import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/app/nav_bar.dart';
import 'package:qunleashed/services/localization/gen/l10n_generated.dart';
import 'package:qunleashed/theme/theme.dart';

import 'view_size.dart';

/// Built once: `buildAppTheme` runs an HSL loop per call, and every case here
/// would pay it again for the same answer.
final ThemeData _theme = buildAppTheme(
  Brightness.dark,
  const Color(0xFFCC241D),
);

/// The size the bar is designed at. `_TabLabel`'s copy is private; "is drawn
/// at the size the bar is designed at" and "follows the scaler up" are what
/// say this one still agrees with it.
const double _fontSize = 10;

/// The size it will not draw under. Pinned by "stops at the floor and is cut
/// after all" and by the invariants in `expectFitted`.
const double _minFontSize = 8;

/// A sixteen-glyph label, for the cases that quote a number.
///
/// Synthetic on purpose: the arithmetic below is about the glyph count, and a
/// translation that happened to be sixteen glyphs long would make a
/// translator's edit read as a fit regression.
const String _sixteen = 'Mmmmmmmmmmmmmmmm';

/// That the bottom bar's labels fit the quarter of the bar they are given.
///
/// Each of the four tabs is an `Expanded`, so a label gets a quarter of the
/// bar less the 16 of padding around it - 74 on a 360 dp phone with no cutout,
/// 64 on a 320. Three of those labels are nouns. The fourth is a device state,
/// and cut at a fixed size the states stop telling each other apart:
/// `deviceStateSyncing` and `deviceStateSynced` share nine to thirteen leading
/// characters in seven of the eight locales, and `deviceStateConnecting` and
/// `deviceStateConnected` share six or seven in all eight of them. #425, which
/// #424 made visible by making `synced` reachable.
///
/// ## This font cannot measure that, and no width here is a phone's
///
/// `flutter_test` renders every glyph as a square of the font size, about
/// twice what Roboto gives: "Synchronisierung" measures 164 here at 10 dp
/// against 82.88 in Roboto Bold, letter spacing in both. So the collision is
/// *more* reachable here than on a phone - and the fix cannot be shown to
/// remove it at a phone's width, because at 360 both German strings are
/// already at the floor in this font and both are cut, which leaves no before
/// and after to assert. Two widths stand in for phones instead, and only
/// through that ratio: a box of 134 (at 600) is what this font spends where
/// Roboto spends the 66 of a small phone, and 209 (at 900) where it spends the
/// 104 of a large one.
///
/// What the file checks is the contract, which holds in any font:
///
///  * no size is above what the user asked for;
///  * none is below [_minFontSize], unless the user asked for less than that;
///  * and **a label is cut only once the floor has bound** - above the floor,
///    what is on screen is the whole string.
///
/// The last one is the fix: strings that are whole cannot be read as one
/// another. The per-locale group then says that this is not a vacuous win -
/// the sync pair is whole at a small phone's box, and of the eight states at a
/// large phone's box at most one is ever cut, so no two of them can read the
/// same.
///
/// Where the real font puts that boundary is arithmetic off Roboto's own
/// advance widths, and **nothing in this repository re-derives it**: it is
/// recorded in `lib/app/nav_bar.dart` and in the PR. Of the 28 pairs the eight
/// states make, over four phone widths and seven scalers, 20 collided before
/// the fit and none does after.
void main() {
  /// The size [label] is painted at: the style's size through whatever
  /// scaler reached the paragraph, and through the scale it is drawn under.
  ///
  /// The fit is a paint transform rather than a font size - the paragraph is
  /// laid out at the size the user asked for and scaled down into the slot -
  /// so the style alone answers for none of it. Measured as what was painted
  /// over what was laid out, and not off the transform: `getMaxScaleOnAxis`
  /// takes the largest of the three axes and the z scale is 1, so it reports
  /// a confident 1.0 for any flattening of a 2D box.
  double paintedSize(WidgetTester tester, String label) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
    final asked = paragraph.textScaler.scale(paragraph.text.style!.fontSize!);
    return asked *
        tester.getRect(find.text(label)).width /
        paragraph.size.width;
  }

  /// Whether [label] had to truncate, which the paragraph answers itself.
  bool cut(WidgetTester tester, String label) =>
      tester.renderObject<RenderParagraph>(find.text(label)).didExceedMaxLines;

  /// The box [label] was given to fit, so that a change to the slot or its
  /// padding reports as the slot moving rather than as the fit moving.
  double boxOf(WidgetTester tester, String label) {
    final box = find.ancestor(
      of: find.text(label),
      matching: find.byType(LayoutBuilder),
    );
    expect(box, findsOneWidget);
    // Its constraint rather than its size: a label narrower than the slot
    // makes the box narrower with it, and the slot is the question.
    return tester.renderObject<RenderBox>(box).constraints.maxWidth;
  }

  /// Pumps one [TabLabel] in the box a slot gives it.
  ///
  /// The bar's own labels are four ARB nouns since #429, so there is no way
  /// left to hand the bar a label of a chosen length - which is the point of
  /// that change and why `TabLabel` is `@visibleForTesting`. [box] defaults
  /// to 134, the slot on the 600 dp window every number in this file is
  /// measured against: a quarter of it less the 16 of padding.
  Future<void> pumpLabel(
    WidgetTester tester,
    String label, {
    double box = 134,
    double textScale = 1,
    Locale? locale,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: box,
              child: TabLabel(label: label, color: const Color(0xFFFFFFFF)),
            ),
          ),
        ),
      ),
    );
  }

  /// Pumps the bar with [deviceLabel] on a [width] dp window.
  ///
  /// Portrait unless [landscape], because `FlipperRootScaffold.isWide` reads
  /// `MediaQuery` and a landscape window gets the icons-only rail. From an
  /// empty tree each time: a `RenderFlex` reports an overflow once per render
  /// object, and `pumpWidget` reuses the elements, so a second overflow in the
  /// same case would pass unseen.
  Future<void> pumpBar(
    WidgetTester tester, {
    required String deviceLabel,
    required double width,
    double textScale = 1,
    Locale? locale,
    bool landscape = false,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    sizeView(tester, Size(width, landscape ? width / 2 : 2 * width));
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: FlipperRootScaffold(
          currentTab: FlipperRootTab.device,
          onTabSelected: (_) {},
          deviceLabel: deviceLabel,
          deviceStatus: DeviceTabStatus.ready,
          railGroups: const [],
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }

  /// The contract, over every label in the bar at once.
  void expectFitted(
    WidgetTester tester,
    L10n strings,
    String deviceLabel,
    double asked,
    String where,
  ) {
    expect(tester.takeException(), isNull, reason: where);
    // A scaler below 1 is the one case where the floor is not the floor: the
    // cap wins, because a size nobody asked for is not an improvement.
    final floor = math.min(_minFontSize, asked);
    for (final label in [
      deviceLabel,
      strings.navArchive,
      strings.navApps,
      strings.navTools,
    ]) {
      final size = paintedSize(tester, label);
      expect(
        size,
        lessThanOrEqualTo(asked),
        reason: '"$label" painted past the scaler at $where',
      );
      expect(
        size,
        greaterThanOrEqualTo(floor),
        reason: '"$label" painted under the floor at $where',
      );
      if (cut(tester, label)) {
        expect(
          size,
          floor,
          reason: '"$label" cut while there was still room to shrink at $where',
        );
      }
    }
  }

  group('a label that fits', () {
    testWidgets('is drawn at the size the bar is designed at', (tester) async {
      await pumpLabel(tester, 'Synced');
      expect(paintedSize(tester, 'Synced'), _fontSize);
      expect(cut(tester, 'Synced'), isFalse);
      expect(boxOf(tester, 'Synced'), 134);
    });

    // The cap, and the reason it is one: a short label has room to grow into
    // and must not take it.
    testWidgets('follows the scaler up', (tester) async {
      await pumpLabel(tester, 'Synced', textScale: 1.5);
      expect(paintedSize(tester, 'Synced'), _fontSize * 1.5);
      expect(cut(tester, 'Synced'), isFalse);
    });
  });

  group('a label that does not', () {
    // The whole arithmetic, and all of it is the layout's. The box is 134;
    // sixteen glyphs of this font at 10 dp, with the quarter of letter
    // spacing Material's `bodyMedium` charges on each, measure 164; so
    // `scaleDown` draws them at 134 / 164 of 10.
    //
    // Nothing here is modelled, which is the point of the number: it is the
    // ratio of two widths the tree measured itself. The draft this replaced
    // computed the size instead, and got 8.36 when it read the style without
    // the letter spacing and 8.16 from a single probe and a straight ratio.
    testWidgets('shrinks to exactly what fits', (tester) async {
      await pumpLabel(tester, _sixteen);
      expect(boxOf(tester, _sixteen), 134);
      expect(paintedSize(tester, _sixteen), closeTo(8.17, 0.005));
      expect(cut(tester, _sixteen), isFalse);
    });

    // Per slot, not per bar. Making the four labels agree on one size - the
    // smallest of the four - is the obvious tidy-up, and it would cost the
    // shorter ones their size for nothing.
    //
    // Driven at a scaler rather than with a long label, because #429 left the
    // bar no long labels: Russian's `navTools` is the widest of the four and
    // 3.1 is the largest scaler Android offers, which is enough to make it
    // the only one that has to shrink.
    testWidgets('leaves the labels beside it alone', (tester) async {
      // Russian at twice the font size, which is the cheapest arrangement
      // that still has both kinds of slot in one bar: in a 134 box at an
      // asked 20, "Архив" and "Device" fit and "Приложения" and
      // "Инструменты" do not.
      //
      // It used to be driven by a long label in the device slot. #429 left
      // the bar four ARB nouns and no way to hand it a long one, so the
      // scaler is the lever now - and the claim is better for it, because the
      // four labels it compares are the four the bar really draws.
      await pumpBar(
        tester,
        deviceLabel: 'Synced',
        width: 600,
        textScale: 2,
        locale: const Locale('ru'),
      );
      final strings = lookupL10n(const Locale('ru'));

      expect(paintedSize(tester, strings.navArchive), _fontSize * 2);
      expect(
        paintedSize(tester, strings.navTools),
        lessThan(_fontSize * 2),
        reason: 'the premise: this one has to shrink',
      );
    });

    // **This case is the trade, not a mechanism.** A label already as wide as
    // its slot has nowhere to grow, so a raised text-size setting moves it by
    // the width of the letter spacing and no further: measured here, 8.17 at
    // 1.0 and 8.32 at 3.1, where the user asked for 31. The label stays whole
    // instead, which is what #425 is about and what the issue chose - "let the
    // text be as small as it must be rather than clipped". Honouring both
    // takes a different layout, and that is #429.
    //
    // So if this case fails because the spread grew, the question is which of
    // the two promises moved - not which number to update.
    testWidgets('barely moves when the scaler does', (tester) async {
      final sizes = <double, double>{};
      for (final scale in const [1.0, 1.3, 2.0, 3.1]) {
        await pumpLabel(tester, _sixteen, textScale: scale);
        sizes[scale] = paintedSize(tester, _sixteen);
        expect(cut(tester, _sixteen), isFalse, reason: 'at $scale');
        expect(
          sizes[scale],
          lessThan(_fontSize),
          reason: 'the fit grew past the design size at $scale',
        );
      }
      final spread =
          sizes.values.reduce(math.max) - sizes.values.reduce(math.min);
      expect(spread, lessThan(0.3), reason: '$sizes');
    });

    // Under the floor the ellipsis comes back, and German's longest state is
    // the string that gets there: 27 characters, so (134 - 6.75) / 27 is 4.71,
    // which is not a label any more. It is also the string the equal slots
    // were chosen for - see `_BottomTabSlot` - and the per-locale group is
    // what says it still cannot be read as another state.
    testWidgets('stops at the floor and is cut after all', (tester) async {
      final long = lookupL10n(const Locale('de')).deviceStateConnecting;
      await pumpLabel(tester, long, locale: const Locale('de'));
      expect(paintedSize(tester, long), _minFontSize);
      expect(cut(tester, long), isTrue);
      // Cut with an ellipsis rather than clipped: what is gone has to be
      // visibly gone, and `didExceedMaxLines` cannot tell those two apart.
      expect(
        tester.widget<Text>(find.text(long)).overflow,
        TextOverflow.ellipsis,
      );
    });

    // Below the floor the floor is not one: what the user asked for wins,
    // and the label is cut at that size rather than drawn bigger than they
    // asked. No phone goes there - Android stops at 0.85 and iOS near 0.82 -
    // but the clamp is one `min`, and without it the cap lands *under* the
    // slot and the ellipsis eats the difference, which is what the width
    // below is for.
    testWidgets('and stays small when the scaler asks for small', (
      tester,
    ) async {
      final long = lookupL10n(const Locale('de')).deviceStateConnecting;
      await pumpLabel(tester, long, textScale: 0.5, locale: const Locale('de'));
      expect(paintedSize(tester, long), _fontSize * 0.5);
      expect(cut(tester, long), isTrue);
      expect(
        tester.getRect(find.text(long)).width,
        closeTo(boxOf(tester, long), 6),
      );
    });

    // `FlipperRootScaffold` is public and its label is a plain `String`.
    // Nothing fits an empty one and nothing needs to: `RenderFittedBox`
    // paints no child whose size is empty, rather than dividing by it. The
    // draft this replaced computed the scale itself and needed a guard here.
    testWidgets('and an empty one is no label at all', (tester) async {
      await pumpLabel(tester, '');
      expect(tester.takeException(), isNull);
      expect(find.text(''), findsOneWidget);
    });
  });

  group('the row of icons', () {
    /// The four 42x24 icon boxes, in bar order.
    List<Rect> icons(WidgetTester tester) {
      final found = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 42,
      );
      // Without this the two cases below can agree on nothing at all: a
      // changed icon box makes the list empty, and an empty list equals an
      // empty list.
      expect(found, findsNWidgets(4));
      return [for (var i = 0; i < 4; i++) tester.getRect(found.at(i))];
    }

    // The reserved height is what holds these. A shrinking label makes a
    // shorter line box, the slots are a `Row` of centred columns, and without
    // the line reserved at the asked size the device tab's icon would sit
    // below its neighbours - and hop as the state word changed under it.
    testWidgets('stays level under a shrunken label', (tester) async {
      await pumpBar(
        tester,
        deviceLabel: 'Synced',
        width: 600,
        textScale: 2,
        locale: const Locale('ru'),
      );
      final tops = icons(tester).map((r) => r.top).toSet();
      expect(tops, hasLength(1), reason: '$tops');
      // The premise, so this cannot pass on a bar where nothing shrank -
      // which is what it would have done after #429 had it kept driving the
      // device slot with a long string.
      final strings = lookupL10n(const Locale('ru'));
      expect(paintedSize(tester, strings.navTools), lessThan(_fontSize * 2));
    });

    // There was a case here for the icon staying put *as the state word
    // changed*, which was the hop the reserved line exists to prevent. #429
    // removed its subject rather than its mechanism: the device tab's label
    // is a noun that does not change, and the state it used to carry is a dot
    // in the icon's own box, so there is no longer a word whose width can
    // move anything. The reserved line is still pinned, by the two cases
    // around this note.

    // And the label is centred in the line that was reserved rather than
    // pushed to the top of it. That is the visible cost of reserving one, and
    // it is a choice: a shrunken label shares its middle with the labels
    // beside it rather than its baseline.
    testWidgets('centres a shrunken label in the line it kept', (tester) async {
      await pumpBar(
        tester,
        deviceLabel: 'Synced',
        width: 600,
        textScale: 2,
        locale: const Locale('ru'),
      );
      final strings = lookupL10n(const Locale('ru'));
      final middles = [
        strings.navDevice,
        strings.navArchive,
        strings.navApps,
        strings.navTools,
      ].map((l) => tester.getRect(find.text(l)).center.dy).toSet();
      expect(middles, hasLength(1), reason: '$middles');
      expect(
        paintedSize(tester, strings.navTools),
        lessThan(paintedSize(tester, strings.navArchive)),
        reason: 'the premise: one of the four shrank and one did not',
      );
    });
  });

  // The guard that used to be here - that the `deviceState` keys in the ARB
  // are exactly the states the bar can draw - moved to
  // `shell_device_label_test.dart` with #429. It was never about the fit, and
  // the bar does not draw a state any more; what it is really about is a
  // string nobody can reach, which is `_deviceLabel`'s business and that
  // file's subject.

  // The wide layout has no labels to fit, and the fit would not save them if
  // it had: the rail is 58 wide.
  testWidgets('the rail draws no label at all', (tester) async {
    await pumpBar(tester, deviceLabel: 'Synced', width: 900, landscape: true);
    expect(find.text('Synced'), findsNothing);
  });

  // Every locale, because what fits is a property of the translations.
  //
  // **This group used to be about the device states**, and #429 is why it is
  // not. The bar drew the link state as the device tab's label - eight
  // sentences, of which `deviceStateSyncing` and `deviceStateSynced` share
  // nine to thirteen leading characters in seven of the eight locales - so
  // the group's real claim was that no state could be cut down into another
  // state. That claim is unreachable now rather than merely true: the tab's
  // label is `navDevice`, a noun, and the state is a dot on its icon plus the
  // tab's semantics label. `test/nav_bar_device_badge_test.dart` is where the
  // state went.
  //
  // What is left is the contract itself over the four labels the bar really
  // draws, which is wider than the old subject in two ways: all four slots
  // rather than one, and four scalers rather than two.
  group('every locale', () {
    for (final locale in L10n.supportedLocales) {
      testWidgets('in ${locale.languageCode}', (tester) async {
        final strings = lookupL10n(locale);
        for (final width in const [320.0, 600.0]) {
          for (final scale in const [1.0, 1.3, 2.0, 3.1]) {
            await pumpBar(
              tester,
              deviceLabel: 'Synced',
              width: width,
              textScale: scale,
              locale: locale,
            );
            expectFitted(
              tester,
              strings,
              strings.navDevice,
              _fontSize * scale,
              'at $width, scale $scale',
            );
          }
        }
      });
    }
  });
}

// ## Mutations
//
// Nine against `_TabLabel`. Eight killed:
//
// | mutation | killed by |
// |---|---|
// | the width cap dropped, so there is no floor | "stops at the floor", and every locale |
// | a floor of half the asked size rather than 8 | "barely moves when the scaler does", "stops at the floor", and every locale |
// | the floor read before the scaler rather than after | "stays small when the scaler asks for small" **alone**, and only through the width it asserts |
// | the reserved height dropped | "stays level" and "stays put" - not "centres a shrunken label", which passes it: a shorter column is re-centred in the row, so the label's own middle does not move and only the icon above it does |
// | the label pushed to the top of the line it kept | "centres a shrunken label" **alone** |
// | `TextOverflow.clip` in place of `ellipsis` | "stops at the floor" **alone** |
// | `TextScaler.noScaling` dropped from the `Text` | "follows the scaler up", "barely moves when the scaler does", and every locale |
// | the reserved line measured at the design size instead of the asked one | "follows the scaler up", and every locale |
//
// **One survives, and it is worth more than the eight.** `BoxFit.scaleDown`
// swapped for `BoxFit.contain` changes nothing any case can see, because the
// reserved line is exactly one line of the asked size: a label with width to
// spare has no height to grow into, so `contain` cannot scale it up either.
// The cap has two guards and no case can tell which is holding. `scaleDown`
// stays because it is the one that says so, and because it is what still
// holds if the reservation ever goes.
