import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/flipper_action_dialog.dart';
import '../about/page.dart';
import '../paint/page.dart';
import '../remote/page.dart';
import '../utils/cli/page.dart';
import '../utils/infrared/categories_page.dart';
import '../utils/map/page.dart';
import '../utils/mifare/mfkey32_page.dart';
import 'models/tool.dart';
import 'widgets/tool.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  static final List<ToolCardModel> _tools = [
    ToolCardGroup(
      header: const ToolCardHeader(
        iconAsset: 'assets/ic/device/flipper.svg',
        iconColor: Color(0xFF589DFF),
        title: 'Device control',
      ),
      items: [
        ToolItemModel(
          iconAsset: 'assets/ic/app/controller.svg',
          iconColor: const Color(0xFF589DFF),
          title: 'Remote desktop',
          description: 'View, control, and record the flipper screen',
          routeBuilder: _buildRemoteControlPage,
        ),
        ToolItemModel(
          iconAsset: 'assets/ic/app/cli.svg',
          iconColor: const Color(0xFFFF9B34),
          title: 'Command line',
          description: 'Open a terminal session on your flipper',
          onTap: _openCliPage,
        ),
        ToolItemModel(
          iconAsset: 'assets/ic/app/paint-large.svg',
          iconColor: const Color(0xFFE85858),
          title: 'Pixel Draw',
          description: 'Draw directly on the flipper display',
          routeBuilder: _buildPaintPage,
        ),
      ],
    ),
    ToolCardGroup(
      header: const ToolCardHeader(
        iconAsset: 'assets/ic/app/files.svg',
        iconColor: Color(0xFF8BC34A),
        title: 'File utils',
      ),
      items: [
        ToolItemModel(
          preview: ToolPreviewType.mfKey,
          title: 'Extract MIFARE Keys',
          description: 'Calculate keys from Extract MF Keys',
          routeBuilder: _buildMfKey32Page,
          badge: 'Beta',
        ),
        ToolItemModel(
          preview: ToolPreviewType.remoteLibrary,
          title: 'Remotes Library',
          description:
              'Find and save remotes for your devices from a wide range of brands and models',
          routeBuilder: _buildIrLibPage,
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
    ToolCard(
      iconAsset: 'assets/ic/info/lg.svg',
      iconColor: const Color(0xFF589DFF),
      title: 'About',
      description: 'Links, community and license',
      routeBuilder: _buildAboutPage,
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
            children: [for (final tool in _tools) ToolCardView(model: tool)],
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

Widget _buildPaintPage(BuildContext context) => const PaintPage();

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
