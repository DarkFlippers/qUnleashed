import 'package:flutter/material.dart';

import '../../theme.dart';
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
        description: 'Find and save remotes for your devices from a wide range of brands and models',
        routeBuilder: _buildIrLibPage,
        badge: 'Beta',
      ),
    ),
    ToolCardModel(
      iconAsset: 'assets/flipper_svg/archive/ic_file.svg',
      iconColor: const Color(0xFFFF9B34),
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
        routeBuilder: _buildCliPage,
        badge: 'Beta',
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

Widget _buildCliPage(BuildContext context) => const CliPage();

Widget _buildAboutPage(BuildContext context) => const AboutPage();
