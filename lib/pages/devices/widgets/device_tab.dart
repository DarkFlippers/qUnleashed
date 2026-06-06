import 'package:flutter/material.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../../../services/update/update_service.dart';
import '../../../theme.dart';
import '../../../widgets/action_row.dart';
import '../../../widgets/flipper_action_dialog.dart';
import '../../../widgets/info_line.dart';
import '../../../widgets/notification.dart';
import '../../../widgets/page_card.dart';
import '../../remote/page.dart';
import '../scope.dart';
import 'connection_dialog.dart';
import 'firmware_carousel_card.dart';
import 'full_info_sheet.dart';
import 'navigate_icon.dart';
import 'page_header.dart';

class DeviceTab extends StatelessWidget {
  const DeviceTab({super.key});

  static const double _headerContentHeight = 114;
  static const double _contentMaxWidth = 1120;

  @override
  Widget build(BuildContext context) {
    final ctrl = DeviceScope.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final headerHeight = topInset + _headerContentHeight;
    final wide = MediaQuery.sizeOf(context).width >= 560;

    return Stack(
      children: [
        Positioned.fill(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: RefreshIndicator(
              onRefresh: () => _onRefresh(context),
              edgeOffset: headerHeight,
              displacement: 28,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: headerHeight + 14, bottom: 14),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _contentMaxWidth,
                      ),
                      child: Column(
                        children: [
                          // Always in tree — preserves carousel state across
                          // connect/disconnect without rebuilding.
                          FirmwareCarouselCard(
                            deviceVersion: ctrl.firmwareVersion,
                            deviceInfo: ctrl.info,
                          ),
                          // Fade between connected content and disconnected
                          // connect button; no re-layout jump.
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: ctrl.isConnected
                                ? _ConnectedContent(
                                    key: const ValueKey(true),
                                    wide: wide,
                                  )
                                : const _DisconnectedContent(
                                    key: ValueKey(false),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        DevicePageHeader(
          topInset: topInset,
          headerHeight: headerHeight,
          title: ctrl.deviceName,
          subtitle: 'Flipper Zero',
          active: ctrl.isConnected,
          infoEntries: wide ? ctrl.deviceInfoEntries : const [],
          deviceInfo: ctrl.info,
          connectionLabel: ctrl.device?.isBle == true ? 'BLE' : 'USB',
          connectionIcon:
              ctrl.device?.isBle == true ? Icons.bluetooth : Icons.usb,
          onOpenFullInfo:
              ctrl.isConnected ? () => _openFullInfo(context) : null,
        ),
      ],
    );
  }

  static Future<void> _onRefresh(BuildContext context) async {
    DeviceScope.of(context).synchronize();
    await UpdateService.instance.refresh();
  }

  static void _openFullInfo(BuildContext context) {
    final ctrl = DeviceScope.of(context);
    showDeviceFullInfoSheet(
      context,
      title: 'Full Info',
      cards: [
        FlipperPageCard(
          title: 'Firmware',
          child: Column(
            children: [
              for (var i = 0; i < ctrl.deviceInfoEntries.length; i++) ...[
                FlipperInfoLine(
                  label: ctrl.deviceInfoEntries[i].key,
                  value: ctrl.deviceInfoEntries[i].value,
                ),
                if (i != ctrl.deviceInfoEntries.length - 1)
                  Divider(height: 1, color: context.appColors.divider),
              ],
            ],
          ),
        ),
        RawInfoCard(entries: ctrl.info),
      ],
    );
  }
}

// ── Connected content ─────────────────────────────────────────────────────────

class _ConnectedContent extends StatelessWidget {
  const _ConnectedContent({super.key, required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final ctrl = DeviceScope.of(context);

    return Column(
      children: [
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _ResponsiveCardGrid(
            children: [
              _BatterySummaryCard(deviceInfo: ctrl.info),
              _StorageSummaryCard(deviceInfo: ctrl.info),
            ],
          ),
        ),
        if (!wide) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _DeviceInfoCard(
              entries: ctrl.deviceInfoEntries,
              onOpenFullInfo: () => DeviceTab._openFullInfo(context),
              onExport: () => _exportDeviceInfo(context),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _RemoteControlCard(
          onOpenRemoteControl: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RemoteControlPage()),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _ResponsiveCardGrid(
            children: [
              _ActionsCard(
                onSynchronize: ctrl.deviceLoading
                    ? null
                    : () => ctrl.synchronize(),
                onPlayAlert: ctrl.alertPlaying
                    ? null
                    : () => _playAlert(context),
              ),
              _ConnectionActionsCard(
                onDisconnect: () => ctrl.disconnect(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  static Future<void> _playAlert(BuildContext context) async {
    final ctrl = DeviceScope.of(context);
    final success = await ctrl.playAlert();
    if (!context.mounted) return;
    context.showNotification(
      success ? 'Alert sent to Flipper' : 'Failed to play alert',
      type: success ? QNotificationType.good : QNotificationType.error,
    );
  }

  static Future<void> _exportDeviceInfo(BuildContext context) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      if (!context.mounted) return;
      context.showNotification(
        'Clipboard not available',
        type: QNotificationType.warning,
      );
      return;
    }
    final ctrl = DeviceScope.of(context);
    final item = DataWriterItem()
      ..add(Formats.plainText(ctrl.buildExportDump()));
    await clipboard.write([item]);
    if (!context.mounted) return;
    context.showNotification(
      'Device info copied to clipboard',
      type: QNotificationType.good,
    );
  }
}

// ── Disconnected content ──────────────────────────────────────────────────────

class _DisconnectedContent extends StatelessWidget {
  const _DisconnectedContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 14),
        FlipperPageCard(
          child: _ConnectActionRow(
            color: context.appColors.accent,
            onTap: () => _openPicker(context),
          ),
        ),
      ],
    );
  }

  static Future<void> _openPicker(BuildContext context) async {
    // Avoid calling showConnectionDialog when context is stale.
    if (!context.mounted) return;
    final selected = await showConnectionDialog(context);
    if (selected == null || !context.mounted) return;

    final ctrl = DeviceScope.of(context);
    try {
      await ctrl.connect(selected);
    } catch (e) {
      if (!context.mounted) return;
      await _showConnectionFailedDialog(context, selected);
    }
  }

  static Future<void> _showConnectionFailedDialog(
    BuildContext context,
    dynamic device,
  ) async {
    final text = device.isBle
        ? 'Turn Bluetooth off and on in the Flipper Zero system menu, then connect again. Restart the app only if that does not help.'
        : 'Unplug the device and plug it back in, then connect again. Restart the app only if that does not help.';
    await showDialog<void>(
      context: context,
      barrierColor: context.appColors.dialogBarrier,
      builder: (ctx) => FlipperActionDialog(
        imageAssetPath:
            'assets/flipper_svg/tools/mifare/pic_shrug_black.svg',
        imageSize: const Size(147.5, 95.8),
        title: 'Connection failed',
        text: text,
        actionText: 'OK',
        onAction: () => Navigator.of(ctx).pop(),
      ),
    );
  }
}

class _ConnectActionRow extends StatelessWidget {
  const _ConnectActionRow({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: SizedBox(
                width: 44,
                height: 24,
                child: Row(
                  children: [
                    Icon(Icons.usb, size: 22, color: color),
                    const SizedBox(width: 2),
                    Icon(Icons.bluetooth, size: 20, color: color),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Text(
                'Connect',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared card widgets ───────────────────────────────────────────────────────

class _ResponsiveCardGrid extends StatelessWidget {
  const _ResponsiveCardGrid({required this.children});

  final List<Widget> children;
  static const double _spacing = 14;
  static const double _minCardWidth = 300;


  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            (constraints.maxWidth / _minCardWidth).floor().clamp(
              1,
              children.length,
            );
        final cardWidth =
            (constraints.maxWidth - (_spacing * (columns - 1))) / columns;
        if (columns == 1) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                SizedBox(width: double.infinity, child: children[i]),
                if (i != children.length - 1) const SizedBox(height: _spacing),
              ],
            ],
          );
        }
        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: [
            for (final child in children)
              SizedBox(width: cardWidth, child: child),
          ],
        );
      },
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: colors.accent),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 13),
            child,
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.icon,
    required this.metrics,
    this.mainValue,
    this.barValue,
    this.barColor,
  });

  final String title;
  final IconData icon;
  final List<(String, String)> metrics;
  final double? mainValue;
  final double? barValue;
  final Color? barColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final value = mainValue?.isFinite == true ? mainValue! : 0.0;
    final progress = barValue?.isFinite == true ? barValue! : value / 100;

    return _DashboardCard(
      title: title,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                value.round().toString(),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '%',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricBar(
                  value: progress.clamp(0.0, 1.0),
                  color: barColor ?? colors.accent,
                ),
              ),
            ],
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                for (final m in metrics)
                  Expanded(child: _Metric(label: m.$1, value: m.$2)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BatterySummaryCard extends StatelessWidget {
  const _BatterySummaryCard({required this.deviceInfo});

  final Map<String, String> deviceInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final charge = _number(deviceInfo, const [
      'power.charge_level',
      'power.charge',
      'charge_level',
      'charge',
    ]);
    final voltage = _number(deviceInfo, const [
      'power.battery_voltage',
      'power.voltage_gauge',
      'power.voltage',
    ]);
    final current = _number(deviceInfo, const [
      'power.battery_current',
      'power.current_gauge',
      'power.current',
    ]);
    final temp = _number(deviceInfo, const [
      'power.battery_temp',
      'power.temperature_gauge',
      'power.temperature',
    ]);
    final charging = current != null && current > 5;

    return _SummaryCard(
      title: 'Battery',
      icon: charging ? Icons.battery_charging_full : Icons.battery_full,
      mainValue: charge,
      barValue: charge != null ? charge / 100 : null,
      barColor: charge == null ? null : colors.accent,
      metrics: [
        ('Voltage', '${((voltage ?? 0) * 0.001).toStringAsFixed(3)} V'),
        ('Current', '${(current ?? 0).round()} mA'),
        ('Temp', '${(temp ?? 0).toStringAsFixed(1)} C'),
      ],
    );
  }
}

class _StorageSummaryCard extends StatelessWidget {
  const _StorageSummaryCard({required this.deviceInfo});

  final Map<String, String> deviceInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final usedBytes = _number(deviceInfo, const [
      'storage.sdcard.used_bytes',
      'storage.sdcard.used',
    ]);
    final totalBytes = _number(deviceInfo, const [
      'storage.sdcard.total_bytes',
      'storage.sdcard.total',
    ]);
    final free = _str(deviceInfo, const ['storage.sdcard.free']);
    final used = _str(deviceInfo, const ['storage.sdcard.used']);
    final internal = _str(deviceInfo, const ['storage.internal.used']);
    final percent = usedBytes != null && totalBytes != null && totalBytes > 0
        ? (usedBytes / totalBytes * 100).clamp(0.0, 100.0)
        : _number(deviceInfo, const ['storage.sdcard.used_percent']);

    return _SummaryCard(
      title: 'Storage',
      icon: Icons.storage,
      mainValue: percent,
      barValue: percent != null ? percent / 100 : null,
      barColor: percent != null && percent > 90 ? colors.danger : colors.accent,
      metrics: [
        ('Used', used ?? '0 B'),
        ('Free', free ?? '0 B'),
        ('/int', internal ?? '0 B'),
      ],
    );
  }
}

class _DeviceInfoCard extends StatelessWidget {
  const _DeviceInfoCard({
    required this.entries,
    required this.onOpenFullInfo,
    required this.onExport,
  });

  final List<MapEntry<String, String>> entries;
  final VoidCallback onOpenFullInfo;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _DashboardCard(
      title: 'Device Info',
      icon: Icons.info_outline,
      trailing: InkWell(
        onTap: onOpenFullInfo,
        child: DeviceNavigateIcon(color: colors.textMuted),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                FlipperInfoLine(label: entries[i].key, value: entries[i].value),
                if (i != entries.length - 1)
                  Divider(height: 1, color: colors.divider),
              ],
            ],
          ),
          Divider(height: 1, color: colors.divider),
          FlipperActionRow(
            iconAsset: 'assets/flipper_svg/core/ic_navigate.svg',
            label: 'Full Info',
            color: colors.accent,
            onTap: onOpenFullInfo,
          ),
          Divider(height: 1, color: colors.divider),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onExport,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(Icons.copy, color: colors.accent, size: 20),
                    ),
                    Expanded(
                      child: Text(
                        'Export',
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteControlCard extends StatelessWidget {
  const _RemoteControlCard({required this.onOpenRemoteControl});

  final VoidCallback onOpenRemoteControl;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return FlipperPageCard(
      child: Column(
        children: [
          FlipperActionRow(
            iconAsset: 'assets/flipper_svg/info/ic_controller.svg',
            label: 'Remote Control',
            color: colors.textPrimary,
            trailing: DeviceNavigateIcon(color: colors.textMuted),
            onTap: onOpenRemoteControl,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Control your Flipper Zero remotely via mobile phone',
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.onSynchronize, required this.onPlayAlert});

  final VoidCallback? onSynchronize;
  final VoidCallback? onPlayAlert;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          FlipperActionRow(
            iconAsset: 'assets/flipper_svg/core/ic_syncing.svg',
            label: 'Synchronize',
            color: onSynchronize == null ? colors.textMuted : colors.accent,
            onTap: onSynchronize,
          ),
          Divider(height: 1, color: colors.divider),
          FlipperActionRow(
            iconAsset: 'assets/flipper_svg/info/ic_ring.svg',
            label: 'Play Alert on Flipper',
            color: onPlayAlert == null ? colors.textMuted : colors.accent,
            onTap: onPlayAlert,
          ),
        ],
      ),
    );
  }
}

class _ConnectionActionsCard extends StatelessWidget {
  const _ConnectionActionsCard({required this.onDisconnect});

  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          FlipperActionRow(
            iconAsset: 'assets/flipper_svg/core/ic_bluetooth_disable.svg',
            label: 'Disconnect',
            color: colors.accent,
            onTap: onDisconnect,
          ),
          Divider(height: 1, color: colors.divider),
          FlipperActionRow(
            iconAsset: 'assets/flipper_svg/info/ic_disconnection.svg',
            label: 'Forget Flipper',
            color: colors.danger,
            onTap: null,
          ),
        ],
      ),
    );
  }
}

class _MetricBar extends StatelessWidget {
  const _MetricBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 8,
        backgroundColor: colors.divider,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ── Info helpers ──────────────────────────────────────────────────────────────

String? _str(Map<String, String> info, List<String> keys) {
  for (final k in keys) {
    final v = info[k];
    if (v != null && v.trim().isNotEmpty && v != '-') return v;
  }
  return null;
}

double? _number(Map<String, String> info, List<String> keys) {
  final raw = _str(info, keys);
  if (raw == null) return null;
  final n = double.tryParse(raw.replaceAll('%', '').replaceAll(',', '.').trim());
  if (n == null || !n.isFinite) return null;
  return n;
}
