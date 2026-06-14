import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/theme.dart';

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
                      ? 'assets/ic/nav/archive-filled.svg'
                      : 'assets/ic/nav/archive.svg',
                  label: 'Archive',
                  selected: currentTab == FlipperRootTab.archive,
                  onTap: () => onTabSelected(FlipperRootTab.archive),
                ),
                _BottomTab(
                  asset: currentTab == FlipperRootTab.apps
                      ? 'assets/ic/nav/apps-filled.svg'
                      : 'assets/ic/nav/apps.svg',
                  label: 'Apps',
                  selected: currentTab == FlipperRootTab.apps,
                  onTap: () => onTabSelected(FlipperRootTab.apps),
                ),
                _BottomTab(
                  asset: currentTab == FlipperRootTab.tools
                      ? 'assets/ic/nav/tools-filled.svg'
                      : 'assets/ic/nav/tools.svg',
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
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 42,
                height: 24,
                child: applyTint
                    ? SvgPicture.asset(
                        asset,
                        colorFilter: ColorFilter.mode(
                          iconColor,
                          BlendMode.srcIn,
                        ),
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
        ),
      ),
    );
  }
}
