import 'package:flutter/material.dart';

import '../../theme.dart';
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
         badge: 'WIP',
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
      iconAsset: 'assets/flipper_svg/archive/ic_fileformat_sub.svg',
      iconColor: const Color(0xFFFF9B34),
      title: 'FlipperMap',
      compact: true,
      tool: ToolItemModel(
        title: 'FlipperMap',
        description: 'Show where files were written on Flipper storage',
        routeBuilder: _buildFlipperMapPage,
        badge: 'Beta',
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
