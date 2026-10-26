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
            return Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: FlipperMockupHero(
                      active: active,
                      dfu: dfu,
                      title: title,
                      infoEntries: infoEntries,
                      deviceInfo: deviceInfo,
                      connectionLabel: connectionLabel,
                      connectionIcon: connectionIcon,
                    ),
                  ),
                ),
                if (onOpenFullInfo != null)
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: TextButton.icon(
                      onPressed: onOpenFullInfo,
                      icon: const Icon(Icons.info_outline, size: 16),
                      label: Text(context.l10n.deviceFullInfo),
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
