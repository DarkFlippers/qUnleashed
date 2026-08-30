import 'dart:io' as io;

import 'package:dartufbt/dartufbt.dart';
import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../components/format.dart';
import '../../../components/icon.dart';
import '../../../services/http/app_http.dart';
import '../../../services/localization/l10n.dart';
import '../../../services/storage/paths.dart';
import '../../../services/storage/fap_icons.dart';
import '../../../theme/theme.dart';
import '../../../components/notification.dart';
import '../../../services/assembler/controller.dart';

class _StorageArea {
  const _StorageArea({
    required this.group,
    required this.title,
    required this.subtitle,
    required this.resolve,
    this.clear,
  });

  final String group;
  final String title;
  final String subtitle;
  final Future<io.Directory> Function() resolve;

  /// Set when clearing needs more than wiping the folder, as for the SDK that
  /// also has to reset the assembler status.
  final Future<void> Function()? clear;
}

const _groupFlibler = 'Flibler (ufbt)';

Future<void> _clearUfbtSdk() async {
  await clearDirectory(UfbtPaths.resolve().currentSdkDir);
  AssemblerController.instance.refreshStatus();
}

Future<void> _clearUfbtToolchain() async {
  await clearDirectory(UfbtPaths.resolve().toolchainDir);
  AssemblerController.instance.refreshStatus();
}

List<_StorageArea> _buildAreas(L10n s) => [
  _StorageArea(
    group: s.storageGroupAppFolders,
    title: s.storageDeviceData,
    subtitle: s.storageDeviceDataSubtitle,
    resolve: appDevicesDirectory,
  ),
  _StorageArea(
    group: s.storageGroupAppFolders,
    title: s.storageScreenshots,
    subtitle: s.storageScreenshotsSubtitle,
    resolve: appScreenshotsDirectory,
  ),
  _StorageArea(
    group: s.storageGroupAppFolders,
    title: s.storageRecordings,
    subtitle: s.storageRecordingsSubtitle,
    resolve: appRecordingsDirectory,
  ),
  _StorageArea(
    group: s.storageGroupAppFolders,
    title: s.storageAnimations,
    subtitle: s.storageAnimationsSubtitle,
    resolve: appAnimationsDirectory,
  ),
  _StorageArea(
    group: s.storageGroupAppFolders,
    title: s.storageIrLibrary,
    subtitle: s.storageIrLibrarySubtitle,
    resolve: irLibRepositoryDirectory,
  ),
  _StorageArea(
    group: s.storageGroupAppFolders,
    title: 'All-the-plugins',
    subtitle: s.storageAllThePluginsSubtitle,
    resolve: atpRepositoryDirectory,
  ),
  _StorageArea(
    group: s.storageGroupInternal,
    title: s.storageAppIconCache,
    subtitle: s.storageAppIconCacheSubtitle,
    resolve: fapIconRepoDirectory,
  ),
  _StorageArea(
    group: s.storageGroupInternal,
    title: s.storageNetworkCache,
    subtitle: s.storageNetworkCacheSubtitle,
    resolve: AppHttp.httpCacheDirectory,
  ),
  _StorageArea(
    group: s.storageGroupInternal,
    title: s.storageShareCache,
    subtitle: s.storageShareCacheSubtitle,
    resolve: shareCacheDirectory,
  ),
  if (AssemblerController.isSupported) ...[
    _StorageArea(
      group: _groupFlibler,
      title: s.storageFirmwareSdk,
      subtitle: s.storageFirmwareSdkSubtitle,
      resolve: () async => UfbtPaths.resolve().currentSdkDir,
      clear: _clearUfbtSdk,
    ),
    _StorageArea(
      group: _groupFlibler,
      title: s.storageArmToolchain,
      subtitle: s.storageArmToolchainSubtitle,
      resolve: () async => UfbtPaths.resolve().toolchainDir,
      clear: _clearUfbtToolchain,
    ),
  ],
];

List<String> _buildGroups(L10n s) => [
  s.storageGroupAppFolders,
  s.storageGroupInternal,
  if (AssemblerController.isSupported) _groupFlibler,
];

class StorageSettingsPage extends StatefulWidget {
  const StorageSettingsPage({super.key});

  @override
  State<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends State<StorageSettingsPage> {
  final Map<int, int?> _sizes = {};
  final Set<int> _clearing = {};

  List<_StorageArea> get _areas => _buildAreas(l10n);

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
            title: Text(
              ctx.l10n.storageClearTitle(area.title.toLowerCase()),
            ),
            content: Text(ctx.l10n.storageClearBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  ctx.l10n.commonClear,
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
      final clear = area.clear;
      if (clear != null) {
        await clear();
      } else {
        await clearDirectory(await area.resolve());
      }
      if (mounted) {
        context.showNotification(
          context.l10n.storageCleared(area.title),
          type: QNotificationType.good,
        );
      }
    } catch (e) {
      if (mounted) {
        context.showNotification(
          context.l10n.storageClearFailed('$e'),
          type: QNotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _clearing.remove(index));
      await _refreshSizes();
    }
  }

  Widget _tile(BuildContext context, int index) {
    final colors = context.appColors;
    final area = _areas[index];
    final size = _sizes[index];
    final clearing = _clearing.contains(index);
    return Row(
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
          size == null ? '…' : formatBytesScaled(size, topUnitPrecision: 2),
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
            onPressed: (size ?? 0) > 0 ? () => _clearArea(index) : null,
            icon: QIcon(
              asset: 'assets/ic/action/trash.svg',
              color: (size ?? 0) > 0 ? colors.danger : colors.textMuted,
              size: 18,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(context.l10n.settingsStorageTitle),
        backgroundColor: colors.background,
        surfaceTintColor: colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          for (final group in _buildGroups(context.l10n)) ...[
            GroupedCardList<int>(
              title: group,
              items: [
                for (var i = 0; i < _areas.length; i++)
                  if (_areas[i].group == group) i,
              ],
              itemBuilder: _tile,
            ),
            if (group != _buildGroups(context.l10n).last)
              const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
