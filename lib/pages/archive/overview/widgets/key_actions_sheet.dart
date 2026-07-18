import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../components/icon.dart';
import '../../../../theme/theme.dart';
import '../../../../widgets/notification.dart';
import '../../editor/page.dart';
import '../../../tools/paint/editor/page.dart';
import '../../../tools/plotter/page.dart';
import '../../data/models/pin.dart';
import '../../map/page.dart';
import '../controller.dart';
import '../../emulate/page.dart';
import '../../browser/page.dart';
import '../../browser/share_remote_file.dart';
import '../../data/models/key.dart';
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

    final leading = QIconBadge(
      asset: key.category.asset,
      color: key.category.color,
      iconSize: 22,
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
                'Connect a device to restore',
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
    if (!k.isDeleted && k.category.plottable) {
      actions.add(
        ActionItem(
          icon: Icons.show_chart,
          label: 'Plotter',
          onTap: () => _openInPlotter(context, controller, k),
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
    if (hasLocal || (k.onDevice && connected)) {
      actions.add(
        ActionItem(
          icon: Icons.download_outlined,
          label: 'Download',
          onTap: () => _download(context, controller, k),
        ),
      );
    }
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
          onTap: () => _shareFromDevice(context, controller, k),
        ),
      );
    }

    actions.addAll(deleteActions(context, controller, [k]));

    return actions;
  }

  /// The single source of truth for the "Delete local" / "Delete remote"
  /// actions, shared by the single-file menu and the multi-select sheet. Each
  /// button is shown only when it applies to [keys] and runs its own
  /// confirmation before deleting; [onDone] fires after a confirmed delete.
  static List<ActionItem> deleteActions(
    BuildContext context,
    ArchiveController controller,
    List<ArchiveKey> keys, {
    VoidCallback? onDone,
  }) {
    final canDeleteLocal = keys.any((k) => k.hasLocalFile);
    final canDeleteRemote =
        controller.isConnected && keys.any((k) => !k.isDeleted);
    return [
      if (canDeleteLocal)
        ActionItem(
          icon: Icons.phonelink_erase_outlined,
          label: 'Delete local',
          destructive: true,
          onTap: () => _confirmAndDelete(
            context,
            controller,
            keys,
            local: true,
            remote: false,
            onDone: onDone,
          ),
        ),
      if (canDeleteRemote)
        ActionItem(
          icon: Icons.delete_forever,
          label: 'Delete remote',
          destructive: true,
          onTap: () => _confirmAndDelete(
            context,
            controller,
            keys,
            local: false,
            remote: true,
            onDone: onDone,
          ),
        ),
    ];
  }

  /// Opens [k] on the connected Flipper. Public so the file manager can reuse
  /// the exact same emulation entry point for matching files.
  static void emulateOnFlipper(BuildContext context, ArchiveKey k) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EmulatePage(flipperKey: k)));
  }

  static Future<void> _openInPlotter(
    BuildContext context,
    ArchiveController controller,
    ArchiveKey k,
  ) async {
    List<int>? bytes;
    final localPath = k.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      final file = io.File(localPath);
      if (await file.exists()) bytes = await file.readAsBytes();
    }
    if (bytes == null && k.onDevice && controller.isConnected) {
      bytes = await controller.readKeyBytes(k);
    }
    if (!context.mounted) return;
    if (bytes == null) {
      context.showNotification(
        'Could not read ${k.fileName}',
        type: QNotificationType.error,
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PulsePlotterPage(
          initialBytes: Uint8List.fromList(bytes!),
          initialName: k.fileName,
        ),
      ),
    );
  }

  static void _openInEditor(BuildContext context, ArchiveKey k) {
    if (const {'png', 'gif', 'bm'}.contains(k.extension.toLowerCase())) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PaintPage(remotePath: k.remotePath)),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TextEditorPage(remotePath: k.remotePath),
      ),
    );
  }

  static Future<void> _shareFromDevice(
    BuildContext context,
    ArchiveController controller,
    ArchiveKey k,
  ) async {
    final path = await controller.downloadKeyToCache(k);
    if (!context.mounted) return;
    if (path == null) {
      context.showNotification(
        'Download failed',
        type: QNotificationType.error,
      );
      return;
    }
    await shareLocalFile(context, path, displayName: k.name);
  }

  static Future<void> _download(
    BuildContext context,
    ArchiveController controller,
    ArchiveKey k,
  ) async {
    List<int>? bytes;
    final localPath = k.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      final file = io.File(localPath);
      if (await file.exists()) bytes = await file.readAsBytes();
    }
    if (bytes == null && k.onDevice && controller.isConnected) {
      bytes = await controller.readKeyBytes(k);
    }
    if (!context.mounted) return;
    if (bytes == null) {
      context.showNotification(
        'Download failed',
        type: QNotificationType.error,
      );
      return;
    }

    String? savedPath;
    try {
      savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ${k.fileName}',
        fileName: k.fileName,
        bytes: Uint8List.fromList(bytes),
      );
    } catch (e) {
      if (context.mounted) {
        context.showNotification(
          'Saving is not supported on this platform',
          type: QNotificationType.error,
        );
      }
      return;
    }
    if (savedPath == null) return;
    final isDesktop =
        io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS;
    if (isDesktop) {
      await io.File(savedPath).writeAsBytes(bytes, flush: true);
    }
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
    List<ArchiveKey> keys, {
    required bool local,
    required bool remote,
    VoidCallback? onDone,
  }) async {
    if (keys.isEmpty) return;
    final colors = context.appColors;
    final where = local ? 'this phone' : 'the device';
    final title = keys.length == 1
        ? 'Delete ${keys.first.name} from $where?'
        : 'Delete ${keys.length} files from $where?';
    final message = local
        ? 'Permanently deleted from this phone. Copies on the device are kept.'
        : 'Permanently deleted from the device. Local copies on this phone are kept.';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.dialogBackground,
        title: Text(title, style: TextStyle(color: colors.dialogText)),
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
      await controller.deleteKeys(keys, local: local, remote: remote);
      onDone?.call();
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
