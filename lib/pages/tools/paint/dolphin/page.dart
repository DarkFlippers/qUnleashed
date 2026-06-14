import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qunleashed/components/appbar.dart';

import '../../../../theme/theme.dart';
import '../../../../widgets/notification.dart';
import '../project.dart';
import 'controller.dart';

/// "Send dolphin pack to device" screen. Lists every local project with the
/// FlipperAnimationManager-style controls (select, weight, level/butthurt range)
/// and uploads the selected set to `/ext/dolphin`, manifest last.
class ManifestSyncPage extends StatefulWidget {
  const ManifestSyncPage({super.key});

  @override
  State<ManifestSyncPage> createState() => _ManifestSyncPageState();
}

class _ManifestSyncPageState extends State<ManifestSyncPage> {
  late final ManifestSyncController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = ManifestSyncController();
    _ctrl.addListener(_onChange);
    _ctrl.load();
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

  Future<void> _confirmSend() async {
    if (!_ctrl.isConnected) {
      context.showNotification(
        'Connect a device to send animations',
        type: QNotificationType.error,
      );
      return;
    }
    final colors = context.appColors;
    final count = _ctrl.selectedCount;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: colors.dialogBarrier,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Send to device', style: TextStyle(color: colors.dialogText)),
        content: Text(
          'Upload $count animation${count == 1 ? '' : 's'} and rewrite '
          '/ext/dolphin/manifest.txt on the device?',
          style: TextStyle(color: colors.dialogMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Send', style: TextStyle(color: colors.accent)),
          ),
        ],
      ),
    );
    if (ok == true) await _ctrl.send();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: QPageAppBar(
        title: 'Send to device',
        actions: [
          QPageAppBarAction(
            onPressed: _ctrl.sending ? null : _ctrl.selectAll,
            icon: const Icon(Icons.select_all),
            tooltip: 'Select all',
          ),
          QPageAppBarAction(
            onPressed: _ctrl.sending ? null : _ctrl.deselectAll,
            icon: const Icon(Icons.deselect),
            tooltip: 'Deselect all',
          ),
        ],
      ),
      floatingActionButton: _buildSendButton(colors),
      body: Column(
        children: [
          if (_ctrl.sending) _buildProgress(colors),
          Expanded(child: _buildBody(colors)),
        ],
      ),
    );
  }

  Widget? _buildSendButton(QAppColors colors) {
    if (_ctrl.loading) return null;
    final count = _ctrl.selectedCount;
    return FloatingActionButton.extended(
      onPressed: (_ctrl.sending || count == 0) ? null : _confirmSend,
      backgroundColor: (count == 0 || _ctrl.sending)
          ? colors.card
          : colors.accent,
      foregroundColor: (count == 0 || _ctrl.sending)
          ? colors.textMuted
          : colors.onAccent,
      icon: const Icon(Icons.publish),
      label: Text('Send ($count)'),
    );
  }

  Widget _buildProgress(QAppColors colors) {
    return Container(
      color: colors.card,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _ctrl.status ?? 'Sending…',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _ctrl.progress,
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
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_ctrl.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No projects to send. Create a drawing or animation, or import '
            'dolphin animations from a device first.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
      itemCount: _ctrl.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final item = _ctrl.items[i];
        return _SyncCard(
          key: ValueKey(item.project.path),
          item: item,
          colors: colors,
          mirroring: _ctrl.previewId == item.project.id,
          enabled: !_ctrl.sending,
          onTapPreview: () => _ctrl.mirror(item),
          onToggle: () => _ctrl.toggleSelected(item),
          onWeight: (v) => _ctrl.setWeight(item, v),
          onLevels: ({min, max}) => _ctrl.setLevels(item, min: min, max: max),
          onButthurt: ({min, max}) =>
              _ctrl.setButthurt(item, min: min, max: max),
        );
      },
    );
  }
}

typedef _RangeSetter = void Function({int? min, int? max});

class _SyncCard extends StatefulWidget {
  const _SyncCard({
    super.key,
    required this.item,
    required this.colors,
    required this.mirroring,
    required this.enabled,
    required this.onTapPreview,
    required this.onToggle,
    required this.onWeight,
    required this.onLevels,
    required this.onButthurt,
  });

  final SyncItem item;
  final QAppColors colors;
  final bool mirroring;
  final bool enabled;
  final VoidCallback onTapPreview;
  final VoidCallback onToggle;
  final ValueChanged<int> onWeight;
  final _RangeSetter onLevels;
  final _RangeSetter onButthurt;

  @override
  State<_SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends State<_SyncCard> {
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final entry = widget.item.entry;
    return Material(
      color: entry.selected ? colors.accent.withAlpha(28) : colors.card,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: widget.onTapPreview,
                  child: _AnimPreview(
                    key: ValueKey('prev-${widget.item.project.path}'),
                    project: widget.item.project,
                    colors: colors,
                    highlight: widget.mirroring,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _buildInfo()),
              ],
            ),
            const SizedBox(height: 8),
            _buildUseRow(),
            _buildWeight(),
            _buildMoreToggle(),
            if (_more) _buildRanges(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo() {
    final colors = widget.colors;
    final project = widget.item.project;
    final detail = project.frameCount > 1
        ? '${project.frameCount} frames'
        : '1 frame';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.item.entry.name,
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
          widget.mirroring ? '$detail · on screen' : detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: widget.mirroring ? colors.accent : colors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildUseRow() {
    final colors = widget.colors;
    return InkWell(
      onTap: widget.enabled ? widget.onToggle : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: widget.item.entry.selected,
              onChanged: widget.enabled ? (_) => widget.onToggle() : null,
              activeColor: colors.accent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            Text(
              'Use this animation',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeight() {
    final entry = widget.item.entry;
    return _slider(
      label: 'Weight',
      value: entry.weight,
      min: 0,
      max: 14,
      onChanged: widget.onWeight,
    );
  }

  Widget _buildMoreToggle() {
    final colors = widget.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(() => _more = !_more),
        icon: Icon(
          _more ? Icons.expand_less : Icons.expand_more,
          size: 18,
          color: colors.textSecondary,
        ),
        label: Text(
          _more ? 'Less' : 'More',
          style: TextStyle(color: colors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildRanges() {
    final entry = widget.item.entry;
    return Column(
      children: [
        _slider(
          label: 'Min level',
          value: entry.minLevel,
          min: 0,
          max: entry.maxLevel,
          onChanged: (v) => widget.onLevels(min: v),
        ),
        _slider(
          label: 'Max level',
          value: entry.maxLevel,
          min: entry.minLevel,
          max: 30,
          onChanged: (v) => widget.onLevels(max: v),
        ),
        _slider(
          label: 'Min butthurt',
          value: entry.minButthurt,
          min: 0,
          max: entry.maxButthurt,
          onChanged: (v) => widget.onButthurt(min: v),
        ),
        _slider(
          label: 'Max butthurt',
          value: entry.maxButthurt,
          min: entry.minButthurt,
          max: 14,
          onChanged: (v) => widget.onButthurt(max: v),
        ),
      ],
    );
  }

  Widget _slider({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    final colors = widget.colors;
    final safeMax = max <= min ? min + 1 : max;
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble().clamp(min.toDouble(), safeMax.toDouble()),
            min: min.toDouble(),
            max: safeMax.toDouble(),
            divisions: safeMax - min,
            activeColor: colors.accent,
            inactiveColor: colors.divider,
            label: '$value',
            onChanged: widget.enabled
                ? (v) => onChanged(v.round())
                : null,
          ),
        ),
        SizedBox(
          width: 24,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: TextStyle(color: colors.textPrimary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// Compact looping preview of a project's frames (128:64), mirroring the
/// manager's thumbnail. Highlights when the project is being shown on the
/// device's external display.
class _AnimPreview extends StatefulWidget {
  const _AnimPreview({
    super.key,
    required this.project,
    required this.colors,
    required this.highlight,
  });

  final PaintProject project;
  final QAppColors colors;
  final bool highlight;

  @override
  State<_AnimPreview> createState() => _AnimPreviewState();
}

class _AnimPreviewState extends State<_AnimPreview> {
  static const double _w = 112;
  static const double _h = _w / 2;

  List<ui.Image> _frames = const [];
  Timer? _timer;
  int _cursor = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preview = await widget.project.loadPreview(full: false);
    if (!mounted) {
      _disposeFrames(preview.frames);
      return;
    }
    setState(() {
      _frames = preview.frames;
      _loading = false;
    });
    if (preview.frames.length > 1) {
      _timer = Timer.periodic(
        Duration(milliseconds: preview.delayMs.clamp(33, 2000)),
        (_) {
          if (!mounted) return;
          setState(() => _cursor = (_cursor + 1) % _frames.length);
        },
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _disposeFrames(_frames);
    super.dispose();
  }

  static void _disposeFrames(List<ui.Image> frames) {
    final seen = <ui.Image>{};
    for (final img in frames) {
      if (seen.add(img)) img.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Container(
      width: _w,
      height: _h,
      decoration: BoxDecoration(
        color: colors.screenBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: widget.highlight
              ? colors.accent
              : colors.screenBorder.withAlpha(40),
          width: widget.highlight ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: _buildFrame(colors),
    );
  }

  Widget _buildFrame(QAppColors colors) {
    if (_loading) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.accent),
      );
    }
    if (_frames.isEmpty) {
      return Icon(Icons.broken_image_outlined, size: 18, color: colors.textMuted);
    }
    return RawImage(
      image: _frames[_cursor % _frames.length],
      width: _w,
      height: _h,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.none,
    );
  }
}
