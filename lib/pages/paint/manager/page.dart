import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets/notification.dart';
import 'package:qunleashed/components/appbar.dart';
import '../editor/page.dart';
import '../project.dart';
import 'controller.dart';
import '../dolphin/page.dart';

/// Pixel Draw project manager: the landing screen for the paint tool. Lists
/// saved animations, device imports and drafts, opens them in the editor, and
/// imports/sends dolphin animations to a connected device.
class ProjectManagerPage extends StatefulWidget {
  const ProjectManagerPage({super.key});

  @override
  State<ProjectManagerPage> createState() => _ProjectManagerPageState();
}

class _ProjectManagerPageState extends State<ProjectManagerPage> {
  late final ProjectManagerController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = ProjectManagerController();
    _ctrl.addListener(_onChange);
    _ctrl.loadAll();
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
  }

  Future<void> _openSync() async {
    // Cross-fade rather than the default lateral slide, so it reads as the
    // content rebuilding in place rather than a sideways navigation.
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => const ManifestSyncPage(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    // Sending may have changed the local library; reconcile on return.
    await _ctrl.loadAll(silent: true);
  }

  Future<void> _openEditor(PaintProject? project) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PaintPage(project: project)));
    // Returning from the editor may have created or updated a draft.
    await _ctrl.loadAll(silent: true);
  }

  Future<void> _confirmDelete(PaintProject project) async {
    final colors = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: colors.dialogBarrier,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Delete project',
          style: TextStyle(color: colors.dialogText),
        ),
        content: Text(
          'Delete "${project.name}"? This cannot be undone.',
          style: TextStyle(color: colors.dialogMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: colors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await _ctrl.deleteProject(project);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: QPageAppBar(
        title: 'Pixel Draw',
        actions: [
          QPageAppBarAction(
            onPressed: _ctrl.importing ? null : () => _openEditor(null),
            icon: const Icon(Icons.add),
            tooltip: 'New project',
          ),
          QPageAppBarAction(
            onPressed: (_ctrl.isConnected && !_ctrl.importing) ? _import : null,
            icon: const Icon(Icons.download_outlined),
            tooltip: _ctrl.isConnected
                ? 'Import from device'
                : 'Connect a device to import',
          ),
          QPageAppBarAction(
            onPressed: _ctrl.importing ? null : _openSync,
            icon: const Icon(Icons.upload_outlined),
            tooltip: 'Send pack to device',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_ctrl.importing) _buildImportProgress(colors),
          Expanded(child: _buildBody(colors)),
        ],
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
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    // Pull-down (overscroll) refresh, like a browser. AlwaysScrollableScrollPhysics
    // lets it trigger even when the content is shorter than the viewport.
    return RefreshIndicator(
      color: colors.accent,
      onRefresh: () => _ctrl.loadAll(silent: true),
      child: _ctrl.projects.isEmpty
          ? LayoutBuilder(
              builder: (_, c) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: _buildEmpty(colors),
                ),
              ),
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: _ctrl.projects.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (_, i) {
                final p = _ctrl.projects[i];
                return _ProjectRow(
                  key: ValueKey(p.path),
                  project: p,
                  colors: colors,
                  selected: _ctrl.selectedId == p.id,
                  onTap: () => _ctrl.select(p.id),
                  onOpen: () => _openEditor(p),
                  onDelete: () => _confirmDelete(p),
                );
              },
            ),
    );
  }

  Widget _buildEmpty(QAppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.palette_outlined, size: 56, color: colors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No projects yet',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a new animation or import dolphin animations from a '
              'connected device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _openEditor(null),
              icon: const Icon(Icons.add),
              label: const Text('New project'),
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

String _formatDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}';
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    super.key,
    required this.project,
    required this.colors,
    required this.selected,
    required this.onTap,
    required this.onOpen,
    required this.onDelete,
  });

  final PaintProject project;
  final QAppColors colors;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

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
        _ProjectPreview(
          key: ValueKey('preview-${project.path}-collapsed'),
          project: project,
          width: 112,
          full: false,
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
        LayoutBuilder(
          builder: (_, constraints) {
            final w = constraints.maxWidth.clamp(0.0, 320.0);
            return Center(
              child: _ProjectPreview(
                key: ValueKey('preview-${project.path}-expanded'),
                project: project,
                width: w,
                full: true,
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
        const SizedBox(height: 12),
        _buildDetails(),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton.icon(
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, size: 18, color: colors.danger),
              label: Text('Delete', style: TextStyle(color: colors.danger)),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Open'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.onAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// All project metadata as a borderless key/value table.
  Widget _buildDetails() {
    final d = project.dolphin;
    final rows = <(String, String)>[
      ('Frame files', '${project.frameCount}'),
      ('Passive frames', '${d.passiveFrames}'),
      ('Active frames', '${d.activeFrames}'),
      ('Order', '${d.fullOrder.length} steps'),
      ('Frame rate', '${d.frameRate} fps'),
      ('Duration', '${d.duration}'),
      ('Size', '${d.width}×${d.height}'),
      ('Active cycles', '${d.activeCycles}'),
      ('Active cooldown', '${d.activeCooldown}'),
      ('Modified', _formatDate(project.modified)),
      ('Path', project.path),
    ];
    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (final (k, v) in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 16, bottom: 6),
                child: Text(
                  k,
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  v,
                  style: TextStyle(color: colors.textPrimary, fontSize: 12),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildInfo() {
    final detail = project.frameCount > 1
        ? '${project.frameCount} frames'
        : '1 frame';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          project.name,
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
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

/// Lazily decodes and loops a project's preview frames. Decoding happens once
/// the row is built (scrolled into view), keeping large libraries cheap.
class _ProjectPreview extends StatefulWidget {
  const _ProjectPreview({
    super.key,
    required this.project,
    required this.width,
    required this.full,
    required this.colors,
  });

  final PaintProject project;
  final double width;
  final bool full;
  final QAppColors colors;

  @override
  State<_ProjectPreview> createState() => _ProjectPreviewState();
}

class _ProjectPreviewState extends State<_ProjectPreview> {
  List<ui.Image> _frames = const [];
  Timer? _timer;
  int _cursor = 0;
  bool _loading = true;

  double get _w => widget.width;
  double get _h => widget.width / 2; // 128:64 → 2:1

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preview = await widget.project.loadPreview(full: widget.full);
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

  /// A frame order may reference the same [ui.Image] more than once (e.g.
  /// "0 1 2 1 0"), so dispose each unique image only once to avoid a
  /// double-dispose assertion.
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
        border: Border.all(color: colors.screenBorder.withAlpha(40)),
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
      return Icon(
        Icons.broken_image_outlined,
        size: 18,
        color: colors.textMuted,
      );
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
