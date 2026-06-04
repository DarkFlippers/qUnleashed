import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../../../widgets/notification.dart';
import '../../editor/page.dart';
import '../../tools/map/models/pin.dart';
import '../../tools/map/page.dart';
import '../controller.dart';
import '../emulate/page.dart';
import '../../file_manager/controller.dart';
import '../../file_manager/page.dart';
import '../../file_manager/share_remote_file.dart';
import '../models/key.dart';
import 'actions_sheet.dart';

/// Builds the archive-specific action set for an [ArchiveKey] and presents it
/// through the shared [ActionsSheet], so the file manager and the category
/// pages render the exact same "actions" UI.
class KeyActionsSheet {
  const KeyActionsSheet._();

  static Future<void> show(
    BuildContext context,
    ArchiveController controller,
    ArchiveKey key, {
    VoidCallback? onRename,
    VoidCallback? onDuplicate,
    VoidCallback? onToggleFavorite,
  }) async {
    final canShowOnMap = await _hasCoordinates(key);
    if (!context.mounted) return;

    final leading = Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: key.category.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SvgPicture.asset(
        key.category.asset,
        width: 22,
        height: 22,
        colorFilter: ColorFilter.mode(key.category.color, BlendMode.srcIn),
      ),
    );

    final actions = _buildActions(
      context,
      controller,
      key,
      canShowOnMap: canShowOnMap,
      onRename: onRename,
      onDuplicate: onDuplicate,
      onToggleFavorite: onToggleFavorite,
    );

    await ActionsSheet.show(
      context,
      leading: leading,
      title: key.name,
      subtitle: key.remotePath,
      actions: actions,
    );
  }

  static List<ActionItem> _buildActions(
    BuildContext context,
    ArchiveController controller,
    ArchiveKey k, {
    required bool canShowOnMap,
    VoidCallback? onRename,
    VoidCallback? onDuplicate,
    VoidCallback? onToggleFavorite,
  }) {
    final connected = controller.isConnected;
    final actions = <ActionItem>[];

    if (onRename != null) {
      actions.add(
        ActionItem(icon: Icons.edit_outlined, label: 'Rename', onTap: onRename),
      );
    }
    if (onDuplicate != null) {
      actions.add(
        ActionItem(
          icon: Icons.copy_outlined,
          label: 'Duplicate',
          onTap: onDuplicate,
        ),
      );
    }
    if (onToggleFavorite != null) {
      final isFav = k.favorite;
      actions.add(
        ActionItem(
          icon: isFav ? Icons.star_rounded : Icons.star_outline_rounded,
          label: isFav ? 'Unstar' : 'Star',
          onTap: onToggleFavorite,
        ),
      );
    }

    if (k.state == ArchiveKeyState.deleted) {
      actions.add(
        ActionItem(
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
        ),
      );
    }
    if (!k.isDeleted && k.category.emulatable) {
      actions.add(
        ActionItem(
          icon: Icons.play_arrow,
          label: 'Emulate',
          onTap: () => emulateOnFlipper(context, k),
        ),
      );
    }
    if (canShowOnMap) {
      actions.add(
        ActionItem(
          icon: Icons.map_outlined,
          label: 'Map',
          onTap: () => _openOnMap(context, k),
        ),
      );
    } else if (k.inLocal && (k.localPath?.isNotEmpty ?? false)) {
      actions.add(
        ActionItem(
          icon: Icons.add_location_alt_outlined,
          label: 'Map',
          onTap: () => _pickLocation(context, k),
        ),
      );
    }
    if (k.onDevice && connected) {
      actions.add(
        ActionItem(
          icon: Icons.folder_open,
          label: 'Reveal',
          onTap: () => _openInFileManager(context, k),
        ),
      );
      actions.add(
        ActionItem(
          icon: Icons.edit_note,
          label: 'Edit',
          onTap: () => _openInEditor(context, k),
        ),
      );
    }
    final shareIcon = isShareSupported ? Icons.ios_share : Icons.content_copy;
    final shareLabel = isShareSupported ? 'Share' : 'Copy';
    final hasLocal = k.inLocal && (k.localPath?.isNotEmpty ?? false);
    if (hasLocal) {
      actions.add(
        ActionItem(
          icon: shareIcon,
          label: shareLabel,
          onTap: () =>
              shareLocalFile(context, k.localPath!, displayName: k.name),
        ),
      );
    } else if (k.onDevice && connected) {
      actions.add(
        ActionItem(
          icon: shareIcon,
          label: shareLabel,
          onTap: () => _shareFromDevice(context, k),
        ),
      );
    }

    actions.add(
      ActionItem(
        icon: Icons.delete_forever,
        label: 'Delete',
        destructive: true,
        onTap: () => _confirmAndDelete(context, controller, k, connected),
      ),
    );

    return actions;
  }

  /// Opens [k] on the connected Flipper. Public so the file manager can reuse
  /// the exact same emulation entry point for matching files.
  static void emulateOnFlipper(BuildContext context, ArchiveKey k) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EmulatePage(flipperKey: k)));
  }

  static void _openInEditor(BuildContext context, ArchiveKey k) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TextEditorPage(remotePath: k.remotePath),
      ),
    );
  }

  static void _shareFromDevice(BuildContext context, ArchiveKey k) {
    final remoteParent = _parent(k.remotePath);
    shareRemoteFile(
      context,
      FileManagerController(initialPath: remoteParent),
      k.remotePath,
      displayName: k.name,
    );
  }

  static void _openInFileManager(BuildContext context, ArchiveKey k) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FileManagerPage(initialPath: _parent(k.remotePath)),
      ),
    );
  }

  static void _openOnMap(BuildContext context, ArchiveKey k) {
    final path = k.localPath;
    if (path == null || path.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FlipperMapPage(focusPinPath: path)),
    );
  }

  static void _pickLocation(BuildContext context, ArchiveKey k) {
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

  static String _parent(String path) {
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return '/';
    return path.substring(0, idx);
  }

  static Future<void> _confirmAndDelete(
    BuildContext context,
    ArchiveController controller,
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
        title: Text(
          'Delete ${k.name}?',
          style: TextStyle(color: colors.dialogText),
        ),
        content: Text(
          message,
          style: TextStyle(color: colors.dialogMuted, height: 1.4),
        ),
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

  static Future<bool> _hasCoordinates(ArchiveKey k) async {
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
