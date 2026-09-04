import '../../../../services/localization/l10n.dart';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';
import '../../../../components/filelist/sync_progress_bar.dart';
import '../../../../components/notification.dart';
import '../../../../components/path.dart';
import 'package:qunleashed/components/appbar.dart';
import '../../../archive/editor/open.dart';
import '../dolphin/importer.dart';
import '../dolphin/sender.dart';
import '../editor/page.dart';
import '../project.dart';
import '../project_preview.dart';
import 'controller.dart';
import 'details.dart';

/// Pixel Draw's library screen: every local animation with its manifest
/// settings. Rows open in the editor, the preview picks the animation the
/// details pane describes (and mirrors it on the device), and the pack that
/// goes to `/ext/dolphin` is assembled right here — including editing the
/// manifest as text.
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
        context.l10n.paintConnectToImport,
        type: QNotificationType.error,
      );
      return;
    }
    final written = await _ctrl.importFromDevice();
    if (!mounted || _ctrl.error != null) return;
    if (written == 0) {
      context.showNotification(
        context.l10n.paintImportUpToDate,
        type: QNotificationType.good,
      );
    }
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
          context.l10n.paintDeleteProject,
          style: TextStyle(color: colors.dialogText),
        ),
        content: Text(
          context.l10n.paintDeleteProjectMessage(project.name),
          style: TextStyle(color: colors.dialogMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              context.l10n.commonCancel,
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.l10n.commonDelete,
              style: TextStyle(color: colors.danger),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await _ctrl.deleteProject(project);
  }

  Future<void> _confirmSend() async {
    if (!_ctrl.isConnected) {
      context.showNotification(
        context.l10n.paintConnectToImport,
        type: QNotificationType.error,
      );
      return;
    }
    final colors = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: colors.dialogBarrier,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          context.l10n.paintSendToDevice,
          style: TextStyle(color: colors.dialogText),
        ),
        content: Text(
          context.l10n.paintUploadConfirm(_ctrl.packCount),
          style: TextStyle(color: colors.dialogMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              context.l10n.commonCancel,
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.l10n.paintSendAction,
              style: TextStyle(color: colors.accent),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await _ctrl.send();
  }

  /// Hands the manifest to the app's text editor as a scratch file. Saving it
  /// parses the text straight back into the list, so hand edits survive into
  /// the upload.
  Future<void> _editManifest() async {
    final tmp = await io.Directory.systemTemp.createTemp('qu_manifest_');
    final file = io.File(pathJoin([tmp.path, 'manifest.txt']));
    try {
      await file.writeAsString(_ctrl.manifestText(), flush: true);
      if (!mounted) return;
      await openLocalFileInEditor(
        context,
        localPath: file.path,
        title: 'manifest.txt',
        onSave: (bytes) async {
          final applied = _ctrl.applyManifest(
            utf8.decode(bytes, allowMalformed: true),
          );
          if (!mounted) return true;
          context.showNotification(
            applied == 0
                ? context.l10n.paintManifestInvalid
                : context.l10n.paintManifestApplied,
            type: applied == 0
                ? QNotificationType.warning
                : QNotificationType.good,
          );
          return true;
        },
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification('$e', type: QNotificationType.error);
    } finally {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }

  bool get _allInPack =>
      _ctrl.items.isNotEmpty && _ctrl.packCount == _ctrl.items.length;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: QPageAppBar(
        title: context.l10n.paintTitle,
        actions: [
          QPageAppBarAction(
            onPressed: _ctrl.busy ? null : () => _openEditor(null),
            icon: const Icon(Icons.add),
            tooltip: context.l10n.paintNewProject,
          ),
          QPageAppBarAction(
            onPressed: (_ctrl.isConnected && !_ctrl.busy) ? _import : null,
            icon: const Icon(Icons.download_outlined),
            tooltip: _ctrl.isConnected
                ? context.l10n.paintImportFromDevice
                : context.l10n.paintConnectToImportShort,
          ),
          QPageAppBarAction(
            onPressed: (_ctrl.busy || _ctrl.loading) ? null : _editManifest,
            icon: const Icon(Icons.edit_note),
            tooltip: context.l10n.paintEditManifest,
          ),
          QPageAppBarAction(
            onPressed: (_ctrl.busy || _ctrl.items.isEmpty)
                ? null
                : (_allInPack ? _ctrl.deselectAll : _ctrl.selectAll),
            icon: Icon(_allInPack ? Icons.deselect : Icons.select_all),
            tooltip: _allInPack
                ? context.l10n.paintDeselectAll
                : context.l10n.paintSelectAll,
          ),
          _SendAction(
            count: _ctrl.packCount,
            enabled: !_ctrl.busy && _ctrl.packCount > 0,
            onPressed: _confirmSend,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_ctrl.importing) _buildImportProgress(colors),
          if (_ctrl.sending) _buildSendProgress(colors),
          Expanded(child: _buildContent(colors)),
        ],
      ),
    );
  }

  Widget _buildContent(QAppColors colors) {
    return LayoutBuilder(
      builder: (_, constraints) {
        // Material 3 window size classes: the details pane only earns its place
        // in the expanded class, and the decision comes from the actual box we
        // were given, never from device orientation.
        final expanded = constraints.maxWidth >= 840;
        if (expanded) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildGallery(colors, bottomInset: 16)),
              VerticalDivider(width: 1, thickness: 1, color: colors.divider),
              SizedBox(
                width: kDetailsPaneWidth,
                child: PaintDetailsPane(
                  item: _ctrl.selected,
                  colors: colors,
                  ctrl: _ctrl,
                  onOpen: () {
                    final item = _ctrl.selected;
                    if (item != null) _openEditor(item.project);
                  },
                ),
              ),
            ],
          );
        }

        // Compact and medium: the gallery owns the screen and the details ride
        // a draggable sheet, which exists only while something is selected.
        final selected = _ctrl.selected;
        return Stack(
          children: [
            _buildGallery(
              colors,
              bottomInset: selected == null ? 16 : kSheetPeek + 10,
            ),
            if (selected != null)
              Positioned.fill(
                child: PaintDetailsSheet(
                  item: selected,
                  colors: colors,
                  ctrl: _ctrl,
                  onClose: () => _ctrl.select(null),
                  onOpen: () => _openEditor(selected.project),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildImportProgress(QAppColors colors) {
    final p = _ctrl.importProgress;
    return SyncProgressBar(
      icon: p?.phase == ImportPhase.downloading
          ? Icons.download_rounded
          : Icons.sync_rounded,
      label: _importLabel(p),
      progress: p?.ratio ?? 0,
      fileProgress: p?.fileProgress,
      color: colors.accent,
    );
  }

  String _importLabel(ImportProgress? p) {
    if (p == null) return context.l10n.paintPreparing;
    return switch (p.phase) {
      ImportPhase.listing =>
        '${context.l10n.paintDeviceListing} ${p.current}/${p.total}',
      ImportPhase.checking =>
        '${context.l10n.paintChecking} ${p.current}/${p.total} · ${p.name}',
      ImportPhase.downloading => context.l10n.paintDownloadingFile(
        p.name,
        p.current,
        p.total,
      ),
    };
  }

  Widget _buildSendProgress(QAppColors colors) {
    final p = _ctrl.sendProgress;
    final checking = p == null || p.phase == SendPhase.checking;
    return SyncProgressBar(
      icon: checking ? Icons.sync_rounded : Icons.upload_rounded,
      label: p == null
          ? context.l10n.paintPreparing
          : '${checking ? context.l10n.paintChecking : context.l10n.paintSending}'
                ' ${p.current}/${p.total} · ${p.fileName}',
      progress: p?.ratio ?? 0,
      fileProgress: p?.fileProgress,
      color: colors.accent,
    );
  }

  Widget _buildGallery(QAppColors colors, {required double bottomInset}) {
    if (_ctrl.loading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    // Pull-down (overscroll) refresh, like a browser. AlwaysScrollableScrollPhysics
    // lets it trigger even when the content is shorter than the viewport.
    return RefreshIndicator(
      color: colors.accent,
      onRefresh: () => _ctrl.loadAll(silent: true),
      child: _ctrl.items.isEmpty
          ? LayoutBuilder(
              builder: (_, c) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: _buildEmpty(colors),
                ),
              ),
            )
          : LayoutBuilder(
              builder: (_, c) {
                const gap = 10.0;
                const pad = 12.0;
                const maxCell = 260.0;
                final usable = (c.maxWidth - pad * 2).clamp(1.0, 4000.0);
                // Same column maths SliverGridDelegateWithMaxCrossAxisExtent
                // uses, repeated here so the tile height can follow the real
                // cell width instead of an assumed aspect ratio.
                final columns = (usable / (maxCell + gap)).ceil().clamp(1, 8);
                final cell = (usable - gap * (columns - 1)) / columns;
                return GridView.builder(
                  key: const PageStorageKey('paintGallery'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(pad, 12, pad, bottomInset),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: gap,
                    mainAxisSpacing: gap,
                    mainAxisExtent: cell / 2 + 54,
                  ),
                  itemCount: _ctrl.items.length,
                  itemBuilder: (_, i) {
                    final item = _ctrl.items[i];
                    return _AnimationCard(
                      key: ValueKey(item.project.path),
                      item: item,
                      colors: colors,
                      selected: _ctrl.selectedId == item.id,
                      enabled: !_ctrl.busy,
                      onSelect: () => _ctrl.select(item.id),
                      onOpen: () => _openEditor(item.project),
                      onTogglePack: () => _ctrl.toggleInPack(item),
                      onDelete: () => _confirmDelete(item.project),
                    );
                  },
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
            Icon(Icons.palette_outlined, size: 44, color: colors.textMuted),
            const SizedBox(height: 14),
            Text(
              context.l10n.paintNoProjects,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.paintNoProjectsHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openEditor(null),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.paintNewProject),
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

/// Upload button carrying the pack size, so the count needs no second screen.
class _SendAction extends StatelessWidget {
  const _SendAction({
    required this.count,
    required this.enabled,
    required this.onPressed,
  });

  final int count;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return QPageAppBarAction(
      onPressed: enabled ? onPressed : null,
      tooltip: context.l10n.paintSendCount(count),
      icon: count == 0
          ? const Icon(Icons.upload_outlined)
          : Badge(
              label: Text('$count'),
              child: const Icon(Icons.upload_outlined),
            ),
    );
  }
}

/// A gallery tile: the animation itself is the content, the name is the label.
/// Tapping selects it (details + mirroring on the device), the pencil opens the
/// editor, the checkbox puts it in the pack and the bin deletes it.
class _AnimationCard extends StatelessWidget {
  const _AnimationCard({
    super.key,
    required this.item,
    required this.colors,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    required this.onOpen,
    required this.onTogglePack,
    required this.onDelete,
  });

  final PaintItem item;
  final QAppColors colors;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final VoidCallback onTogglePack;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final project = item.project;
    final inPack = item.entry.selected;
    return Material(
      color: colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? colors.accent : colors.divider,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onSelect,
        onDoubleTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                ProjectPreview(
                  key: ValueKey('preview-${project.path}'),
                  project: project,
                  full: false,
                  colors: colors,
                  showBorder: false,
                  radius: 0,
                ),
                Positioned(
                  left: 4,
                  top: 4,
                  child: _PackToggle(
                    on: inPack,
                    colors: colors,
                    onTap: enabled ? onTogglePack : null,
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: Row(
                    children: [
                      _TileButton(
                        icon: Icons.edit_outlined,
                        colors: colors,
                        tooltip: context.l10n.commonOpen,
                        onTap: enabled ? onOpen : null,
                      ),
                      const SizedBox(width: 4),
                      _TileButton(
                        icon: Icons.delete_outline,
                        colors: colors,
                        tooltip: context.l10n.commonDelete,
                        onTap: enabled ? onDelete : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      project.frameCount > 1
                          ? context.l10n.paintFrameCount(project.frameCount)
                          : '1 frame',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pack membership, drawn on the preview so the tile needs no second row.
class _PackToggle extends StatelessWidget {
  const _PackToggle({
    required this.on,
    required this.colors,
    required this.onTap,
  });

  final bool on;
  final QAppColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.paintSendToDevice,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: on ? colors.accent : colors.background.withAlpha(190),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? colors.accent : colors.divider),
          ),
          child: Icon(
            on ? Icons.check : Icons.check_box_outline_blank,
            size: 15,
            color: on ? colors.onAccent : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _TileButton extends StatelessWidget {
  const _TileButton({
    required this.icon,
    required this.colors,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final QAppColors colors;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: colors.background.withAlpha(190),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.divider),
          ),
          child: Icon(icon, size: 15, color: colors.textSecondary),
        ),
      ),
    );
  }
}
