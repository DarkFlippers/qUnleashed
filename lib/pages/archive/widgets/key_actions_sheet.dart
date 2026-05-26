import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../../../widgets/notification.dart';
import '../../tools/map/models/pin.dart';
import '../../tools/map/page.dart';
import '../controller.dart';
import '../emulate/page.dart';
import '../file_manager/controller.dart';
import '../file_manager/page.dart';
import '../file_manager/text_editor_page.dart';
import '../models/key.dart';
import '../share_remote_file.dart';

class KeyActionsSheet extends StatelessWidget {
  const KeyActionsSheet({
    super.key,
    required this.controller,
    required this.flipperKey,
    this.onRename,
    this.onDuplicate,
    this.onToggleFavorite,
  });

  final ArchiveController controller;
  final ArchiveKey flipperKey;
  final VoidCallback? onRename;
  final VoidCallback? onDuplicate;
  final VoidCallback? onToggleFavorite;

  static Future<void> show(
    BuildContext context,
    ArchiveController controller,
    ArchiveKey key, {
    VoidCallback? onRename,
    VoidCallback? onDuplicate,
    VoidCallback? onToggleFavorite,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: KeyActionsSheet(
              controller: controller,
              flipperKey: key,
              onRename: onRename,
              onDuplicate: onDuplicate,
              onToggleFavorite: onToggleFavorite,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasCoordinates(flipperKey),
      builder: (context, snapshot) {
        return _KeyActionsContent(
          controller: controller,
          flipperKey: flipperKey,
          onRename: onRename,
          onDuplicate: onDuplicate,
          onToggleFavorite: onToggleFavorite,
          canShowOnMap: snapshot.data ?? false,
        );
      },
    );
  }

  Future<bool> _hasCoordinates(ArchiveKey k) async {
    final path = k.localPath;
    if (path == null || path.isEmpty) return false;
    try {
      final file = io.File(path);
      if (!await file.exists()) return false;
      final content = await file.readAsString();
      double? lat;
      double? lon;
      for (final raw in content.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        final lower = line.toLowerCase();
        final colon = line.indexOf(':');
        if (colon < 0) continue;
        final value = line.substring(colon + 1).trim();
        if (lower.startsWith('latitude:') ||
            lower.startsWith('latitute:') ||
            lower.startsWith('lat:')) {
          lat = double.tryParse(value);
        } else if (lower.startsWith('longitude:') ||
            lower.startsWith('lon:') ||
            lower.startsWith('lng:')) {
          lon = double.tryParse(value);
        }
      }
      if (lat == null || lon == null) return false;
      return lat != 0 || lon != 0;
    } catch (_) {
      return false;
    }
  }
}

class _KeyActionsContent extends StatelessWidget {
  const _KeyActionsContent({
    required this.controller,
    required this.flipperKey,
    required this.canShowOnMap,
    this.onRename,
    this.onDuplicate,
    this.onToggleFavorite,
  });

  final ArchiveController controller;
  final ArchiveKey flipperKey;
  final bool canShowOnMap;
  final VoidCallback? onRename;
  final VoidCallback? onDuplicate;
  final VoidCallback? onToggleFavorite;

  List<_Action> _buildActions(BuildContext context) {
    final k = flipperKey;
    final connected = controller.isConnected;
    final actions = <_Action>[];

    if (onRename != null) {
      actions.add(_Action(icon: Icons.edit_outlined, label: 'Rename', onTap: onRename!));
    }
    if (onDuplicate != null) {
      actions.add(_Action(icon: Icons.copy_outlined, label: 'Duplicate', onTap: onDuplicate!));
    }
    if (onToggleFavorite != null) {
      final isFav = k.favorite;
      actions.add(_Action(
        icon: isFav ? Icons.star_rounded : Icons.star_outline_rounded,
        label: isFav ? 'Unstar' : 'Star',
        onTap: onToggleFavorite!,
      ));
    }

    if (k.state == ArchiveKeyState.deleted) {
      actions.add(_Action(
        icon: Icons.restore,
        label: 'Restore',
        onTap: () async {
          if (!connected) {
            context.showNotification(
              'Connect a Flipper to restore',
              type: QNotificationType.warning,
            );
            return;
          }
          await controller.restoreKey(k);
        },
      ));
    }
    if (k.onDevice && connected && k.category.emulatable) {
      actions.add(_Action(
        icon: Icons.play_arrow,
        label: 'Emulate',
        onTap: () => _emulateOnFlipper(context, k),
      ));
    }
    if (canShowOnMap) {
      actions.add(_Action(
        icon: Icons.map_outlined,
        label: 'Map',
        onTap: () => _openOnMap(context, k),
      ));
    } else if (k.inLocal && (k.localPath?.isNotEmpty ?? false)) {
      actions.add(_Action(
        icon: Icons.add_location_alt_outlined,
        label: 'Map',
        onTap: () => _pickLocation(context, k),
      ));
    }
    if (k.onDevice && connected) {
      actions.add(_Action(
        icon: Icons.folder_open,
        label: 'Reveal',
        onTap: () => _openInFileManager(context, k),
      ));
      actions.add(_Action(
        icon: Icons.edit_note,
        label: 'Edit',
        onTap: () => _openInEditor(context, k),
      ));
    }
    final shareIcon = isShareSupported ? Icons.ios_share : Icons.content_copy;
    final shareLabel = isShareSupported ? 'Share' : 'Copy';
    final hasLocal = k.inLocal && (k.localPath?.isNotEmpty ?? false);
    if (hasLocal) {
      actions.add(_Action(
        icon: shareIcon,
        label: shareLabel,
        onTap: () => shareLocalFile(context, k.localPath!, displayName: k.name),
      ));
    } else if (k.onDevice && connected) {
      actions.add(_Action(
        icon: shareIcon,
        label: shareLabel,
        onTap: () => _shareFromDevice(context, k),
      ));
    }

    actions.add(_Action(
      icon: Icons.delete_forever,
      label: 'Delete',
      destructive: true,
      onTap: () => _confirmAndDelete(context, k, connected),
    ));

    return actions;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final k = flipperKey;
    final actions = _buildActions(context);

    return Material(
      color: colors.card,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: k.category.color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SvgPicture.asset(
                      k.category.asset,
                      width: 22,
                      height: 22,
                      colorFilter: ColorFilter.mode(k.category.color, BlendMode.srcIn),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          k.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          k.remotePath,
                          style: TextStyle(color: colors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.divider),
            _KeyActionsGrid(actions: actions),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _emulateOnFlipper(BuildContext context, ArchiveKey k) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EmulatePage(flipperKey: k)),
    );
  }

  void _openInEditor(BuildContext context, ArchiveKey k) {
    final remoteParent = _parent(k.remotePath);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TextEditorPage(
          controller: FileManagerController(initialPath: remoteParent),
          remotePath: k.remotePath,
        ),
      ),
    );
  }

  void _shareFromDevice(BuildContext context, ArchiveKey k) {
    final remoteParent = _parent(k.remotePath);
    shareRemoteFile(
      context,
      FileManagerController(initialPath: remoteParent),
      k.remotePath,
      displayName: k.name,
    );
  }

  void _openInFileManager(BuildContext context, ArchiveKey k) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FileManagerPage(initialPath: _parent(k.remotePath)),
      ),
    );
  }

  void _openOnMap(BuildContext context, ArchiveKey k) {
    final path = k.localPath;
    if (path == null || path.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FlipperMapPage(focusPinPath: path)),
    );
  }

  void _pickLocation(BuildContext context, ArchiveKey k) {
    final path = k.localPath;
    if (path == null || path.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FlipperMapPage(
          pickLocationFor: MapPickTarget(
            localPath: path,
            remotePath: k.remotePath,
            displayName: k.name,
          ),
        ),
      ),
    );
  }

  String _parent(String path) {
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return '/';
    return path.substring(0, idx);
  }

  Future<void> _confirmAndDelete(
    BuildContext context,
    ArchiveKey k,
    bool connected,
  ) async {
    final colors = context.appColors;
    final hasLocal = k.inLocal;
    final onDevice = k.onDevice;

    String message;
    if (connected && onDevice && hasLocal) {
      message =
          'This file will be permanently deleted from the Flipper and this phone. This cannot be undone.';
    } else if (connected && onDevice) {
      message =
          'This file will be permanently deleted from the Flipper. There is no local copy.';
    } else if (!connected && onDevice) {
      message =
          'No Flipper is connected. This file will be deleted only from this phone and will remain on the Flipper.';
    } else {
      message = 'This local file will be permanently deleted.';
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.dialogBackground,
        title: Text('Delete ${k.name}?',
            style: TextStyle(color: colors.dialogText)),
        content: Text(message,
            style: TextStyle(color: colors.dialogMuted, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: colors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.deleteKey(k);
    }
  }
}

class _KeyActionsGrid extends StatelessWidget {
  const _KeyActionsGrid({required this.actions});

  final List<_Action> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in actions)
            SizedBox(width: 72, height: 72, child: _ActionTile(action: a)),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final _Action action;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDestructive = action.destructive;
    final iconColor = isDestructive ? colors.danger : colors.textSecondary;
    final labelColor = isDestructive ? colors.danger : colors.textSecondary;

    return Material(
      color: colors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          action.onTap();
        },
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, color: iconColor, size: 22),
            const SizedBox(height: 5),
            Text(
              action.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: labelColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action {
  _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}
