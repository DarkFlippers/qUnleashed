import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../components/cardlist.dart';
import '../../../../components/format.dart';
import '../../../../components/icon.dart';
import '../../../../services/storage/fap_icons.dart' as icon_repo;
import '../../../../theme/theme.dart';
import '../../../../components/codec/fap/icon.dart';
import '../../widgets/actions_sheet.dart';
import '../../../../components/filelist/progress_fill.dart';
import '../share_remote_file.dart';
import '../controller.dart';
import 'file_type.dart';

/// Shared callbacks for a directory entry, threaded into both the list row and
/// the grid tile so the action set stays identical across view modes.
class FileEntryActions {
  const FileEntryActions({
    this.onDelete,
    this.onShare,
    this.onCopy,
    this.onCut,
    this.onDownload,
    this.onRename,
    this.onEmulate,
    this.onEdit,
    this.onIndexIcon,
  });

  final VoidCallback? onDelete;
  final VoidCallback? onShare;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onDownload;

  /// For `.fap` files only: downloads the app and caches its embedded icon so
  /// it can be indexed and shown without re-fetching the whole binary later.
  final VoidCallback? onIndexIcon;

  /// Category capabilities surfaced for files that map to an archive category,
  /// so the file manager offers the same actions as the category pages.
  final VoidCallback? onEmulate;
  final VoidCallback? onEdit;

  /// Returns a Future so the caller can block taps during the network op.
  final Future<void> Function(String)? onRename;
}

// ─── Icon badge ───────────────────────────────────────────────────────────────

class FileIconBadge extends StatefulWidget {
  const FileIconBadge({
    super.key,
    required this.entry,
    this.size = 40,
    this.muted = false,
  });

  final RemoteEntry entry;
  final double size;
  final bool muted;

  @override
  State<FileIconBadge> createState() => _FileIconBadgeState();
}

class _FileIconBadgeState extends State<FileIconBadge> {
  String? _fapAppId;
  Uint8List? _fapIcon;

  @override
  void initState() {
    super.initState();
    _resolveFapIcon();
    icon_repo.fapIconRevision.addListener(_onIconRepoChanged);
  }

  @override
  void didUpdateWidget(FileIconBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.name != widget.entry.name) {
      _fapIcon = null;
      _resolveFapIcon();
    }
  }

  @override
  void dispose() {
    icon_repo.fapIconRevision.removeListener(_onIconRepoChanged);
    super.dispose();
  }

  void _onIconRepoChanged() {
    if (mounted) _resolveFapIcon();
  }

  void _resolveFapIcon() {
    final name = widget.entry.name;
    if (widget.entry.isDir || !name.toLowerCase().endsWith('.fap')) {
      _fapAppId = null;
      return;
    }
    final appId = name.substring(0, name.length - 4);
    _fapAppId = appId;
    icon_repo.readFapIcon(appId).then((bytes) {
      if (mounted && _fapAppId == appId && bytes != null) {
        setState(() => _fapIcon = bytes);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final visual = fileVisualFor(widget.entry, colors);
    final color = widget.muted ? colors.textMuted : visual.color;
    final badge = QIconBadgeStyle.of(context, color, darkOpacity: 0.14);
    final glyph = widget.size * 0.55;
    final fapIcon = _fapIcon;

    final Widget child;
    if (fapIcon != null) {
      child = QIcon.xbm(
        bytes: fapIcon,
        width: fapIconWidth,
        height: fapIconHeight,
        cacheKey: 'repo:${widget.entry.name}',
        color: badge.foreground,
        size: glyph,
      );
    } else if (visual.asset != null) {
      child = SvgPicture.asset(
        visual.asset!,
        width: glyph,
        height: glyph,
        colorFilter: ColorFilter.mode(badge.foreground, BlendMode.srcIn),
      );
    } else {
      child = Icon(visual.icon, size: glyph, color: badge.foreground);
    }

    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: badge.background,
        borderRadius: BorderRadius.circular(widget.size * 0.28),
      ),
      child: child,
    );
  }
}

/// A small accent check-badge that floats on top of a file icon's corner while
/// the entry is selected. A card-colored ring lifts it off the icon, and the
/// parent stacks use `Clip.none` so it is never clipped by the icon bounds.
class _SelectionCheck extends StatelessWidget {
  const _SelectionCheck();

  static const double _size = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.accent,
        border: Border.all(color: colors.card, width: 2),
      ),
      child: Icon(Icons.check, size: _size * 0.6, color: colors.onAccent),
    );
  }
}

class FileGridTile extends StatelessWidget {
  const FileGridTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.actions,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.progress,
  });

  final RemoteEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final FileEntryActions actions;
  final bool selectionMode;
  final bool selected;
  final double? progress;

  void _showActionsSheet(BuildContext context) {
    FileActionsSheet.show(context, entry: entry, actions: actions);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = entry.isHidden;
    final radius = GroupedCardCorners.of(context);

    return Material(
      color: selected ? colors.accent.withValues(alpha: 0.12) : colors.card,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        // Expand so the tap target and content fill the whole cell; without
        // this the InkWell/Column shrink-wrap to the name width, making tiles
        // look uneven and leaving most of the cell untappable.
        fit: StackFit.expand,
        children: [
          ProgressFill(progress: progress),
          InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            onSecondaryTap: () => _showActionsSheet(context),
            borderRadius: radius,
            child: Padding(
              // Fixed top inset + fixed name height → the icon always sits at
              // the same position regardless of how many lines the name takes.
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      FileIconBadge(entry: entry, size: 44, muted: muted),
                      if (selectionMode && selected)
                        const Positioned(
                          right: -3,
                          bottom: -3,
                          child: _SelectionCheck(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 30,
                    child: Text(
                      entry.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted ? colors.textMuted : colors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Actions bottom sheet ─────────────────────────────────────────────────────

/// Builds the file-manager action set for a [RemoteEntry] and presents it via
/// the shared [ActionsSheet], so it stays visually and behaviourally identical
/// to the archive category pages.
class FileActionsSheet {
  const FileActionsSheet._();

  static Future<void> show(
    BuildContext context, {
    required RemoteEntry entry,
    required FileEntryActions actions,
    VoidCallback? onRenameInline,
  }) {
    final isDir = entry.isDir;
    final items = <ActionItem>[];

    void add(
      IconData icon,
      String label,
      VoidCallback? onTap, {
      bool destructive = false,
    }) {
      if (onTap == null) return;
      items.add(
        ActionItem(
          icon: icon,
          label: label,
          destructive: destructive,
          onTap: onTap,
        ),
      );
    }

    final renameTap =
        onRenameInline ??
        (actions.onRename != null
            ? () => actions.onRename!.call(entry.name)
            : null);
    add(Icons.drive_file_rename_outline, l10n.fmRename, renameTap);
    add(Icons.copy_outlined, l10n.fmCopy, actions.onCopy);
    add(Icons.drive_file_move_outlined, l10n.fmMove, actions.onCut);
    add(Icons.download_outlined, l10n.fmDownload, actions.onDownload);
    add(Icons.image_outlined, l10n.fmIndexIcon, actions.onIndexIcon);
    add(Icons.play_arrow, l10n.fileEmulate, actions.onEmulate);
    add(Icons.edit_note, l10n.fileEdit, actions.onEdit);
    if (!isDir) {
      add(
        isShareSupported ? Icons.ios_share : Icons.content_copy,
        isShareSupported ? l10n.shareShare : l10n.fileClipboard,
        actions.onShare,
      );
    }
    add(
      Icons.delete_outline,
      l10n.commonDelete,
      actions.onDelete,
      destructive: true,
    );

    final subtitle = isDir
        ? l10n.typeFolder
        : '${fileTypeLabel(entry)} · ${formatBytes(entry.size)}';

    return ActionsSheet.show(
      context,
      leading: FileIconBadge(entry: entry, size: 40),
      title: entry.name,
      subtitle: subtitle,
      actions: items,
    );
  }
}
