import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../services/localization/l10n.dart';
import '../../../components/flipper_screen_animation.dart';
import '../../../theme/theme.dart';
import '../models/device_info.dart';

class FlipperMockupWidget extends StatelessWidget {
  const FlipperMockupWidget({
    super.key,
    required this.active,
    this.dfu = false,
  });

  static const _templateWidth = 238.0;
  static const _templateHeight = 100.0;
  static const _screenLeft = 60.65;
  static const _screenTop = 10.54;
  static const _screenWidth = 85.32;
  static const _screenHeight = 46.95;

  final bool active;

  final bool dfu;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AspectRatio(
      aspectRatio: _templateWidth / _templateHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(
            fit: StackFit.expand,
            children: [
              SvgPicture.asset(
                colors.isDark
                    ? (active
                          ? 'assets/pic/device/body/black-active.svg'
                          : 'assets/pic/device/body/black-disabled.svg')
                    : (active
                          ? 'assets/pic/device/body/white-active.svg'
                          : 'assets/pic/device/body/white-disabled.svg'),
              ),
              Positioned(
                left: w * (_screenLeft / _templateWidth),
                top: h * (_screenTop / _templateHeight),
                width: w * (_screenWidth / _templateWidth),
                height: h * (_screenHeight / _templateHeight),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(w * (3.4 / 238)),
                  child: RepaintBoundary(
                    child: dfu
                        ? const _MockupRecoveryScreen()
                        : const FlipperScreenAnimation(
                            active: true,
                            fg: Color(0xFF000000),
                            bg: Color(0xFFFF8200),
                            deadZonePx: 2,
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class FlipperMockupHero extends StatelessWidget {
  const FlipperMockupHero({
    super.key,
    required this.active,
    required this.title,
    required this.infoEntries,
    required this.deviceInfo,
    required this.connectionLabel,
    required this.connectionIcon,
    this.dfu = false,
  });

  final bool active;
  final bool dfu;
  final String title;
  final List<MapEntry<String, String>> infoEntries;
  final Map<String, String> deviceInfo;
  final String connectionLabel;
  final IconData connectionIcon;

  /// The gap between the mockup and the text column, spelt once.
  static const _mockupGap = 24.0;

  /// The least this can be given without overflowing, at [scaler].
  ///
  /// The mockup is a fixed [FlipperMockupWidget._templateWidth] - a
  /// `SizedBox(height: 100)` over a 238:100 `AspectRatio`, so nothing shrinks
  /// it - plus [_mockupGap] and [titleRowFloor].
  ///
  /// **Not a readable width.** It is the width below which this throws, which
  /// is a different question from the width at which it reads. Above it
  /// everything here ellipsises or wraps instead; `DevicePageHeader` works
  /// from both numbers and they are not interchangeable. #417.
  static double minWidth(TextScaler scaler) =>
      FlipperMockupWidget._templateWidth + _mockupGap + titleRowFloor(scaler);

  /// The least the title row can be given without overflowing, at [scaler].
  ///
  /// That row is `Flexible(title)`, a 10 gap and [_HeroPill], and the pill is
  /// the half that cannot shrink. Written out, with the gap first:
  /// `10 + 2 (border) + 16 (padding) + 12 (icon) + 5 (gap) + 1.5 (letter
  /// spacing, charged for the trailing glyph too) = 46.5`, plus three glyphs
  /// of a 10 px font - `connectionLabel` is `BLE` or `USB` and never
  /// translated (`pages/devices/page.dart`). The 52 is that 46.5 with 5.5
  /// against rounding.
  ///
  /// Taking a glyph as wide as its font size is what `flutter_test`'s font
  /// does and about twice what a proportional one does, so this over-reserves
  /// rather than under - which is the direction a floor should err in.
  ///
  /// [TextScaler.scale] on a **font size** is what it is defined for, unlike
  /// the box-height guess #411 threw out. The pill's icon is 12 at every
  /// scale only because `Icon.applyTextScaling` defaults to false and the
  /// theme sets no `iconTheme`; if that ever changes, this is where it has to
  /// be paid for.
  static double titleRowFloor(TextScaler scaler) => 52 + 3 * scaler.scale(10);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final firmwareVersion =
        DeviceInfoReader.str(deviceInfo, const [
          'firmware_version',
          'firmware.version',
          'software_revision',
        ]) ??
        _entryValue(infoEntries, context.l10n.infoFirmwareVersion);
    final buildDate =
        DeviceInfoReader.str(deviceInfo, const [
          'firmware_build_date',
          'firmware.build.date',
          'build_date',
        ]) ??
        _entryValue(infoEntries, context.l10n.infoBuildDate);
    final uid = DeviceInfoReader.str(deviceInfo, const [
      'hardware_uid',
      'hardware.uid',
      'uid',
    ]);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 100,
          child: FlipperMockupWidget(active: active, dfu: dfu),
        ),
        const SizedBox(width: _mockupGap),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onAccent,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _HeroPill(icon: connectionIcon, label: connectionLabel),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 2,
                children: [
                  if (firmwareVersion != null)
                    _HeroMetaText(
                      context.l10n.deviceHeroFirmware(firmwareVersion),
                    ),
                  if (buildDate != null)
                    _HeroMetaText(context.l10n.deviceHeroBuilt(buildDate)),
                ],
              ),
              if (uid != null) ...[
                const SizedBox(height: 6),
                Text(
                  context.l10n.deviceHeroUid(uid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onAccent.withValues(alpha: .72),
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.onAccent.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.onAccent.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.onAccent),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: colors.onAccent,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetaText extends StatelessWidget {
  const _HeroMetaText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Text(
      text,
      style: TextStyle(
        color: colors.onAccent.withValues(alpha: .78),
        fontSize: 12,
      ),
    );
  }
}

String? _entryValue(List<MapEntry<String, String>> entries, String key) {
  for (final entry in entries) {
    if (entry.key == key &&
        entry.value.trim().isNotEmpty &&
        entry.value != '-') {
      return entry.value;
    }
  }
  return null;
}

class _MockupRecoveryScreen extends StatelessWidget {
  const _MockupRecoveryScreen();

  static const _screenColor = Color(0xFFFF8200);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _screenColor,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: SvgPicture.asset(
          'assets/pic/device/screen/recovery.svg',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
