import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/theme.dart';

enum FlipperRootTab { device, archive, apps, tools }

/// One icon-only destination of the desktop side rail. [color] tints both the
/// icon and the selected pill behind it.
class FlipperRailItem {
  const FlipperRailItem({
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Widget icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
}

/// Root chrome around the tab bodies. A window wider than it is tall gets the
/// desktop side rail (icons only, no labels); anything else keeps the mobile
/// bottom bar with its four labelled tabs.
class FlipperRootScaffold extends StatelessWidget {
  const FlipperRootScaffold({
    super.key,
    required this.child,
    required this.currentTab,
    required this.onTabSelected,
    required this.deviceIconAsset,
    required this.deviceLabel,
    required this.deviceSyncing,
    required this.railGroups,
  });

  final Widget child;
  final FlipperRootTab currentTab;
  final ValueChanged<FlipperRootTab> onTabSelected;
  final String deviceIconAsset;
  final String deviceLabel;
  final bool deviceSyncing;

  /// Rail destinations, split into groups drawn with a divider between them.
  final List<List<FlipperRailItem>> railGroups;

  static bool isWide(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (isWide(context)) {
      return Scaffold(
        backgroundColor: colors.background,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SideRail(groups: railGroups),
            Expanded(child: child),
          ],
        ),
      );
    }
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
                  icon: DeviceStatusIcon(
                    asset: deviceIconAsset,
                    syncing: deviceSyncing,
                  ),
                  label: deviceLabel,
                  selected: currentTab == FlipperRootTab.device,
                  onTap: () => onTabSelected(FlipperRootTab.device),
                ),
                _BottomTab(
                  icon: _NavIcon(
                    asset: currentTab == FlipperRootTab.archive
                        ? 'assets/ic/nav/archive-filled.svg'
                        : 'assets/ic/nav/archive.svg',
                  ),
                  label: 'Archive',
                  selected: currentTab == FlipperRootTab.archive,
                  onTap: () => onTabSelected(FlipperRootTab.archive),
                ),
                _BottomTab(
                  icon: _NavIcon(
                    asset: currentTab == FlipperRootTab.apps
                        ? 'assets/ic/nav/apps-filled.svg'
                        : 'assets/ic/nav/apps.svg',
                  ),
                  label: 'Apps',
                  selected: currentTab == FlipperRootTab.apps,
                  onTap: () => onTabSelected(FlipperRootTab.apps),
                ),
                _BottomTab(
                  icon: _NavIcon(
                    asset: currentTab == FlipperRootTab.tools
                        ? 'assets/ic/nav/tools-filled.svg'
                        : 'assets/ic/nav/tools.svg',
                  ),
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

class _SideRail extends StatelessWidget {
  const _SideRail({required this.groups});

  final List<List<FlipperRailItem>> groups;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: 58,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(right: BorderSide(color: colors.divider)),
      ),
      child: SafeArea(
        right: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              for (var g = 0; g < groups.length; g++) ...[
                if (g > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Divider(height: 1, color: colors.divider),
                  ),
                for (final item in groups[g]) _RailButton(item: item),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.item});

  final FlipperRailItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Material(
        color: item.selected
            ? item.color.withValues(alpha: colors.isDark ? 0.20 : 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: item.onTap,
          child: SizedBox(
            width: 44,
            height: 40,
            child: Center(child: item.icon),
          ),
        ),
      ),
    );
  }
}

/// Rail icon drawn from an SVG asset in a single flat [color].
class FlipperRailIcon extends StatelessWidget {
  const FlipperRailIcon({
    super.key,
    required this.asset,
    required this.color,
    this.size = 22,
  });

  final String asset;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

class _BottomTab extends StatelessWidget {
  const _BottomTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = selected ? colors.textPrimary : colors.textMuted;
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
              SizedBox(width: 42, height: 24, child: icon),
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

class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      colorFilter: ColorFilter.mode(
        context.appColors.textMuted,
        BlendMode.srcIn,
      ),
    );
  }
}

/// Device tab status badge. Renders [asset] with its own colours; while
/// [syncing] the badge stays put and the sync arrows spin over it.
class DeviceStatusIcon extends StatefulWidget {
  const DeviceStatusIcon({
    super.key,
    required this.asset,
    required this.syncing,
  });

  final String asset;
  final bool syncing;

  @override
  State<DeviceStatusIcon> createState() => _DeviceStatusIconState();
}

class _DeviceStatusIconState extends State<DeviceStatusIcon>
    with SingleTickerProviderStateMixin {
  static const _arrowsAsset = 'assets/ic/connect/sync-arrows.svg';
  // Arrow group's visual centre inside the 42×24 viewBox, so it spins in place.
  static const _pivot = Alignment(0.03, -0.09);

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.syncing) _spin.repeat();
  }

  @override
  void didUpdateWidget(DeviceStatusIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.syncing == oldWidget.syncing) return;
    if (widget.syncing) {
      _spin.repeat();
    } else {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.syncing) return SvgPicture.asset(widget.asset);
    return Stack(
      alignment: Alignment.center,
      children: [
        SvgPicture.asset(widget.asset),
        RotationTransition(
          turns: _spin,
          alignment: _pivot,
          child: SvgPicture.asset(_arrowsAsset),
        ),
      ],
    );
  }
}
