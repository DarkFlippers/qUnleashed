import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../components/sensitive_surface.dart';
import '../services/localization/l10n.dart';
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
    required this.deviceLabel,
    required this.railGroups,
  });

  final Widget child;
  final FlipperRootTab currentTab;
  final ValueChanged<FlipperRootTab> onTabSelected;
  final String deviceLabel;

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
              children: [
                _BottomTabSlot(
                  icon: const _NavIcon(asset: 'assets/ic/device/flipper.svg'),
                  label: deviceLabel,
                  selected: currentTab == FlipperRootTab.device,
                  onTap: () => onTabSelected(FlipperRootTab.device),
                ),
                _BottomTabSlot(
                  icon: const _NavIcon(asset: 'assets/ic/app/files.svg'),
                  label: context.l10n.navArchive,
                  selected: currentTab == FlipperRootTab.archive,
                  onTap: () => onTabSelected(FlipperRootTab.archive),
                ),
                _BottomTabSlot(
                  icon: const _NavIcon(asset: 'assets/ic/app/apps.svg'),
                  label: context.l10n.navApps,
                  selected: currentTab == FlipperRootTab.apps,
                  onTap: () => onTabSelected(FlipperRootTab.apps),
                ),
                _BottomTabSlot(
                  icon: const _NavIcon(asset: 'assets/ic/appcat/tools.svg'),
                  label: context.l10n.navTools,
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
        // Scrolls when the destinations outgrow a short window, but the bar is
        // too narrow to give a scrollbar its own lane.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
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

/// One quarter of the bottom bar. The tabs are given equal slots rather than
/// their natural widths: the device tab's label is a connection state, and a
/// long one - German's "Verbindung wird hergestellt" - used to push the bar
/// past the edge of the screen.
class _BottomTabSlot extends StatelessWidget {
  const _BottomTabSlot({
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
    return Expanded(
      child: _BottomTab(
        icon: icon,
        label: label,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}

class _BottomTab extends StatelessWidget with VisibleSurface {
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
              _TabLabel(label: label, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// A bottom-bar label, drawn at the size the bar is designed at where it
/// fits, and as near to it as the slot allows where it does not.
///
/// A slot is a quarter of the bar less the 16 of padding around the label: 74
/// on a 360 dp phone with no cutout, 64 on a 320. Cut at a fixed size in that
/// box, the device states stop telling each other apart. `deviceStateSyncing`
/// and `deviceStateSynced` share nine to thirteen leading characters in seven
/// of the eight locales, so an ellipsis that eats the tail leaves the same
/// word on screen for "a sync is running" and "the sync has finished" and the
/// bar reads as if nothing happened; `deviceStateConnecting` and
/// `deviceStateConnected` share six or seven in all eight, English included.
/// #425
///
/// **Measured off Roboto Bold's own advance widths** plus the quarter of
/// letter spacing Material charges per glyph, and **nothing in this
/// repository re-derives the numbers below** - the test font cannot stand in
/// for either, since every glyph of that one is a square of the font size,
/// about twice a real one. They are reproduced in the PR for #425; what the
/// suite holds is the weaker claim that survives any font, which
/// `test/nav_bar_label_fit_test.dart` states.
///
/// At 10 dp "Синхронизирован" is 88.2 and "Синхронизация" 76.7, so that pair
/// collides in three locales on a 320 dp phone at the default font size -
/// Russian, Belarusian and German - and the scaler takes the rest: at 360 dp
/// none at 1.0, three at 1.15, six at the 1.3 Android calls "large", all eight
/// by 2.5. Over the eight states, their 28 pairs, four phone widths and seven
/// scalers, 20 pairs collided somewhere. Measured again with the fit in place:
/// none does.
///
/// ## The floor is a trade, and it is this label's, not the user's
///
/// The label shrinks no further than [_minFontSize], and under that it is cut
/// after all. German's `deviceStateConnecting` ("Verbindung wird hergestellt")
/// is 131.4 dp and fits no phone at any size worth reading, which is why the
/// slots are equal in the first place - see [_BottomTabSlot]. At the floor it
/// shows 16 of its 27 characters on a 360 dp phone where the clip showed 12,
/// and it is the only state in any locale that is cut at all above the 320 dp
/// end, so there is nothing for it to be read as. That last part is a property
/// of the eight translations rather than of this widget, which is why the
/// per-locale group in the test file checks it rather than this doc claiming
/// it.
///
/// The cost is that **a raised text-size setting buys this one label almost
/// nothing**: it is already as large as the slot allows, so what the setting
/// raises is the size it is measured against, not the size it is drawn at.
/// That is the trade #425 chose - "let the text be as small as it must be
/// rather than clipped" - and it is the right way round only because the
/// alternative is a word that cannot be told from another word. The layout
/// that would honour both is a different change: a named device tab with the
/// state on its icon, or a second line above some scaler. #429.
///
/// ## No arithmetic in the fit
///
/// `FittedBox` lays its child out unconstrained and scales it down into the
/// slot, which is the fit. `scaleDown` never scales *up*, which is the cap at
/// the asked size - and so is the reserved line, since a box one line of
/// [asked] tall leaves a label with width to spare no height to grow into
/// either; the two say the same thing and the mutation note in the test file
/// records that neither alone is observable. The cap on the child's own width
/// is the floor, because a child at most `asked / floor` times the slot cannot
/// be scaled by less than `floor / asked`. Past that the paragraph ellipsises
/// at the asked size, which leaves the same glyphs on screen as laying it out
/// at the floor would.
///
/// An earlier draft of this did the same thing by measuring the label with two
/// `TextPainter` probes and solving for the size that fits. It worked, and
/// every defect it could have had was in the model rather than the layout:
/// letter spacing is charged per glyph and does not scale with the size, so
/// one probe gives a ratio that is wide by exactly that; `Text` merges
/// `FontWeight.bold` over its style under the system bold-text setting, so the
/// probe had to say `w700` and not `bold`; a `MediaQuery` letter- or
/// word-spacing override is applied to the span rather than the style, so the
/// probe could not see it at all; and a platform that rounds advances to whole
/// pixels breaks the linearity the two probes assume. A `FittedBox` measures
/// the paragraph the tree actually laid out, so none of those is reachable.
class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.label, required this.color});

  final String label;
  final Color color;

  /// The size the bar is designed at, and the most that will be drawn.
  static const double _fontSize = 10;

  /// The least that will be drawn. A state nobody can read is no better than
  /// a state nobody can tell apart, so the shrinking stops here and the
  /// ellipsis comes back.
  static const double _minFontSize = 8;

  @override
  Widget build(BuildContext context) {
    final asked = MediaQuery.textScalerOf(context).scale(_fontSize);
    // A scaler below the floor is the one case where the floor is not one:
    // a size nobody asked for is not an improvement on a cut.
    final floor = math.min(_minFontSize, asked);
    // The style the `Text` below will draw with, rather than the one passed
    // to it: `Material` puts `textTheme.bodyMedium` in front of its child as
    // the `DefaultTextStyle`, and that is where the line height the box is
    // reserved at comes from. Merged here so that the two cannot disagree -
    // `bodyMedium` is `inherit: false` and `merge` keeps that, so the `Text`
    // takes this verbatim.
    final style = DefaultTextStyle.of(context).style.merge(
      TextStyle(fontSize: asked, fontWeight: FontWeight.w700, color: color),
    );
    final probe = TextPainter(
      text: TextSpan(text: label, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: TextScaler.noScaling,
    )..layout();
    final line = probe.height;
    probe.dispose();
    // The height [asked] would have taken, so the row of icons stays level and
    // stays put while a shrinking label changes under it. It is also what
    // keeps `scaleDown` off the height: `RenderFittedBox` sizes itself by
    // `constrainSizeAndAttemptToPreserveAspectRatio`, so with a tight box the
    // fitted label is centred in a line of the full height instead of
    // dragging the line down with it.
    return SizedBox(
      height: line,
      child: LayoutBuilder(
        builder: (context, constraints) => FittedBox(
          fit: BoxFit.scaleDown,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * asked / floor,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              // The scaler is already in [asked], and in the size this is
              // scaled down from; applying it again would square it.
              textScaler: TextScaler.noScaling,
              style: style,
            ),
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
