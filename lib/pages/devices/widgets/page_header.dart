import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/localization/l10n.dart';
import '../../../theme/theme.dart';
import 'flipper_mockup.dart';

class DevicePageHeader extends StatelessWidget {
  const DevicePageHeader({
    super.key,
    required this.topInset,
    required this.title,
    required this.subtitle,
    required this.active,
    this.dfu = false,
    this.infoEntries = const [],
    this.deviceInfo = const {},
    this.connectionLabel = 'USB',
    this.connectionIcon = Icons.usb,
    this.onOpenFullInfo,
  });

  final double topInset;
  final String title;
  final String subtitle;
  final bool active;
  final bool dfu;
  final List<MapEntry<String, String>> infoEntries;
  final Map<String, String> deviceInfo;
  final String connectionLabel;
  final IconData connectionIcon;
  final VoidCallback? onOpenFullInfo;

  /// The inset the button hangs off the header's corner by, spelt once.
  ///
  /// Not the 14 a side inside the button's own style, which is part of how
  /// wide the button is rather than where it sits.
  static const _buttonInset = 14.0;

  /// The hero's own horizontal padding, which the button is outside of.
  static const _heroInset = 18.0;

  /// What the header keeps for the hero before the button may have anything,
  /// when the two are side by side.
  ///
  /// [FlipperMockupHero.minWidth] plus the two insets between it and the
  /// header's right edge. **Not a readable width** - the hero's own doc for
  /// that term is the one that defines it, and [_sideBySideWidth] is the
  /// number for the other question.
  static double _heroFloor(TextScaler scaler) =>
      _buttonInset + 2 * _heroInset + FlipperMockupHero.minWidth(scaler);

  /// Where the button stops being drawn beside the hero and goes under it.
  ///
  /// **A choice between two safe layouts, not a safety bound** - which is why
  /// a real-font estimate can set it. Below this there is no arrangement
  /// where all three fit: in the shipped font at 560 the mockup takes 238 of
  /// the width, a whole UID line about 210 and the longest `deviceFullInfo`
  /// about 185, which is 633 of a 560 header before any padding. Something
  /// has to give, and giving the button a line of its own costs 50 of height
  /// where the alternative costs most of the UID - about eleven of its
  /// thirty-two characters, measured.
  ///
  /// 720 is those three plus the insets, rounded up. An iPad in portrait is
  /// 768 and a desktop window wider still, so the common wide layouts are
  /// unchanged; what this catches is the 560-720 band, which on a phone is
  /// landscape and on a desktop is a dragged window. #417.
  static const _sideBySideWidth = 720.0;

  /// **No height of its own.** This sizes to its content, which is the whole
  /// of why it cannot overflow: the narrow row is as tall as the mockup's 114
  /// or as its text, whichever is more, and the hero as tall as its metadata.
  ///
  /// It used to be a `Positioned` over the page's list with a height the page
  /// computed - the mockup's 7+100+7 and nothing for the text - so a wrapped
  /// title or a `Wrap` of metadata that took one line more than the number
  /// allowed for simply spilled out of it. `Flex.clipBehavior` is `Clip.none`,
  /// so release painted the surplus over the list below rather than clipping
  /// it, and reported nothing. The page is a `Column` now and nobody promises
  /// this a height. #411.
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      color: colors.accent,
      padding: EdgeInsets.only(top: topInset),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 560;
          if (wide && infoEntries.isNotEmpty) {
            // **The button is in the layout now, not over it.**
            //
            // The hero's text column is `Expanded`
            // (`widgets/flipper_mockup.dart`), so it ran the full width of
            // the header - under a `Positioned` button painted after it. A
            // `Stack` constrains no sibling of a `Positioned` child, so there
            // was no overflow to report: the two simply painted on top of
            // each other, and the UID line lost its tail under the button at
            // every width this layout is drawn at. #417.
            //
            // Beside the hero while all three of them fit, and under it when
            // they do not - [_sideBySideWidth] has that arithmetic, and the
            // reason the band below it cannot be solved by sharing the row
            // out differently.
            final hero = Padding(
              padding: const EdgeInsets.symmetric(horizontal: _heroInset),
              child: FlipperMockupHero(
                active: active,
                dfu: dfu,
                title: title,
                infoEntries: infoEntries,
                deviceInfo: deviceInfo,
                connectionLabel: connectionLabel,
                connectionIcon: connectionIcon,
              ),
            );
            if (onOpenFullInfo == null) return hero;
            // The insets the `Positioned` carried, so the button sits where
            // it did in either layout: 14 off a box as tall as its content is
            // the same place as `bottom: 14` off a stack that was.
            final button = Padding(
              padding: const EdgeInsets.only(
                right: _buttonInset,
                bottom: _buttonInset,
              ),
              child: TextButton.icon(
                onPressed: onOpenFullInfo,
                icon: const Icon(Icons.info_outline, size: 16),
                // Bounded both ways: `TextButton.icon` puts the label in a
                // `Flexible`, so this ellipsises inside the button rather
                // than overflowing it - which is what it does when the row
                // leaves it less than it wants, and when a text scale makes
                // it wider than the whole header.
                label: Text(
                  context.l10n.deviceFullInfo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: colors.onAccent,
                  fixedSize: const Size.fromHeight(36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: colors.onAccent.withValues(alpha: .28),
                    ),
                  ),
                ),
              ),
            );
            if (constraints.maxWidth < _sideBySideWidth) {
              // Nothing can overlap down here by construction, and the hero
              // keeps the whole width - which is the point: this band is the
              // one where the UID needs all of it.
              return Column(
                children: [
                  hero,
                  Align(alignment: Alignment.centerRight, child: button),
                ],
              );
            }
            // `end`, and the default is `center` rather than `start`: without
            // this the button sits half way up the header instead of 14 off
            // its bottom.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: hero),
                // **The cap is what keeps the mockup alive.** The button
                // takes its own width or this, whichever is less; unbounded,
                // it would starve the mockup, which cannot shrink, and *that*
                // overflow does throw. A text scale of 2 is enough: the
                // longest label alone is then wider than 720 leaves.
                //
                // What yields instead is the hero's text, down to - never
                // below - its floor, and then the button's label.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(
                      0,
                      constraints.maxWidth -
                          _heroFloor(MediaQuery.textScalerOf(context)),
                    ),
                  ),
                  child: button,
                ),
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 18, bottom: 7),
                child: SizedBox(
                  height: 100,
                  child: FlipperMockupWidget(active: active, dfu: dfu),
                ),
              ),
              // **`Flexible`, and both texts bounded.** The mockup is a
              // fixed 238 wide - 100 tall at the template's 238:100 - so on
              // a 360 dp phone it and its padding take 256 of the width and
              // leave 104 for the name. Without a flex factor the column
              // asked for its intrinsic width anyway and the row asked for
              // more than it had.
              //
              // Debug paints that as stripes and throws. Release reports
              // nothing and does not clip either, because
              // `Flex.clipBehavior` is `Clip.none` - the text is painted
              // past the row's edge and cut off at the window's instead,
              // which is the same missing tail by a different hand.
              //
              // Who hits it: the disconnected title is
              // `deviceStateNoDevice`, about 75 of those 104 pixels in a
              // proportional font, so English fitted a 360 dp phone and
              // clipped a 320 one - while "Sin dispositivo" and the other
              // six translations are half again as long and clipped at 360
              // too. A connected name is `hardware_name` verbatim: the
              // firmware caps it at 8 characters
              // (`FURI_HAL_VERSION_NAME_LENGTH`) but nothing here does, and
              // eight wide glyphs are already past 104. #411.
              //
              // Loose fit, so nothing moves while the text fits: the column
              // still takes its intrinsic width and the row still centres
              // the pair. Only the overflow case is different, and it
              // ellipsises now - the title over two lines first, which is
              // what a translation of two words wants.
              //
              // Two lines need the room, which is what took the page's fixed
              // header height with it: see the note on `build` above.
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.onAccent,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // No `textAlign` on this one, unlike the title: it is
                    // one line, so it is either narrower than its box - in
                    // which case the box is its own width and alignment is
                    // unobservable - or ellipsised and filling it.
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colors.onAccent),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
