import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme/theme.dart';
import '../models/device_info.dart';

class FlipperMockupWidget extends StatelessWidget {
  const FlipperMockupWidget({super.key, required this.active});

  static const _templateWidth = 238.0;
  static const _templateHeight = 100.0;
  static const _screenLeft = 60.65;
  static const _screenTop = 10.54;
  static const _screenWidth = 85.32;
  static const _screenHeight = 46.95;

  final bool active;

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
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: w,
                      maxWidth: w,
                      minHeight: h,
                      maxHeight: h,
                      child: Transform.translate(
                        offset: Offset(
                          -w * (_screenLeft / _templateWidth),
                          -h * (_screenTop / _templateHeight),
                        ),
                        child: SizedBox(
                          width: w,
                          height: h,
                          child: const _MockupInnerScreen(),
                        ),
                      ),
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
  });

  final bool active;
  final String title;
  final List<MapEntry<String, String>> infoEntries;
  final Map<String, String> deviceInfo;
  final String connectionLabel;
  final IconData connectionIcon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final firmwareVersion =
        DeviceInfoReader.str(deviceInfo, const [
          'firmware_version',
          'firmware.version',
          'software_revision',
        ]) ??
        _entryValue(infoEntries, 'Firmware Version');
    final buildDate =
        DeviceInfoReader.str(deviceInfo, const [
          'firmware_build_date',
          'firmware.build.date',
          'build_date',
        ]) ??
        _entryValue(infoEntries, 'Build Date');
    final uid = DeviceInfoReader.str(deviceInfo, const [
      'hardware_uid',
      'hardware.uid',
      'uid',
    ]);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(height: 100, child: FlipperMockupWidget(active: active)),
        const SizedBox(width: 24),
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
                    _HeroMetaText('fw $firmwareVersion'),
                  if (buildDate != null) _HeroMetaText('built $buildDate'),
                ],
              ),
              if (uid != null) ...[
                const SizedBox(height: 6),
                Text(
                  'UID $uid',
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

class _MockupInnerScreen extends StatelessWidget {
  const _MockupInnerScreen();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/pic/device/screen/default.svg',
      fit: BoxFit.fill,
    );
  }
}
