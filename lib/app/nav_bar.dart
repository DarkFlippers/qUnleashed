import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../components/sensitive_surface.dart';
import '../services/localization/l10n.dart';
import '../theme/theme.dart';

enum FlipperRootTab { device, archive, apps, tools }

/// What the device tab's icon says about the link, in constant space.
///
/// Four classes over the eight states `_AppShellState._deviceLabel` spells,
/// and deliberately coarser than those: a dot cannot carry eight meanings,
/// and the eight are still announced in full through the tab's semantics
/// label and shown as words on the device screen itself.
///
/// The tab used to carry the state *as its label*, which is why this exists.
/// A status is a sentence in several locales - German's `deviceStateConnecting`
/// is "Verbindung wird hergestellt", 131 dp of it - so the label was drawn
/// shrunk to whatever a quarter of the bar allowed, and a raised text-size
/// setting then bought that one label almost nothing: it raised the size the
/// label was *measured* at, not the size it was *drawn* at. The three ways
/// out were weighed in #429; this is the one that makes the slot's width stop
/// mattering, because a noun fits at any scaler.
enum DeviceTabStatus {
  /// No Flipper, or one that is not connected.
  absent,

  /// Connecting, recovering, or collecting what it needs after arriving.
  working,

  /// Connected, with nothing outstanding.
  ready,

  /// In DFU. Not an error, but not a Flipper the app can talk to either.
  attention,
}

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
    required this.deviceStatus,
    required this.railGroups,
  });

  final Widget child;
  final FlipperRootTab currentTab;
  final ValueChanged<FlipperRootTab> onTabSelected;

  /// The link state as a sentence. No longer the device tab's label - it is
  /// what the tab *announces*, which is where the eight states survive now
  /// that the visible label is a noun. See [DeviceTabStatus].
  final String deviceLabel;

  /// The same state as the dot on the tab's icon.
  final DeviceTabStatus deviceStatus;

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
                  icon: _DeviceNavIcon(status: deviceStatus),
                  label: context.l10n.navDevice,
                  announce: deviceLabel,
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
    this.announce,
  });

  final Widget icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Said after [label] instead of [label] alone, for a tab whose icon
  /// carries something the label does not. Only the device tab does.
  final String? announce;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _BottomTab(
        icon: icon,
        label: label,
        announce: announce,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}

/// [child] announced as "[label], [announcement]" rather than as [label].
///
/// The dot on the device tab's icon is the only thing in the bar that carries
/// meaning no label spells, so it is the only tab that passes an
/// announcement. [ExcludeSemantics] because the label is inside [child] and
/// would otherwise be read twice.
Widget _announced(String? announcement, String label, Widget child) {
  if (announcement == null) return child;
  return Semantics(
    container: true,
    label: '$label, $announcement',
    child: ExcludeSemantics(child: child),
  );
}

class _BottomTab extends StatelessWidget with VisibleSurface {
  const _BottomTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.announce,
  });

  final Widget icon;
  final String label;
  final String? announce;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = selected ? colors.textPrimary : colors.textMuted;
    final announcement = announce;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: _announced(
            announcement,
            label,
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 42, height: 24, child: icon),
                const SizedBox(height: 4),
                TabLabel(label: label, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bottom-bar label, drawn at the size the bar is designed at where it
/// fits, and as near to it as the slot allows where it does not.
///
/// Public for `test/nav_bar_label_fit_test.dart` alone, which is where the
/// contract below is pinned. It was private while the device tab's label was
/// a *status*, because that made every tab's label an arbitrary string the
/// bar's own API accepted and so gave the fit cases a vehicle. #429 made that
/// label a noun from the ARB like the other three, and with it the bar has no
/// way left to be handed a long label - which is the point of #429 and would
/// have left the fit untestable. Exposing the label is the smaller price, and
/// the better test: the contract is this widget's, not the shell's.
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
@visibleForTesting
class TabLabel extends StatelessWidget {
  const TabLabel({required this.label, required this.color});

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

/// The dot [_DeviceNavIcon] draws, so a test can read its colour.
///
/// A key rather than a semantics value: what the dot says is already
/// announced as the tab's label (see `_announced`), and a second
/// announcement for the same fact would be read out twice.
@visibleForTesting
const Key deviceStatusDotKey = ValueKey('deviceStatusDot');

/// The device tab's icon with the link state as a dot on its corner.
///
/// Drawn in the icon's own 42x24 box rather than beside it, so the state
/// costs no width at any text size - which is the whole point of #429.
class _DeviceNavIcon extends StatelessWidget {
  const _DeviceNavIcon({required this.status});

  final DeviceTabStatus status;

  /// The dot's diameter, and the ring around it. The ring is the card colour
  /// so the dot reads as separate from the icon's own strokes rather than as
  /// part of the drawing.
  static const double _dot = 8;
  static const double _ring = 2;

  Color _color(QAppColors colors) => switch (status) {
    DeviceTabStatus.absent => colors.textMuted,
    DeviceTabStatus.working => colors.info,
    DeviceTabStatus.ready => colors.success,
    DeviceTabStatus.attention => colors.danger,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned.fill(
          child: _NavIcon(asset: 'assets/ic/device/flipper.svg'),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            width: _dot + _ring * 2,
            height: _dot + _ring * 2,
            decoration: BoxDecoration(
              color: colors.card,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                key: deviceStatusDotKey,
                width: _dot,
                height: _dot,
                decoration: BoxDecoration(
                  color: _color(colors),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ],
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
