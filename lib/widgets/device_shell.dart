import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

enum FlipperRootTab { device, archive, apps, tools }

class FlipperRootScaffold extends StatelessWidget {
  const FlipperRootScaffold({
    super.key,
    required this.child,
    required this.currentTab,
    required this.onTabSelected,
    required this.deviceIconAsset,
    required this.deviceLabel,
  });

  final Widget child;
  final FlipperRootTab currentTab;
  final ValueChanged<FlipperRootTab> onTabSelected;
  final String deviceIconAsset;
  final String deviceLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      body: child,
      bottomNavigationBar: Container(
        color: colors.card,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _BottomTab(
                  asset: deviceIconAsset,
                  label: deviceLabel,
                  selected: currentTab == FlipperRootTab.device,
                  applyTint: false,
                  onTap: () => onTabSelected(FlipperRootTab.device),
                ),
                _BottomTab(
                  asset: currentTab == FlipperRootTab.archive
                      ? 'assets/flipper_svg/bottombar/ic_archive_filled.svg'
                      : 'assets/flipper_svg/bottombar/ic_archive.svg',
                  label: 'Archive',
                  selected: currentTab == FlipperRootTab.archive,
                  onTap: () => onTabSelected(FlipperRootTab.archive),
                ),
                _BottomTab(
                  asset: currentTab == FlipperRootTab.apps
                      ? 'assets/flipper_svg/bottombar/ic_tab_apps_filled.svg'
                      : 'assets/flipper_svg/bottombar/ic_tab_apps.svg',
                  label: 'Apps',
                  selected: currentTab == FlipperRootTab.apps,
                  onTap: () => onTabSelected(FlipperRootTab.apps),
                ),
                _BottomTab(
                  asset: currentTab == FlipperRootTab.tools
                      ? 'assets/flipper_svg/bottombar/ic_tools_filled.svg'
                      : 'assets/flipper_svg/bottombar/ic_tools.svg',
                  label: 'Tools',
                  selected: currentTab == FlipperRootTab.tools,
                  onTap: () => onTabSelected(FlipperRootTab.tools),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomTab extends StatelessWidget {
  const _BottomTab({
    required this.asset,
    required this.label,
    required this.selected,
    this.applyTint = true,
    required this.onTap,
  });

  final String asset;
  final String label;
  final bool selected;
  final bool applyTint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = selected ? colors.textPrimary : colors.textMuted;
    final iconColor = colors.textMuted;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 42,
            height: 24,
            child: applyTint
                ? SvgPicture.asset(
                    asset,
                    colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                  )
                : SvgPicture.asset(asset),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class FlipperPageCard extends StatelessWidget {
  const FlipperPageCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class FlipperMockupWidget extends StatelessWidget {
  const FlipperMockupWidget({
    super.key,
    required this.active,
  });

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AspectRatio(
      aspectRatio: 238 / 100,
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
                        ? 'assets/flipper_svg/mockup/template_black_flipper_active.svg'
                        : 'assets/flipper_svg/mockup/template_black_flipper_disabled.svg')
                    : (active
                        ? 'assets/flipper_svg/mockup/template_white_flipper_active.svg'
                        : 'assets/flipper_svg/mockup/template_white_flipper_disabled.svg'),
              ),
              Positioned(
                left: w * (60.56 / 238),
                top: h * (10.54 / 100),
                width: w * (85.33 / 238),
                height: h * (46.96 / 100),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(w * (3.4 / 238)),
                  child: const RepaintBoundary(
                    child: _MockupInnerScreen(),
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

class _MockupInnerScreen extends StatelessWidget {
  const _MockupInnerScreen();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/flipper_svg/mockup/pic_flipperscreen_default.svg',
      fit: BoxFit.fill,
    );
  }
}

class FlipperActionRow extends StatelessWidget {
  const FlipperActionRow({
    super.key,
    required this.iconAsset,
    required this.label,
    required this.color,
    required this.onTap,
    this.trailing,
  });

  final String iconAsset;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: SizedBox(
            width: 24,
            height: 24,
            child: SvgPicture.asset(iconAsset, colorFilter: ColorFilter.mode(color, BlendMode.srcIn)),
          ),
        ),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

class FlipperInfoLine extends StatelessWidget {
  const FlipperInfoLine({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: colors.textMuted,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 14,
                color: valueColor ?? colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
