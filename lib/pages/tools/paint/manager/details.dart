import '../../../../services/localization/l10n.dart';
import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';
import '../editor/widgets/editor_widgets.dart';
import 'controller.dart';

/// Height of the sheet's grab bar.
const double kSheetHandle = 16;

/// Header height: the manifest summary line.
const double kSheetHeader = 40;

/// Resting height of the sheet.
const double kSheetPeek = kSheetHandle + kSheetHeader;

/// Width of the details pane on the desktop layout.
const double kDetailsPaneWidth = 300;

String formatPaintDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}';
}

/// The facts worth showing at a glance; the rest of the animation's numbers
/// stay in the file itself.
List<(String, String)> _facts(PaintItem item) {
  final d = item.project.dolphin;
  return [
    (
      l10n.paintDetailFrameFiles,
      '${item.project.frameCount} '
          '(${d.passiveFrames}P/${d.activeFrames}A)',
    ),
    (l10n.colSize, '${d.width}×${d.height}'),
    (l10n.paintFrameRate, l10n.paintFps(d.frameRate)),
    (l10n.paintDuration, '${d.duration}'),
  ];
}

/// Desktop pane: facts and manifest settings for the selected animation, as a
/// fixed part of the screen.
class PaintDetailsPane extends StatelessWidget {
  const PaintDetailsPane({
    super.key,
    required this.item,
    required this.colors,
    required this.ctrl,
    required this.onOpen,
  });

  final PaintItem? item;
  final VoidCallback onOpen;
  final QAppColors colors;
  final ProjectManagerController ctrl;

  @override
  Widget build(BuildContext context) {
    final selected = item;
    if (selected == null) {
      return Container(
        color: colors.card,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          context.l10n.paintSelectAnimation,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textMuted, fontSize: 13),
        ),
      );
    }
    return Container(
      color: colors.card,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    selected.project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _OpenButton(colors: colors, onTap: onOpen),
              ],
            ),
            const SizedBox(height: 8),
            _FactList(facts: _facts(selected), colors: colors),
            const SizedBox(height: 10),
            ManifestSettings(item: selected, colors: colors, ctrl: ctrl),
          ],
        ),
      ),
    );
  }
}

/// Phone sheet: a grab bar that rests just under the selected animation's
/// header and pulls up to everything the pane shows on desktop.
class PaintDetailsSheet extends StatefulWidget {
  const PaintDetailsSheet({
    super.key,
    required this.item,
    required this.colors,
    required this.ctrl,
    required this.onClose,
    required this.onOpen,
  });

  final PaintItem item;
  final VoidCallback onClose;
  final VoidCallback onOpen;
  final QAppColors colors;
  final ProjectManagerController ctrl;

  @override
  State<PaintDetailsSheet> createState() => _PaintDetailsSheetState();
}

class _PaintDetailsSheetState extends State<PaintDetailsSheet> {
  final DraggableScrollableController _sheet = DraggableScrollableController();
  double _peek = 0.14;

  // DraggableScrollableSheet compares `snapSizes` by identity, so the list is
  // cached and only rebuilt when the numbers actually move — otherwise it
  // re-snaps every frame and cancels any programmatic animateTo.
  List<double> _snaps = const [];

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PaintDetailsSheet old) {
    super.didUpdateWidget(old);
    if (old.item.id == widget.item.id) return;
    // Another animation was picked: come back to the resting height. Runs after
    // this frame — the sheet swaps its extent object while rebuilding.
    WidgetsBinding.instance.addPostFrameCallback((_) => _animate(_peek));
  }

  void _animate(double size) {
    if (!mounted || !_sheet.isAttached) return;
    if ((_sheet.size - size).abs() < 0.004) return;
    _sheet.animateTo(
      size,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _toggle() {
    if (!_sheet.isAttached) return;
    _animate(_sheet.size > _peek + 0.02 ? _peek : _midSize);
  }

  double get _midSize => (_peek + 0.45).clamp(_peek, 0.9);

  void _syncSnaps(double mid, double max) {
    final next = <double>[
      _peek,
      if (mid > _peek + 0.02 && mid < max - 0.02) mid,
    ];
    if (_snaps.length == next.length) {
      var same = true;
      for (var i = 0; i < next.length; i++) {
        if (_snaps[i] != next[i]) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    _snaps = next;
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        if (height > 0) {
          _peek = ((kSheetPeek + bottomInset) / height).clamp(0.05, 0.6);
        }
        const max = 0.9;
        _syncSnaps(_midSize, max);

        return DraggableScrollableSheet(
          controller: _sheet,
          initialChildSize: _peek,
          minChildSize: _peek,
          maxChildSize: max,
          snap: true,
          snapSizes: _snaps,
          builder: (context, scrollController) => DecoratedBox(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 10),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: _SheetBody(
                  item: widget.item,
                  colors: colors,
                  ctrl: widget.ctrl,
                  scrollController: scrollController,
                  onHandleTap: _toggle,
                  onClose: widget.onClose,
                  onOpen: widget.onOpen,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.item,
    required this.colors,
    required this.ctrl,
    required this.scrollController,
    required this.onHandleTap,
    required this.onClose,
    required this.onOpen,
  });

  final PaintItem item;
  final QAppColors colors;
  final ProjectManagerController ctrl;
  final ScrollController scrollController;
  final VoidCallback onHandleTap;
  final VoidCallback onClose;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _SheetHeaderDelegate(
            extent: kSheetPeek,
            background: colors.card,
            divider: colors.divider,
            // The whole header toggles the sheet, not just the 16px grab bar —
            // the buttons inside it still take their own taps first.
            child: GestureDetector(
              onTap: onHandleTap,
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: [
                  _Handle(colors: colors),
                  // Flexible, not a fixed box: the sheet hands the header a
                  // height rounded off the viewport fraction, which can land a
                  // pixel under kSheetPeek.
                  Expanded(
                    child: _SheetSummary(
                      item: item,
                      colors: colors,
                      onClose: onClose,
                      onOpen: onOpen,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FactList(facts: _facts(item), colors: colors),
                const SizedBox(height: 10),
                ManifestSettings(item: item, colors: colors, ctrl: ctrl),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The resting line: what the row cannot show — the manifest numbers — plus a
/// way out. The preview, name and pack checkbox stay in the list row.
class _SheetSummary extends StatelessWidget {
  const _SheetSummary({
    required this.item,
    required this.colors,
    required this.onClose,
    required this.onOpen,
  });

  final PaintItem item;
  final QAppColors colors;
  final VoidCallback onClose;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final e = item.entry;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.paintManifestSummary(
                e.weight,
                e.minLevel,
                e.maxLevel,
                e.minButthurt,
                e.maxButthurt,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _OpenButton(colors: colors, onTap: onOpen),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close, size: 18, color: colors.textMuted),
            tooltip: context.l10n.commonClose,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(32),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.colors});

  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kSheetHandle,
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: colors.textMuted.withAlpha(120),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _SheetHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SheetHeaderDelegate({
    required this.extent,
    required this.background,
    required this.divider,
    required this.child,
  });

  final double extent;
  final Color background;
  final Color? divider;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      height: extent,
      decoration: BoxDecoration(
        color: background,
        border: divider == null
            ? null
            : Border(bottom: BorderSide(color: divider!)),
      ),
      child: ClipRect(child: child),
    );
  }

  @override
  bool shouldRebuild(_SheetHeaderDelegate old) =>
      old.extent != extent ||
      old.background != background ||
      old.divider != divider ||
      old.child != child;
}

/// Opens the selected animation in the editor.
class _OpenButton extends StatelessWidget {
  const _OpenButton({required this.colors, required this.onTap});

  final QAppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(Icons.edit_outlined, size: 18, color: colors.accent),
      tooltip: context.l10n.commonOpen,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(32),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// Weight and the level/butthurt ranges of one manifest entry.
class ManifestSettings extends StatelessWidget {
  const ManifestSettings({
    super.key,
    required this.item,
    required this.colors,
    required this.ctrl,
  });

  final PaintItem item;
  final QAppColors colors;
  final ProjectManagerController ctrl;

  @override
  Widget build(BuildContext context) {
    final e = item.entry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.paintAnimationSettings,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        AnimRow(
          label: context.l10n.paintWeight,
          colors: colors,
          trailing: NumberStepper(
            value: e.weight,
            min: 0,
            max: 14,
            colors: colors,
            onChange: (v) => ctrl.setWeight(item, v),
          ),
        ),
        AnimRow(
          label: context.l10n.paintMinLevel,
          colors: colors,
          trailing: NumberStepper(
            value: e.minLevel,
            min: 0,
            max: e.maxLevel,
            colors: colors,
            onChange: (v) => ctrl.setLevels(item, min: v),
          ),
        ),
        AnimRow(
          label: context.l10n.paintMaxLevel,
          colors: colors,
          trailing: NumberStepper(
            value: e.maxLevel,
            min: e.minLevel,
            max: 30,
            colors: colors,
            onChange: (v) => ctrl.setLevels(item, max: v),
          ),
        ),
        AnimRow(
          label: context.l10n.paintMinButthurt,
          colors: colors,
          trailing: NumberStepper(
            value: e.minButthurt,
            min: 0,
            max: e.maxButthurt,
            colors: colors,
            onChange: (v) => ctrl.setButthurt(item, min: v),
          ),
        ),
        AnimRow(
          label: context.l10n.paintMaxButthurt,
          colors: colors,
          trailing: NumberStepper(
            value: e.maxButthurt,
            min: e.minButthurt,
            max: 14,
            colors: colors,
            onChange: (v) => ctrl.setButthurt(item, max: v),
          ),
        ),
      ],
    );
  }
}

class _FactList extends StatelessWidget {
  const _FactList({required this.facts, required this.colors});

  final List<(String, String)> facts;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (label, value) in facts)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  value,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
