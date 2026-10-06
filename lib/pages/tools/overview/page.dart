import '../../../services/localization/l10n.dart';

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../components/icon.dart';
import '../../../components/navigation.dart';
import '../../../theme/theme.dart';
import '../../../services/assembler/controller.dart';
import '../paint/manager/page.dart';
import '../remote/desktop/page.dart';
import '../remote/cli/page.dart';
import '../infrared/categories_page.dart';
import '../mifare/recover_page.dart';
import '../subghz/seed/seed_page.dart';
import '../plotter/page.dart';
import 'models/tool.dart';
import 'widgets/app_version.dart';
import 'widgets/tool_item_badge.dart';
import 'widgets/tool_item_text.dart';
import '../../devices/device_scope.dart';
import '../../../services/connection/link_service.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  /// [localReady] is whether this computer can compile right now, which is
  /// what `ensureReady` enforces - not which backend the catalog is using.
  /// Flibler has no server path, so pinning the server or a catalog build
  /// faulting leaves it working; it used to take the entry point with it. #248
  static List<ToolGroup> _toolGroups(L10n s, bool localReady) => [
    ToolGroup(
      header: ToolCardHeader(
        iconAsset: 'assets/ic/device/flipper.svg',
        iconColor: const Color(0xFF589DFF),
        title: s.toolsGroupDeviceControl,
      ),
      items: [
        ToolItemModel(
          iconAsset: 'assets/ic/app/controller.svg',
          iconColor: const Color(0xFFFFFFFF),
          title: s.toolRemoteDesktop,
          description: s.toolRemoteDesktopSubtitle,
          routeBuilder: _buildRemoteControlPage,
        ),
        if (!Platform.isIOS)
          ToolItemModel(
            iconAsset: 'assets/ic/app/cli.svg',
            iconColor: const Color(0xFFFF9B34),
            title: s.toolCommandLine,
            description: s.toolCommandLineSubtitle,
            onTap: _openCliPage,
          ),
        ToolItemModel(
          iconAsset: 'assets/ic/app/paint-large.svg',
          iconColor: const Color(0xFFE85858),
          title: s.toolPixelDraw,
          description: s.toolPixelDrawSubtitle,
          routeBuilder: _buildPaintPage,
        ),
      ],
    ),
    if (AssemblerController.isSupported)
      ToolGroup(
        header: ToolCardHeader(
          iconAsset: 'assets/ic/app/apps.svg',
          iconColor: const Color(0xFF4DB6AC),
          title: s.toolsGroupApps,
        ),
        items: [
          ToolItemModel(
            iconAsset: 'assets/ic/fileformat/plugins.svg',
            iconColor: const Color(0xFF4DB6AC),
            title: 'Flibler',
            // Not ready is worth saying rather than hiding: the page links to
            // the assembler settings, and deploying the SDK brings it back.
            description: localReady
                ? s.toolFliblerSubtitle
                : s.toolFliblerNeedsSdk,
            onTap: _openFliblerPage,
            badge: s.toolBadgeBeta,
          ),
        ],
      ),
    ToolGroup(
      header: ToolCardHeader(
        iconAsset: 'assets/ic/app/files.svg',
        iconColor: const Color(0xFF8BC34A),
        title: s.toolsGroupFileUtils,
      ),
      items: [
        ToolItemModel(
          iconAsset: 'assets/ic/fileformat/nfc.svg',
          iconColor: const Color(0xFF34C7A4),
          title: s.toolMifare,
          description: s.toolMifareSubtitle,
          routeBuilder: _buildRecoverPage,
          badge: s.toolBadgeBeta,
        ),
        ToolItemModel(
          iconAsset: 'assets/ic/fileformat/sub.svg',
          iconColor: const Color(0xFFFF9B34),
          title: s.toolSeedRecovery,
          description: s.toolSeedRecoverySubtitle,
          routeBuilder: _buildSeedPage,
          badge: s.toolBadgeBeta,
        ),
        ToolItemModel(
          iconAsset: 'assets/ic/fileformat/ir.svg',
          iconColor: const Color(0xFFAF52DE),
          title: s.toolRemotesLibrary,
          description: s.toolRemotesLibrarySubtitle,
          routeBuilder: _buildIrLibPage,
        ),
        ToolItemModel(
          iconAsset: 'assets/ic/app/sub-tools.svg',
          iconColor: const Color(0xFFFF9B34),
          title: s.toolPulsePlotter,
          description: s.toolPulsePlotterSubtitle,
          routeBuilder: _buildPlotterPage,
          badge: s.toolBadgeBeta,
        ),
        ToolItemModel(
          iconAsset: 'assets/ic/fileformat/sub.svg',
          iconColor: const Color(0xFF8BC34A),
          title: s.toolSavedLocations,
          description: s.toolSavedLocationsSubtitle,
          onTap: _openFlipperMapPage,
        ),
      ],
    ),
    ToolGroup(
      items: [
        ToolItemModel(
          iconAsset: 'assets/ic/fileformat/settings.svg',
          iconColor: const Color(0xFF9E9E9E),
          title: s.settingsTitle,
          description: s.toolSettingsSubtitle,
          onTap: _openSettingsPage,
        ),
      ],
    ),
    ToolGroup(
      items: [
        ToolItemModel(
          iconAsset: 'assets/ic/info/lg.svg',
          iconColor: const Color(0xFF589DFF),
          title: s.aboutTitle,
          description: s.toolAboutSubtitle,
          onTap: _openAboutPage,
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
          child: AnimatedBuilder(
            animation: AssemblerController.instance,
            builder: (context, _) => Column(
              children: [
                for (final group in _toolGroups(
                  context.l10n,
                  AssemblerController.instance.localReady,
                ))
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
      ),
    );
  }
}

Widget _buildRecoverPage(BuildContext context) =>
    RecoverPage(client: DeviceScope.of(context).client);

Widget _buildSeedPage(BuildContext context) =>
    SeedPage(client: DeviceScope.of(context).client);

Widget _buildPlotterPage(BuildContext context) => const PulsePlotterPage();

Future<void> _openFlipperMapPage(BuildContext context) async {
  await openRoute(context, AppRoute.archiveMap);
}

Widget _buildIrLibPage(BuildContext context) => const IrCategoriesPage();

Future<void> _openAboutPage(BuildContext context) async {
  await openRoute(context, AppRoute.about);
}

Future<void> _openSettingsPage(BuildContext context) async {
  await openRoute(context, AppRoute.appSettings);
}

Widget _buildPaintPage(BuildContext context) =>
    ProjectManagerPage(client: DeviceScope.of(context).client);

Future<void> _openFliblerPage(BuildContext context) async {
  await openRoute(context, AppRoute.fliblerProject);
}

Widget _buildRemoteControlPage(BuildContext context) =>
    RemoteControlPage(client: DeviceScope.of(context).client);

Future<void> _openCliPage(BuildContext context) async {
  final client = DeviceScope.of(context).client;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CliPage(client: client, links: LinkService.instance),
    ),
  );
}
