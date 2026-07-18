import 'package:flutter/material.dart';

import '../../theme/theme.dart';
// import 'connected_devices_page.dart';
import 'notifications_page.dart';
import 'storage_page.dart';
import 'theme_page.dart';
import 'widgets/settings_group.dart';
import 'widgets/settings_tile.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _open(BuildContext context, WidgetBuilder builder) {
    Navigator.of(context).push(MaterialPageRoute(builder: builder));
  }

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
          SettingsGroup(
            children: [
              SettingsCategoryTile(
                title: 'Notifications',
                subtitle: 'App and firmware releases',
                asset: 'assets/ic/app/bell.svg',
                color: const Color(0xFFE85858),
                onTap: () =>
                    _open(context, (_) => const NotificationsSettingsPage()),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SettingsGroup(
            children: [
              // SettingsCategoryTile(
              //   title: 'Connected devices',
              //   subtitle: 'Bluetooth, USB, known devices',
              //   asset: 'assets/ic/device/flipper.svg',
              //   color: const Color(0xFF589DFF),
              //   onTap: () =>
              //       _open(context, (_) => const ConnectedDevicesSettingsPage()),
              // ),
              SettingsCategoryTile(
                title: 'Storage',
                subtitle: 'SD card, internal storage',
                asset: 'assets/ic/storage/sd.svg',
                color: const Color(0xFF8BC34A),
                onTap: () => _open(context, (_) => const StorageSettingsPage()),
              ),
              SettingsCategoryTile(
                title: 'Theme',
                subtitle: 'Firmware, system, dark or light',
                asset: 'assets/ic/app/paint.svg',
                color: const Color(0xFFB388FF),
                onTap: () => _open(context, (_) => const ThemeSettingsPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
