import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/notification.dart';
import '../paint/page.dart';
import 'controller.dart';
import 'dolphin_animation.dart';

class AnimationManagerPage extends StatefulWidget {
  const AnimationManagerPage({super.key});

  @override
  State<AnimationManagerPage> createState() => _AnimationManagerPageState();
}

class _AnimationManagerPageState extends State<AnimationManagerPage> {
  late final AnimationManagerController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationManagerController();
    _ctrl.addListener(_onChange);
    _ctrl.loadLocal();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    final err = _ctrl.error;
    if (err != null) {
      context.showNotification(err, type: QNotificationType.error);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChange);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (!_ctrl.isConnected) {
      context.showNotification(
        'Connect a device to import animations',
        type: QNotificationType.error,
      );
      return;
    }
    await _ctrl.importFromDevice();
    if (!mounted) return;
    if (_ctrl.error == null) {
      context.showNotification(
        'Imported ${_ctrl.animations.length} animation(s)',
        type: QNotificationType.good,
      );
    }
  }

  Future<void> _openInPaint(DolphinAnimation anim) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaintPage(initialAnimationPath: anim.metaPath),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          _buildAppBar(colors, topInset),
          if (_ctrl.importing) _buildImportProgress(colors),
          Expanded(child: _buildBody(colors)),
        ],
      ),
    );
  }

  Widget _buildAppBar(QAppColors colors, double topInset) {
    return Container(
      color: colors.accent,
      padding: EdgeInsets.only(top: topInset),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back, color: colors.onAccent),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Animation Manager',
                    style: TextStyle(
                      color: colors.onAccent,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    _ctrl.isConnected
                        ? 'Dolphin animations · device connected'
                        : 'Dolphin animations · local',
                    style: TextStyle(
                      color: colors.onAccent.withAlpha(180),
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _ctrl.loading || _ctrl.importing
                  ? null
                  : _ctrl.loadLocal,
              icon: Icon(Icons.refresh, color: colors.onAccent),
              tooltip: 'Reload',
            ),
            IconButton(
              onPressed: (_ctrl.isConnected && !_ctrl.importing) ? _import : null,
              icon: Icon(
                Icons.download_for_offline_outlined,
                color: _ctrl.isConnected
                    ? colors.onAccent
                    : colors.onAccent.withAlpha(90),
              ),
              tooltip: _ctrl.isConnected
                  ? 'Import from device'
                  : 'Connect a device to import',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportProgress(QAppColors colors) {
    return Container(
      color: colors.card,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _ctrl.importStatus ?? 'Importing…',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _ctrl.importProgress,
              minHeight: 5,
              backgroundColor: colors.divider,
              color: colors.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(QAppColors colors) {
    if (_ctrl.loading) {
      return Center(
        child: CircularProgressIndicator(color: colors.accent),
      );
    }
    if (_ctrl.animations.isEmpty) {
      return _buildEmpty(colors);
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: _ctrl.animations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final anim = _ctrl.animations[i];
        return _AnimationRow(
          key: ValueKey(anim.dirPath),
          anim: anim,
          colors: colors,
          selected: _ctrl.selectedName == anim.name,
          onTap: () => _ctrl.select(anim.name),
          onOpen: () => _openInPaint(anim),
        );
      },
    );
  }

  Widget _buildEmpty(QAppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.movie_filter_outlined,
              size: 56,
              color: colors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'No dolphin animations',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _ctrl.isConnected
                  ? 'Import them from your connected device.'
                  : 'Connect a device to import from /ext/dolphin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _ctrl.isConnected ? _import : null,
              icon: const Icon(Icons.download_for_offline_outlined),
              label: const Text('Import from device'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.onAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimationRow extends StatelessWidget {
  const _AnimationRow({
    super.key,
    required this.anim,
    required this.colors,
    required this.selected,
    required this.onTap,
    required this.onOpen,
  });

  final DolphinAnimation anim;
  final QAppColors colors;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: selected ? colors.accent.withAlpha(28) : colors.card,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: selected ? _buildExpanded() : _buildCollapsed(),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsed() {
    return Row(
      children: [
        // Compact preview loops the passive (idle) frames.
        _AnimationPreview(
          key: ValueKey('preview-${anim.dirPath}-collapsed'),
          anim: anim,
          order: anim.passiveOrder,
          width: 112,
          colors: colors,
        ),
        const SizedBox(width: 12),
        Expanded(child: _buildInfo()),
        Icon(Icons.expand_more, color: colors.textMuted),
      ],
    );
  }

  Widget _buildExpanded() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Single large preview plays the full frame order ("full video").
        LayoutBuilder(
          builder: (_, constraints) {
            final w = constraints.maxWidth.clamp(0.0, 320.0);
            return Center(
              child: _AnimationPreview(
                key: ValueKey('preview-${anim.dirPath}-expanded'),
                anim: anim,
                order: anim.fullOrder,
                width: w,
                colors: colors,
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildInfo()),
            Icon(Icons.expand_less, color: colors.textMuted),
          ],
        ),
        const SizedBox(height: 10),
        Divider(height: 1, color: colors.divider),
        const SizedBox(height: 10),
        _buildMeta(),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Open in Pixel Draw'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          anim.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${anim.passiveFrames} passive · ${anim.activeFrames} active · '
          '${anim.frameRate} fps',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildMeta() {
    final entries = <MapEntry<String, String>>[
      MapEntry('Frames', '${anim.frameFileCount} files'),
      MapEntry('Order length', '${anim.fullOrder.length}'),
      MapEntry('Duration', '${anim.duration}'),
      MapEntry('Active cycles', '${anim.activeCycles}'),
      MapEntry('Active cooldown', '${anim.activeCooldown}'),
    ];
    return Column(
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Text(
                  e.key,
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  e.value,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Lazily decodes and loops a set of frames for an animation. The frames are
/// decoded once the widget is built (i.e. scrolled into view), keeping the list
/// cheap for large collections.
class _AnimationPreview extends StatefulWidget {
  const _AnimationPreview({
    super.key,
    required this.anim,
    required this.order,
    required this.width,
    required this.colors,
  });

  final DolphinAnimation anim;
  final List<int> order;

  /// Rendered width in logical pixels; height keeps the 128:64 (2:1) ratio.
  final double width;
  final QAppColors colors;

  @override
  State<_AnimationPreview> createState() => _AnimationPreviewState();
}

class _AnimationPreviewState extends State<_AnimationPreview> {
  final Map<int, ui.Image> _images = {};
  Timer? _timer;
  int _cursor = 0;
  bool _loading = true;

  double get _w => widget.width;
  double get _h => widget.width * dolphinFrameHeight / dolphinFrameWidth;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Only decode frames not already cached, so expanding (passive → full)
    // loads just the extra active frames.
    final needed = widget.order.toSet()..removeAll(_images.keys);
    if (needed.isNotEmpty) {
      final more = await widget.anim.loadImages(needed);
      if (!mounted) {
        for (final img in more.values) {
          img.dispose();
        }
        return;
      }
      _images.addAll(more);
    }
    if (!mounted) return;
    setState(() => _loading = false);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.order.length <= 1) return;
    final ms = (widget.anim.secondsPerFrame * 1000).clamp(33, 2000).round();
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (!mounted) return;
      setState(() => _cursor = (_cursor + 1) % widget.order.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final img in _images.values) {
      img.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final container = Container(
      width: _w,
      height: _h,
      decoration: BoxDecoration(
        color: colors.screenBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.screenBorder.withAlpha(40)),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: _buildFrame(colors),
    );
    return container;
  }

  Widget _buildFrame(QAppColors colors) {
    if (_loading) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.accent),
      );
    }
    final order = widget.order;
    if (order.isEmpty || _images.isEmpty) {
      return Icon(
        Icons.broken_image_outlined,
        size: 18,
        color: colors.textMuted,
      );
    }
    final fileIdx = order[_cursor % order.length];
    final image = _images[fileIdx] ?? _images.values.first;
    return RawImage(
      image: image,
      width: _w,
      height: _h,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.none,
    );
  }
}
