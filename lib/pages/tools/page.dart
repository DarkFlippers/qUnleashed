import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/flipper_action_dialog.dart';
import 'about/page.dart';
import 'cli/cli_page.dart';
import 'irlib/categories_page.dart';
import 'map/page.dart';
import 'mifare/mfkey32_page.dart';
import 'models/tool.dart';
import 'widgets/tool.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  static final _tools = [
    ToolCardModel(
      iconAsset: 'assets/flipper_svg/archive/ic_fileformat_nfc.svg',
      iconColor: const Color(0xFF34C7A4),
      title: 'MIFARE Classic',
      tool: ToolItemModel(
        preview: ToolPreviewType.mfKey,
        title: 'Mfkey32 (Extract MF Keys)',
        description: 'Calculate keys from Extract MF Keys',
        routeBuilder: _buildMfKey32Page,
        badge: 'Beta',
      ),
    ),
    ToolCardModel(
      iconAsset: 'assets/flipper_svg/archive/ic_fileformat_ir.svg',
      iconColor: const Color(0xFFAF52DE),
      title: 'Infrared',
      tool: ToolItemModel(
        preview: ToolPreviewType.remoteLibrary,
        title: 'Remotes Library',
        description:
            'Find and save remotes for your devices from a wide range of brands and models',
        routeBuilder: _buildIrLibPage,
        badge: 'Beta',
      ),
    ),
    ToolCardModel(
      iconAsset: 'assets/flipper_svg/tools/ic_settings_gear.svg',
      iconColor: const Color(0xFFE85858),
      title: 'Flibler',
      tool: ToolItemModel(
        preview: ToolPreviewType.flibler,
        title: 'Flipper app assembler',
        description:
            'Build Flipper Zero apps from source projects or simple block-based app templates using uFBT',
        badge: 'Soon',
      ),
    ),
    ToolCardModel(
      iconAsset: 'assets/flipper_svg/archive/ic_fileformat_sub.svg',
      iconColor: const Color(0xFF8BC34A),
      title: 'Saved Locations',
      compact: true,
      tool: ToolItemModel(
        title: 'Saved Locations',
        description: 'View saved files by recording location',
        routeBuilder: _buildFlipperMapPage,
      ),
    ),
    ToolCardModel(
      iconAsset: 'assets/flipper_svg/archive/ic_fileformat_badusb.svg',
      iconColor: const Color(0xFFFF9B34),
      title: 'Command-line interface',
      compact: true,
      tool: ToolItemModel(
        title: 'Command-line interface',
        description: 'Open a terminal session with your Flipper Zero',
        onTap: _openCliPage,
      ),
    ),
    ToolCardModel(
      iconAsset: 'assets/apps/app_placeholder.svg',
      iconColor: const Color(0xFF589DFF),
      title: 'About',
      compact: true,
      tool: ToolItemModel(
        title: 'About',
        description: 'Links, community and license',
        routeBuilder: _buildAboutPage,
      ),
    ),
  ];

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
              for (final tool in _tools) ToolCard(model: tool),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildMfKey32Page(BuildContext context) => const MfKey32Page();

Widget _buildFlipperMapPage(BuildContext context) => const FlipperMapPage();

Widget _buildIrLibPage(BuildContext context) => const IrCategoriesPage();

Widget _buildAboutPage(BuildContext context) => const AboutPage();

Future<void> _openCliPage(BuildContext context) async {
  final client = FlipperOneClient().get();
  final connectedDevice = client.connectedDevice;

  if (connectedDevice?.isBle == true) {
    final shouldContinue = await showDialog<bool>(
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

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const CliPage()),
  );
}
