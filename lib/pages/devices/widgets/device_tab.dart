import 'package:flutter/material.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../../../services/update/update_service.dart';
import '../../../theme/theme.dart';
import '../../../widgets/info_line.dart';
import '../../../widgets/notification.dart';
import '../../../widgets/page_card.dart';
import '../device_scope.dart';
import 'cards/battery_card.dart';
import 'cards/connect_card.dart';
import 'cards/device_actions_row.dart';
import 'cards/device_info_card.dart';
import 'cards/storage_card.dart';
import 'firmware_card.dart';
import 'full_info_sheet.dart';
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
                          FirmwareCard(
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
          connectionIcon: ctrl.device?.isBle == true
              ? Icons.bluetooth
              : Icons.usb,
          onOpenFullInfo: ctrl.isConnected
              ? () => _openFullInfo(context)
              : null,
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
              BatterySummaryCard(deviceInfo: ctrl.info),
              StorageSummaryCard(deviceInfo: ctrl.info),
            ],
          ),
        ),
        if (!wide) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: DeviceInfoCard(
              entries: ctrl.deviceInfoEntries,
              onOpenFullInfo: () => DeviceTab._openFullInfo(context),
              onExport: () => _exportDeviceInfo(context),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: DeviceActionsRow(
            onDisconnect: () => ctrl.disconnect(),
            onPlayAlert: ctrl.alertPlaying ? null : () => _playAlert(context),
            onReboot: () => ctrl.reboot(),
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
    return const Column(children: [SizedBox(height: 14), ConnectCard()]);
  }
}

class _ResponsiveCardGrid extends StatelessWidget {
  const _ResponsiveCardGrid({required this.children});

  final List<Widget> children;
  static const double _spacing = 14;
  static const double _minCardWidth = 300;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / _minCardWidth).floor().clamp(
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
