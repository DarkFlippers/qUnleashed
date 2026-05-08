import 'package:flutter/material.dart';

import '../../theme.dart';
import 'mifare/mfkey32_page.dart';
import 'models/tool.dart';
import 'widgets/tool.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  static final _tools = [
    ToolCardModel(
      iconAsset: 'assets/flipper_svg/tools/ic_fileformat_nfc.svg',
      title: 'MIFARE Classic',
      tool: ToolItemModel(
        preview: ToolPreviewType.mfKey,
        title: 'Mfkey32 (Extract MF Keys)',
        description: 'Calculate keys from Extract MF Keys',
        routeBuilder: _buildMfKey32Page,
      ),
    ),
    ToolCardModel(
      iconAsset: 'assets/flipper_svg/tools/ic_fileformat_ir.svg',
      title: 'Infrared',
      tool: ToolItemModel(
        preview: ToolPreviewType.remoteLibrary,
        title: 'Remotes Library',
        description:
            'Find and save remotes for your devices from a wide range of brands and models',
        badge: 'Beta',
      ),
    ),
    ToolCardModel(
      iconAsset: 'assets/flipper_svg/tools/ic_fileformat_sub.svg',
      title: 'FlipperMap',
      tool: ToolItemModel(
        preview: ToolPreviewType.fileMap,
        title: 'FlipperMap',
        description: 'Show where files were written on Flipper storage',
        badge: 'Soon',
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
          padding: const EdgeInsets.only(bottom: 14),
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
