part of '../page.dart';

class _MapSheet extends StatefulWidget {
  const _MapSheet({
    required this.pins,
    required this.selected,
    required this.controller,
    required this.colors,
    required this.onSelect,
    required this.onClose,
    required this.onCopyCoords,
    this.onEdit,
  });

  final List<MapPin> pins;
  final MapPin? selected;
  final MapToolController controller;
  final QAppColors colors;
  final ValueChanged<MapPin> onSelect;
  final VoidCallback onClose;
  final VoidCallback? onEdit;
  final VoidCallback onCopyCoords;

  @override
  State<_MapSheet> createState() => _MapSheetState();
}

class _MapSheetState extends State<_MapSheet> {
  final DraggableScrollableController _sheet = DraggableScrollableController();
  double _thin = 0.06;
  double _peek = 0.16;

  // DraggableScrollableSheet compares `snapSizes` by identity: handing it a
  // freshly built list on every rebuild makes it re-snap in a post-frame
  // callback, which cancels any programmatic animateTo. So the list is cached
  // and only rebuilt when the numbers actually move.
  List<double> _snaps = const [];

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_MapSheet old) {
    super.didUpdateWidget(old);
    if (old.selected?.id == widget.selected?.id) return;
    // Run after this frame: the sheet swaps its extent object while rebuilding,
    // and an animation started before that would be driving the dead one.
    final target = widget.selected == null ? _thin : _peek;
    WidgetsBinding.instance.addPostFrameCallback((_) => _animate(target));
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
    final resting = widget.selected == null ? _thin : _peek;
    _animate(_sheet.size > resting + 0.02 ? resting : _midSize);
  }

  double get _midSize => (_peek + 0.5).clamp(_peek, 0.9);

  void _syncSnaps(double thin, double peek, double mid, double max) {
    final next = <double>[
      thin,
      if (peek > thin + 0.01) peek,
      if (mid > peek + 0.02 && mid < max - 0.02) mid,
    ];
    if (_snaps.length == next.length) {
      var same = true;
      for (var i = 0; i < next.length; i++) {
        if ((_snaps[i] - next[i]).abs() > 0.0005) {
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        if (height > 0) {
          _thin = (kMapSheetThin / height).clamp(0.02, 0.4);
          _peek = (kMapPanelPeek / height).clamp(_thin, 0.6);
        }
        const max = 0.92;
        _syncSnaps(_thin, _peek, _midSize, max);

        return DraggableScrollableSheet(
          controller: _sheet,
          // Constant: copyWith() resets the live size to initialChildSize on
          // every rebuild until the sheet has been moved once.
          initialChildSize: _thin,
          minChildSize: _thin,
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
              child: _MapPanel(
                pins: widget.pins,
                selected: widget.selected,
                controller: widget.controller,
                colors: colors,
                scrollController: scrollController,
                showHandle: true,
                onHandleTap: _toggle,
                onSelect: (pin) {
                  widget.onSelect(pin);
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _animate(_peek),
                  );
                },
                onClose: widget.onClose,
                onEdit: widget.onEdit,
                onCopyCoords: widget.onCopyCoords,
              ),
            ),
          ),
        );
      },
    );
  }
}
