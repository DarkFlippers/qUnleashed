import 'dart:io' as io;

import 'package:flutter/material.dart';

import '../../components/icon.dart';
import '../../services/repository/app.dart';
import '../../theme/theme.dart';
import '../../widgets/notification.dart';
import 'widgets/settings_group.dart';
import 'widgets/settings_tile.dart';

class _StorageArea {
  const _StorageArea({
    required this.title,
    required this.subtitle,
    required this.resolve,
  });

  final String title;
  final String subtitle;
  final Future<io.Directory> Function() resolve;
}

final List<_StorageArea> _areas = [
  _StorageArea(
    title: 'Device data',
    subtitle: 'Synced archive and app catalogs per device',
    resolve: appDevicesDirectory,
  ),
  _StorageArea(
    title: 'Screenshots',
    subtitle: 'Saved device screen captures',
    resolve: appScreenshotsDirectory,
  ),
  _StorageArea(
    title: 'Recordings',
    subtitle: 'Saved device screen recordings',
    resolve: appRecordingsDirectory,
  ),
  _StorageArea(
    title: 'Animations',
    subtitle: 'Pixel Draw projects and dolphin animations',
    resolve: appAnimationsDirectory,
  ),
  _StorageArea(
    title: 'IR library',
    subtitle: 'Downloaded infrared remotes repository',
    resolve: irLibRepositoryDirectory,
  ),
  _StorageArea(
    title: 'App icon cache',
    subtitle: 'Cached application icons',
    resolve: fapIconRepoDirectory,
  ),
  _StorageArea(
    title: 'Share cache',
    subtitle: 'Temporary files created for sharing',
    resolve: shareCacheDirectory,
  ),
];

class StorageSettingsPage extends StatefulWidget {
  const StorageSettingsPage({super.key});

  @override
  State<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends State<StorageSettingsPage> {
  final Map<int, int?> _sizes = {};
  final Set<int> _clearing = {};

  @override
  void initState() {
    super.initState();
    _refreshSizes();
  }

  Future<void> _refreshSizes() async {
    for (var i = 0; i < _areas.length; i++) {
      directorySize(await _areas[i].resolve()).then((size) {
        if (mounted) setState(() => _sizes[i] = size);
      });
    }
  }

  Future<void> _clearArea(int index) async {
    final area = _areas[index];
    final confirmed =
        await showDialog<bool>(
          context: context,
          barrierColor: context.appColors.dialogBarrier,
          builder: (ctx) => AlertDialog(
            title: Text('Clear ${area.title.toLowerCase()}?'),
            content: Text(
              'This permanently deletes everything inside this folder.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Clear',
                  style: TextStyle(color: ctx.appColors.danger),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _clearing.add(index));
    try {
      await clearDirectory(await area.resolve());
      if (mounted) {
        context.showNotification(
          '${area.title} cleared',
          type: QNotificationType.good,
        );
      }
    } catch (e) {
      if (mounted) {
        context.showNotification(
          'Failed to clear: $e',
          type: QNotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _clearing.remove(index));
      await _refreshSizes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Storage'),
        backgroundColor: colors.background,
        surfaceTintColor: colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          SettingsGroup(
            title: 'App folders',
            children: [
              for (var i = 0; i < _areas.length; i++)
                _StorageAreaTile(
                  area: _areas[i],
                  size: _sizes[i],
                  clearing: _clearing.contains(i),
                  onClear: () => _clearArea(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StorageAreaTile extends StatelessWidget {
  const _StorageAreaTile({
    required this.area,
    required this.size,
    required this.clearing,
    required this.onClear,
  });

  final _StorageArea area;
  final int? size;
  final bool clearing;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SettingsTileShell(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  area.title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  area.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            size == null ? '…' : formatBytes(size!),
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(width: 2),
          if (clearing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: (size ?? 0) > 0 ? onClear : null,
              icon: QIcon(
                asset: 'assets/ic/action/trash.svg',
                color: (size ?? 0) > 0 ? colors.danger : colors.textMuted,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GB';
}
