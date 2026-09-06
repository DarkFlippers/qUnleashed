import 'package:flutter/material.dart';

import '../../components/cardlist.dart';
import '../../components/icon.dart';
import '../../components/navigation.dart';
import '../../services/home_widget/service.dart';
import '../../services/localization/l10n.dart';
import '../../theme/theme.dart';
import 'pages/apps.dart';
import 'pages/device.dart';
import 'pages/flibler.dart';
import 'pages/language.dart';
import 'pages/map.dart';
import 'pages/push.dart';
import 'pages/storage.dart';
import 'pages/theme.dart';
import 'pages/widgets.dart';

class _Category {
  const _Category({
    required this.title,
    required this.subtitle,
    required this.asset,
    required this.color,
    this.page,
    this.route,
  }) : assert(page != null || route != null);

  final String title;
  final String subtitle;
  final String asset;
  final Color color;

  /// Screen owned by this feature; screens of other features go through [route].
  final WidgetBuilder? page;
  final AppRoute? route;
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Widget _tile(BuildContext context, _Category c) {
    final colors = context.appColors;
    return Row(
      children: [
        QIconBadge(asset: c.asset, color: c.color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                c.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                c.subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
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

  VoidCallback _open(BuildContext context, _Category category) {
    final page = category.page;
    if (page == null) {
      return () => openRoute(context, category.route!);
    }
    return () => Navigator.of(context).push(MaterialPageRoute(builder: page));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(context.l10n.settingsTitle),
        backgroundColor: colors.background,
        surfaceTintColor: colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          GroupedCardList<_Category>(
            items: [
              _Category(
                title: context.l10n.settingsDeviceTitle,
                subtitle: context.l10n.settingsDeviceSubtitle,
                asset: 'assets/ic/device/flipper.svg',
                color: const Color(0xFFFF8A65),
                page: (_) => const DeviceSettingsPage(),
              ),
              _Category(
                title: context.l10n.settingsNotificationsTitle,
                subtitle: context.l10n.settingsNotificationsSubtitle,
                asset: 'assets/ic/app/bell.svg',
                color: const Color(0xFFE85858),
                page: (_) => const NotificationsSettingsPage(),
              ),
              _Category(
                title: context.l10n.settingsLanguageTitle,
                subtitle: context.l10n.settingsLanguageSubtitle,
                asset: 'assets/ic/app/language.svg',
                color: const Color(0xFFFFB74D),
                page: (_) => const LanguageSettingsPage(),
              ),
            ],
            onTap: (c) => _open(context, c),
            itemBuilder: _tile,
          ),
          const SizedBox(height: 10),
          GroupedCardList<_Category>(
            items: [
              _Category(
                title: context.l10n.settingsStorageTitle,
                subtitle: context.l10n.settingsStorageSubtitle,
                asset: 'assets/ic/storage/sd.svg',
                color: const Color(0xFF8BC34A),
                page: (_) => const StorageSettingsPage(),
              ),
              _Category(
                title: context.l10n.settingsThemeTitle,
                subtitle: context.l10n.settingsThemeSubtitle,
                asset: 'assets/ic/app/paint.svg',
                color: const Color(0xFFB388FF),
                page: (_) => const ThemeSettingsPage(),
              ),
              _Category(
                title: context.l10n.settingsMapTitle,
                subtitle: context.l10n.settingsMapSubtitle,
                asset: 'assets/ic/fileformat/sub.svg',
                color: const Color(0xFF4FC3F7),
                page: (_) => const MapSettingsPage(),
              ),
              if (HomeWidgetService.instance.supported)
                _Category(
                  title: context.l10n.settingsWidgetsTitle,
                  subtitle: context.l10n.settingsWidgetsSubtitle,
                  asset: 'assets/ic/fileformat/favorites.svg',
                  color: const Color(0xFF34C7A4),
                  page: (_) => const WidgetSettingsPage(),
                ),
            ],
            onTap: (c) => _open(context, c),
            itemBuilder: _tile,
          ),
          const SizedBox(height: 10),
          GroupedCardList<_Category>(
            items: [
              _Category(
                title: context.l10n.settingsAppsTitle,
                subtitle: context.l10n.settingsAppsSubtitle,
                asset: 'assets/ic/app/apps.svg',
                color: const Color(0xFF5C9BE8),
                page: (_) => const AppsSettingsPage(),
              ),
              _Category(
                title: 'Flibler',
                subtitle: context.l10n.settingsFliblerSubtitle,
                asset: 'assets/ic/fileformat/settings.svg',
                color: const Color(0xFF4DB6AC),
                page: (_) => const AssemblerSettingsPage(),
              ),
            ],
            onTap: (c) => _open(context, c),
            itemBuilder: _tile,
          ),
        ],
      ),
    );
  }
}
