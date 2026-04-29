import 'dart:async';

import 'package:flutter/material.dart';

import '../models/discovered_device.dart';
import '../pages/widgets/connection.dart';
import '../services/ble_service.dart';
import '../services/log_service.dart';
import '../services/usb_service.dart';
import '../widgets/device_shell.dart';
import 'device_info_screen.dart';

bool _isFlipperBle(BleDiscoveredDevice d) {
  final mac = d.id.replaceAll(':', '').toUpperCase();
  return mac.startsWith('80E127') || mac.startsWith('80E126');
}

bool _isFlipperUsb(UsbDiscoveredDevice d) {
  if (d is DesktopUsbDiscoveredDevice) {
    if (d.vendorId == 0x0483) return true;

    final desc = d.description.toLowerCase();
    return desc.contains('stmicroelectronics') ||
        desc.contains('virtual com port') ||
        desc.contains('flipper');
  }
  if (d is AndroidUsbDiscoveredDevice) return d.usbDevice.vid == 0x0483;
  return false;
}

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  FlipperRootTab _tab = FlipperRootTab.device;

  Future<void> _openPicker() async {
    final selected = await showConnectionDialog(context);
    if (selected != null && mounted) _connectTo(selected);
  }

  Future<void> _connectTo(DiscoveredDevice dev) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Connecting...'),
          ],
        ),
      ),
    );
    try {
      final connected = await dev.connect();
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DeviceInfoScreen(device: connected)),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      LogService.log('[DeviceList] connection failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlipperRootScaffold(
      currentTab: _tab,
      onTabSelected: (tab) => setState(() => _tab = tab),
      deviceIconAsset: 'assets/flipper_svg/connection/ic_no_device_filled.svg',
      deviceLabel: 'No device',
      child: IndexedStack(
        index: _tab.index,
        children: [
          _DisconnectedDevicePage(onConnect: _openPicker),
          const _PlaceholderPage(title: 'Archive'),
          const _PlaceholderPage(title: 'Apps'),
          const _PlaceholderPage(title: 'Tools'),
        ],
      ),
    );
  }
}

class _DisconnectedDevicePage extends StatelessWidget {
  const _DisconnectedDevicePage({required this.onConnect});

  final VoidCallback onConnect;
  static const double _headerContentHeight = 114;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final headerHeight = topInset + _headerContentHeight;
    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            padding: EdgeInsets.only(top: headerHeight + 14, bottom: 14),
            children: [
              FlipperPageCard(
                title: 'Firmware Update',
                child: Column(
                  children: [
                    const FlipperInfoLine(
                      label: 'Update Channel',
                      value: 'Connect',
                      valueColor: FlipperOriginalColors.text30,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Container(
                        width: double.infinity,
                        height: 44,
                        decoration: BoxDecoration(
                          color: FlipperOriginalColors.text16,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'UPDATE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const FlipperPageCard(
                title: 'Device Info',
                child: Column(
                  children: [
                    FlipperInfoLine(label: 'Firmware Version', value: '-'),
                    Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'Build Date', value: '-'),
                    Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'SD Card (Used/Total)', value: '-'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                child: Column(
                  children: [
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/core/ic_bluetooth.svg',
                      label: 'Connect',
                      color: FlipperOriginalColors.blue,
                      onTap: onConnect,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: FlipperOriginalColors.accent,
            padding: EdgeInsets.only(top: topInset),
            height: headerHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 18, bottom: 7),
                  child: SizedBox(
                    height: 100,
                    child: const FlipperMockupWidget(active: false),
                  ),
                ),
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'No device',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: FlipperOriginalColors.card,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Flipper Zero',
                      style: TextStyle(
                        fontSize: 12,
                        color: FlipperOriginalColors.card,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          color: FlipperOriginalColors.text60,
        ),
      ),
    );
  }
}
