import 'package:flutter/material.dart';

import '../../components/cardlist.dart';
import '../../components/icon.dart';
import '../../theme/theme.dart';
import 'notifications_page.dart';
import 'storage_page.dart';
import 'theme_page.dart';

class _Category {
  const _Category({
    required this.title,
    required this.subtitle,
    required this.asset,
    required this.color,
    required this.page,
  });

  final String title;
  final String subtitle;
  final String asset;
  final Color color;
  final WidgetBuilder page;
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

  VoidCallback _open(BuildContext context, WidgetBuilder page) =>
      () => Navigator.of(context).push(MaterialPageRoute(builder: page));

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: colors.background,
        surfaceTintColor: colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          GroupedCardList<_Category>(
            items: [
              _Category(
                title: 'Notifications',
                subtitle: 'App and firmware releases',
                asset: 'assets/ic/app/bell.svg',
                color: const Color(0xFFE85858),
                page: (_) => const NotificationsSettingsPage(),
              ),
            ],
            onTap: (c) => _open(context, c.page),
            itemBuilder: _tile,
          ),
          const SizedBox(height: 10),
          GroupedCardList<_Category>(
            items: [
              _Category(
                title: 'Storage',
                subtitle: 'SD card, internal storage',
                asset: 'assets/ic/storage/sd.svg',
                color: const Color(0xFF8BC34A),
                page: (_) => const StorageSettingsPage(),
              ),
              _Category(
                title: 'Theme',
                subtitle: 'Firmware, system, dark or light',
                asset: 'assets/ic/app/paint.svg',
                color: const Color(0xFFB388FF),
                page: (_) => const ThemeSettingsPage(),
              ),
            ],
            onTap: (c) => _open(context, c.page),
            itemBuilder: _tile,
          ),
        ],
      ),
    );
  }
}
