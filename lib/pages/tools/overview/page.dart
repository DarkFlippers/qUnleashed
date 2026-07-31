import 'dart:io';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../components/icon.dart';
import '../../../theme/theme.dart';
import '../../../components/dialogs/action.dart';
import '../../about/page.dart';
import '../../asembler/controller.dart';
import '../../asembler/project/page.dart';
import '../../option/page.dart';
import '../paint/manager/page.dart';
import '../remote/desktop/page.dart';
import '../remote/cli/page.dart';
import '../infrared/categories_page.dart';
import '../../archive/map/page.dart';
import '../mifare/mfkey32_page.dart';
import '../plotter/page.dart';
import 'models/tool.dart';
import 'widgets/app_version.dart';
import 'widgets/tool_item_badge.dart';
import 'widgets/tool_item_text.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  static final List<ToolGroup> _tools = [
    ToolGroup(
      header: const ToolCardHeader(
        iconAsset: 'assets/ic/device/flipper.svg',
        iconColor: Color(0xFF589DFF),
        title: 'Device control',
      ),
      items: [
        ToolItemModel(
          iconAsset: 'assets/ic/app/controller.svg',
          iconColor: const Color(0xFFFFFFFF),
          title: 'Remote desktop',
          description: 'View, control, and record the device screen',
          routeBuilder: _buildRemoteControlPage,
        ),
        if (!Platform.isIOS)
          ToolItemModel(
            iconAsset: 'assets/ic/app/cli.svg',
            iconColor: const Color(0xFFFF9B34),
            title: 'Command line',
            description: 'Open a terminal session on your device',
            onTap: _openCliPage,
          ),
        ToolItemModel(
          iconAsset: 'assets/ic/app/paint-large.svg',
          iconColor: const Color(0xFFE85858),
          title: 'Pixel Draw',
          description: 'Draw, manage projects and import dolphin animations',
          routeBuilder: _buildPaintPage,
        ),
      ],
    ),
    ToolGroup(
      header: const ToolCardHeader(
        iconAsset: 'assets/ic/app/apps.svg',
        iconColor: Color(0xFF4DB6AC),
        title: 'Apps',
      ),
      items: [
        if (AssemblerController.isSupported)
          ToolItemModel(
            iconAsset: 'assets/ic/fileformat/plugins.svg',
            iconColor: const Color(0xFF4DB6AC),
            title: 'Flibler',
            description: 'Build an app from a folder or repo',
            routeBuilder: _buildFliblerPage,
            badge: 'Beta',
          ),
      ],
    ),
    ToolGroup(
      header: const ToolCardHeader(
        iconAsset: 'assets/ic/app/files.svg',
        iconColor: Color(0xFF8BC34A),
        title: 'File utils',
      ),
      items: [
        ToolItemModel(
          iconAsset: 'assets/ic/fileformat/nfc.svg',
          iconColor: const Color(0xFF34C7A4),
          title: 'Extract MIFARE Keys',
          description: 'Calculate keys from Extract MF Keys',
          routeBuilder: _buildMfKey32Page,
          badge: 'Beta',
        ),
        ToolItemModel(
          iconAsset: 'assets/ic/fileformat/ir.svg',
          iconColor: const Color(0xFFAF52DE),
          title: 'Remotes Library',
          description: 'Find and save remotes for your devices',
          routeBuilder: _buildIrLibPage,
        ),
        ToolItemModel(
          iconAsset: 'assets/ic/app/sub-tools.svg',
          iconColor: const Color(0xFFFF9B34),
          title: 'Pulse Plotter',
          description: 'Visualize raw Sub-GHz/Infrared/RFID pulse captures',
          routeBuilder: _buildPlotterPage,
          badge: 'Beta',
        ),
        ToolItemModel(
          iconAsset: 'assets/ic/fileformat/sub.svg',
          iconColor: const Color(0xFF8BC34A),
          title: 'Saved Locations',
          description: 'View saved files by recording location',
          routeBuilder: _buildFlipperMapPage,
        ),
      ],
    ),
    ToolGroup(
      items: [
        ToolItemModel(
          iconAsset: 'assets/ic/fileformat/settings.svg',
          iconColor: const Color(0xFF9E9E9E),
          title: 'Settings',
          description: 'Notifications and app preferences',
          routeBuilder: _buildSettingsPage,
        ),
      ],
    ),
    ToolGroup(
      items: [
        ToolItemModel(
          iconAsset: 'assets/ic/info/lg.svg',
          iconColor: const Color(0xFF589DFF),
          title: 'About',
          description: 'Links, community and license',
          routeBuilder: _buildAboutPage,
        ),
      ],
    ),
  ];

  Widget _groupHeader(ToolCardHeader header, QAppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          QIcon(asset: header.iconAsset, color: header.iconColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              header.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolItem(BuildContext context, ToolItemModel item) {
    final colors = context.appColors;
    return Row(
      children: [
        QIconBadge(asset: item.iconAsset, color: item.iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: ToolItemText(title: item.title, description: item.description),
        ),
        if (item.badge != null) ToolItemBadge(label: item.badge!),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: QIcon(
            asset: 'assets/ic/nav/navigate-tool.svg',
            color: colors.textMuted,
            size: 16,
          ),
        ),
      ],
    );
  }

  VoidCallback? _resolveTap(BuildContext context, ToolItemModel item) {
    final onTap = item.onTap;
    if (onTap != null) return () => onTap(context);
    final routeBuilder = item.routeBuilder;
    if (routeBuilder != null) {
      return () =>
          Navigator.of(context).push(MaterialPageRoute(builder: routeBuilder));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ColoredBox(
      color: colors.background,
      child: SafeArea(
        left: false,
        right: false,
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 9, bottom: 14),
          child: Column(
            children: [
              for (final group in _tools)
                if (group.items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: GroupedCardList<ToolItemModel>(
                      header: group.header == null
                          ? null
                          : _groupHeader(group.header!, colors),
                      items: group.items,
                      onTap: (item) => _resolveTap(context, item),
                      itemBuilder: _toolItem,
                    ),
                  ),
              const AppVersionLabel(),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildMfKey32Page(BuildContext context) => const MfKey32Page();

Widget _buildPlotterPage(BuildContext context) => const PulsePlotterPage();

Widget _buildFlipperMapPage(BuildContext context) => const FlipperMapPage();

Widget _buildIrLibPage(BuildContext context) => const IrCategoriesPage();

Widget _buildAboutPage(BuildContext context) => const AboutPage();

Widget _buildSettingsPage(BuildContext context) => const SettingsPage();

Widget _buildPaintPage(BuildContext context) => const ProjectManagerPage();

Widget _buildFliblerPage(BuildContext context) => const FliblerProjectPage();

Widget _buildRemoteControlPage(BuildContext context) =>
    const RemoteControlPage();

Future<void> _openCliPage(BuildContext context) async {
  final client = FlipperOneClient().get();
  final connectedDevice = client.connectedDevice;

  if (connectedDevice?.isBle == true) {
    final shouldContinue =
        await showDialog<bool>(
          context: context,
          barrierColor: context.appColors.dialogBarrier,
          builder: (dialogContext) {
            return FlipperActionDialog(
              imageAssetPath: kCliBluetoothUnavailableAssetPath,
              title: kCliBluetoothUnavailableTitle,
              text: kCliBluetoothUnavailableMessage,
              actionText: kCliBluetoothUnavailableAction,
              onAction: () => Navigator.of(dialogContext).pop(true),
            );
          },
        ) ??
        false;
    if (!shouldContinue || !context.mounted) return;

    try {
      await client.disconnect();
    } catch (e) {
      LogService.log('[CLI] disconnect before terminal failed: $e');
      return;
    }

    if (!context.mounted) return;
  }

  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const CliPage()));
}
