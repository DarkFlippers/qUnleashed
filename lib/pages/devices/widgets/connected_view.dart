import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets/action_row.dart';
import '../../../widgets/info_line.dart';
import '../../../widgets/page_card.dart';
import 'navigate_icon.dart';
import 'firmware_carousel_card.dart';
import 'page_header.dart';

class ConnectedDeviceView extends StatelessWidget {
  const ConnectedDeviceView({
    super.key,
    required this.deviceName,
    required this.infoLoading,
    required this.deviceInfo,
    required this.deviceInfoEntries,
    required this.connectionLabel,
    required this.connectionIcon,
    required this.onSynchronize,
    required this.onPlayAlert,
    required this.onOpenRemoteControl,
    required this.onOpenFullInfo,
    required this.onExport,
    required this.onDisconnect,
  });

  final String deviceName;
  final bool infoLoading;
  final Map<String, String> deviceInfo;
  final List<MapEntry<String, String>> deviceInfoEntries;
  final String connectionLabel;
  final IconData connectionIcon;
  final VoidCallback? onSynchronize;
  final VoidCallback? onPlayAlert;
  final VoidCallback onOpenRemoteControl;
  final VoidCallback onOpenFullInfo;
  final VoidCallback onExport;
  final VoidCallback onDisconnect;

  static const double _headerContentHeight = 114;
  static const double _contentMaxWidth = 1120;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 560;
              final headerHeight = topInset + _headerContentHeight;
              final contentPadding = EdgeInsets.only(
                top: headerHeight + 14,
                bottom: 14,
              );
              return ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: ListView(
                  padding: contentPadding,
                  children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _contentMaxWidth,
                      ),
                      child: Column(
                        children: [
                          FirmwareCarouselCard(
                            deviceVersion: deviceInfoEntries.isEmpty
                                ? '-'
                                : deviceInfoEntries.first.value,
                            deviceInfo: deviceInfo,
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: _ResponsiveCardGrid(
                              minCardWidth: 300,
                              children: [
                                _BatterySummaryCard(
                                  infoLoading: infoLoading,
                                  deviceInfo: deviceInfo,
                                ),
                                _StorageSummaryCard(
                                  infoLoading: infoLoading,
                                  deviceInfo: deviceInfo,
                                ),
                              ],
                            ),
                          ),
                          if (!wide) ...[
                            const SizedBox(height: 14),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: _DeviceInfoCard(
                                entries: deviceInfoEntries,
                                onOpenFullInfo: onOpenFullInfo,
                                onExport: onExport,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          _RemoteControlCard(
                            onOpenRemoteControl: onOpenRemoteControl,
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: _ResponsiveCardGrid(
                              minCardWidth: 300,
                              children: [
                                _ActionsCard(
                                  onSynchronize: onSynchronize,
                                  onPlayAlert: onPlayAlert,
                                ),
                                _ConnectionActionsCard(
                                  onDisconnect: onDisconnect,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ],
                ),
              );
            },
          ),
        ),
        DevicePageHeader(
          topInset: topInset,
          headerHeight: topInset + _headerContentHeight,
          title: deviceName,
          subtitle: 'Flipper Zero',
          active: true,
          infoEntries: MediaQuery.sizeOf(context).width >= 580
              ? deviceInfoEntries
              : const [],
          deviceInfo: deviceInfo,
          connectionLabel: connectionLabel,
          connectionIcon: connectionIcon,
          onOpenFullInfo: onOpenFullInfo,
        ),
      ],
    );
  }
}

class _ResponsiveCardGrid extends StatelessWidget {
  const _ResponsiveCardGrid({required this.children, this.minCardWidth = 300});

  final List<Widget> children;
  final double minCardWidth;
  static const double _spacing = 14;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minCardWidth).floor().clamp(
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
    required this.infoLoading,
    required this.emptyText,
    required this.metrics,
    this.mainValue,
    this.barValue,
    this.barColor,
    this.statusText,
    this.statusColor,
  });

  final String title;
  final IconData icon;
  final bool infoLoading;
  final String emptyText;
  final List<(String, String)> metrics;
  final double? mainValue;
  final double? barValue;
  final Color? barColor;
  final String? statusText;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _DashboardCard(
      title: title,
      icon: icon,
      child: infoLoading && mainValue == null
          ? const _LoadingRows()
          : mainValue == null
          ? _EmptyCardText(emptyText)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      mainValue!.round().toString(),
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
                        value: (barValue ?? mainValue! / 100).clamp(0.0, 1.0),
                        color: barColor ?? colors.accent,
                      ),
                    ),
                  ],
                ),
                if (statusText != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    statusText!,
                    style: TextStyle(
                      color: statusColor ?? colors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
  const _BatterySummaryCard({
    required this.infoLoading,
    required this.deviceInfo,
  });

  final bool infoLoading;
  final Map<String, String> deviceInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final charge = _numberValue(deviceInfo, const [
      'power.charge_level',
      'power.charge',
      'charge_level',
      'charge',
    ]);
    final voltage = _numberValue(deviceInfo, const [
      'power.battery_voltage',
      'power.voltage_gauge',
      'power.voltage',
    ]);
    final current = _numberValue(deviceInfo, const [
      'power.battery_current',
      'power.current_gauge',
      'power.current',
    ]);
    final temp = _numberValue(deviceInfo, const [
      'power.battery_temp',
      'power.temperature_gauge',
      'power.temperature',
    ]);
    final charging = current != null && current > 5;

    return _SummaryCard(
      title: 'Battery',
      icon: charging ? Icons.battery_charging_full : Icons.battery_full,
      infoLoading: infoLoading,
      emptyText: 'No battery data',
      mainValue: charge,
      barValue: charge != null ? charge / 100 : null,
      barColor: charge == null
          ? null
          : charge < 20
          ? colors.danger
          : charge < 50
          ? colors.accent
          : colors.success,
      statusText: charging ? 'Charging' : null,
      statusColor: colors.success,
      metrics: [
        ('Voltage', voltage == null ? '-' : '${(voltage * 0.001).toStringAsFixed(3)} V'),
        ('Current', current == null ? '-' : '${current.round()} mA'),
        ('Temp', temp == null ? '-' : '${temp.toStringAsFixed(1)} C'),
      ],
    );
  }
}

class _StorageSummaryCard extends StatelessWidget {
  const _StorageSummaryCard({
    required this.infoLoading,
    required this.deviceInfo,
  });

  final bool infoLoading;
  final Map<String, String> deviceInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final usedBytes = _numberValue(deviceInfo, const [
      'storage.sdcard.used_bytes',
      'storage.sdcard.used',
    ]);
    final totalBytes = _numberValue(deviceInfo, const [
      'storage.sdcard.total_bytes',
      'storage.sdcard.total',
    ]);
    final free = _firstValue(deviceInfo, const ['storage.sdcard.free']);
    final used = _firstValue(deviceInfo, const ['storage.sdcard.used']);
    final internal = _firstValue(deviceInfo, const ['storage.internal.used']);
    final percent = usedBytes != null && totalBytes != null && totalBytes > 0
        ? (usedBytes / totalBytes * 100).clamp(0.0, 100.0)
        : _numberValue(deviceInfo, const ['storage.sdcard.used_percent']);

    return _SummaryCard(
      title: 'Storage',
      icon: Icons.storage,
      infoLoading: infoLoading,
      emptyText: 'No storage data',
      mainValue: percent,
      barValue: percent != null ? percent / 100 : null,
      barColor: percent != null && percent > 90 ? colors.danger : colors.accent,
      metrics: [
        ('Used', used ?? '-'),
        ('Free', free ?? '-'),
        ('/int', internal ?? '-'),
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
        value: value.clamp(0, 1),
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

class _LoadingRows extends StatelessWidget {
  const _LoadingRows();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      children: [
        for (var i = 0; i < 3; i++) ...[
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: colors.divider,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          if (i != 2) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _EmptyCardText extends StatelessWidget {
  const _EmptyCardText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: TextStyle(color: context.appColors.textMuted, fontSize: 12),
      ),
    );
  }
}

String? _firstValue(Map<String, String> info, List<String> aliases) {
  for (final alias in aliases) {
    final value = info[alias];
    if (value != null && value.trim().isNotEmpty && value != '-') {
      return value;
    }
  }
  return null;
}

double? _numberValue(Map<String, String> info, List<String> aliases) {
  final raw = _firstValue(info, aliases);
  if (raw == null) return null;
  final sanitized = raw.replaceAll('%', '').replaceAll(',', '.').trim();
  final number = double.tryParse(sanitized);
  if (number == null || !number.isFinite) return null;
  return number;
}
