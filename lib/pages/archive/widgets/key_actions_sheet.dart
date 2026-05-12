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

class KeyActionsSheet extends StatelessWidget {
  const KeyActionsSheet({
    super.key,
    required this.controller,
    required this.flipperKey,
  });

  final ArchiveController controller;
  final ArchiveKey flipperKey;

  static Future<void> show(
    BuildContext context,
    ArchiveController controller,
    ArchiveKey key,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).extension<QAppColors>()!.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => KeyActionsSheet(controller: controller, flipperKey: key),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasCoordinates(flipperKey),
      builder: (context, snapshot) {
        return _buildSheet(context, snapshot.data ?? false);
      },
    );
  }

  Widget _buildSheet(BuildContext context, bool canShowOnMap) {
    final colors = context.appColors;
    final k = flipperKey;
    final connected = controller.isConnected;

    final actions = <_Action>[];
    if (k.state == ArchiveKeyState.remoteOnly && connected) {
      actions.add(_Action(
        icon: Icons.download,
        label: 'Save to phone',
        onTap: () => controller.rememberKey(k),
      ));
    }
    if (k.state == ArchiveKeyState.deleted) {
      actions.add(_Action(
        icon: Icons.restore,
        label: 'Restore to Flipper',
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
        label: 'Open on device',
        onTap: () => _emulateOnFlipper(context, k),
      ));
    }
    if (canShowOnMap) {
      actions.add(_Action(
        icon: Icons.map_outlined,
        label: 'Show on map',
        onTap: () => _openOnMap(context, k),
      ));
    } else if (k.inLocal && (k.localPath?.isNotEmpty ?? false)) {
      actions.add(_Action(
        icon: Icons.add_location_alt_outlined,
        label: 'Set location',
        onTap: () => _pickLocation(context, k),
      ));
    }
    if (k.onDevice && connected) {
      actions.add(_Action(
        icon: Icons.edit_note,
        label: 'Open in editor',
        onTap: () => _openInEditor(context, k),
      ));
      actions.add(_Action(
        icon: Icons.folder_open,
        label: 'Open in file manager',
        onTap: () => _openInFileManager(context, k),
      ));
    }

    actions.add(_Action(
      icon: Icons.delete_forever,
      label: 'Delete permanently',
      destructive: true,
      onTap: () => _confirmAndDelete(context, k, connected),
    ));

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                    colorFilter:
                        ColorFilter.mode(k.category.color, BlendMode.srcIn),
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
          for (final a in actions)
            ListTile(
              leading: Icon(
                a.icon,
                color: a.destructive ? colors.danger : colors.textPrimary,
              ),
              title: Text(
                a.label,
                style: TextStyle(
                  color: a.destructive ? colors.danger : colors.textPrimary,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                a.onTap();
              },
            ),
          const SizedBox(height: 8),
        ],
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
    final navigator = Navigator.of(context);
    navigator.push(
      MaterialPageRoute(
        builder: (_) => TextEditorPage(
          controller: FileManagerController(initialPath: remoteParent),
          remotePath: k.remotePath,
        ),
      ),
    );
  }

  void _openInFileManager(BuildContext context, ArchiveKey k) {
    final navigator = Navigator.of(context);
    navigator.push(
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

class _Action {
  _Action({required this.icon, required this.label, required this.onTap, this.destructive = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}
