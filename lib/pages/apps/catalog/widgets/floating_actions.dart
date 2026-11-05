import 'package:flutter/material.dart';

import '../../../../components/icon.dart';
import '../../../../services/guarded.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';

/// Scroll controls share one corner: the builder yields its place to the
/// return-to-top action without moving or rebuilding the catalog itself.
class CatalogFloatingActions extends StatefulWidget {
  const CatalogFloatingActions({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onOpenBuilder,
  });

  final ScrollController controller;
  final bool enabled;
  final VoidCallback? onOpenBuilder;

  @override
  State<CatalogFloatingActions> createState() => _CatalogFloatingActionsState();
}

class _CatalogFloatingActionsState extends State<CatalogFloatingActions> {
  static const _transition = Duration(milliseconds: 240);
  static const _curve = Curves.easeInOutCubic;
  bool _showTop = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    _syncAfterLayout();
  }

  @override
  void didUpdateWidget(CatalogFloatingActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    _syncAfterLayout();
  }

  void _syncAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
  }

  void _onScroll() {
    final controller = widget.controller;
    var visible = false;
    if (widget.enabled && controller.hasClients) {
      final position = controller.position;
      if (position.hasContentDimensions) {
        // Different thresholds avoid flicker near the point of appearance.
        final threshold = _showTop
            ? 96.0
            : (position.viewportDimension * 0.8).clamp(240.0, 480.0);
        visible = position.extentBefore > threshold;
      }
    }
    if (visible != _showTop) setState(() => _showTop = visible);
  }

  Future<void> _scrollToTop() async {
    final controller = widget.controller;
    if (!controller.hasClients) return;
    final position = controller.position;
    if (!position.hasContentDimensions || position.viewportDimension <= 0) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpTo(position.minScrollExtent);
      return;
    }
    final screens = position.extentBefore / position.viewportDimension;
    final milliseconds = (300 + screens * 45).round().clamp(300, 650);
    await controller.animateTo(
      position.minScrollExtent,
      duration: Duration(milliseconds: milliseconds),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _transition;
    final showTop = widget.enabled && _showTop;
    final builderSize = showTop ? 48.0 : 56.0;
    return SizedBox(
      width: 56,
      height: 124,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.enabled && widget.onOpenBuilder != null)
            AnimatedPositioned(
              duration: duration,
              curve: _curve,
              right: (56 - builderSize) / 2,
              bottom: showTop ? 68 : 0,
              child: AnimatedContainer(
                duration: duration,
                curve: _curve,
                width: builderSize,
                height: builderSize,
                child: FloatingActionButton(
                  heroTag: null,
                  tooltip: context.l10n.catalogAssemblerTooltip,
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
                  onPressed: widget.onOpenBuilder,
                  child: AnimatedScale(
                    duration: duration,
                    curve: _curve,
                    scale: showTop ? 20 / 24 : 1,
                    child: QIcon(
                      asset: 'assets/ic/fileformat/settings.svg',
                      color: colors.onAccent,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !showTop,
              child: ExcludeSemantics(
                excluding: !showTop,
                child: AnimatedSlide(
                  duration: duration,
                  curve: _curve,
                  offset: showTop ? Offset.zero : const Offset(0, 0.25),
                  child: AnimatedScale(
                    duration: duration,
                    curve: _curve,
                    scale: showTop ? 1 : 0.8,
                    child: AnimatedOpacity(
                      duration: duration,
                      curve: _curve,
                      opacity: showTop ? 1 : 0,
                      child: FloatingActionButton(
                        heroTag: null,
                        tooltip: context.l10n.catalogBackToTop,
                        backgroundColor: colors.accent,
                        foregroundColor: colors.onAccent,
                        onPressed: () =>
                            guarded('[Catalog] scroll to top', _scrollToTop),
                        child: QIcon(
                          asset: 'assets/ic/nav/chevron-up.svg',
                          color: colors.onAccent,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
