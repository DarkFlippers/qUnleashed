import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';
import '../../models/device_info.dart';
import 'summary_card.dart';

class StorageSummaryCard extends StatelessWidget {
  const StorageSummaryCard({super.key, required this.deviceInfo});

  final Map<String, String> deviceInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final usedBytes = DeviceInfoReader.number(deviceInfo, const [
      'storage.sdcard.used_bytes',
      'storage.sdcard.used',
    ]);
    final totalBytes = DeviceInfoReader.number(deviceInfo, const [
      'storage.sdcard.total_bytes',
      'storage.sdcard.total',
    ]);
    final free = DeviceInfoReader.str(deviceInfo, const ['storage.sdcard.free']);
    final used = DeviceInfoReader.str(deviceInfo, const ['storage.sdcard.used']);
    final internal = DeviceInfoReader.str(deviceInfo, const [
      'storage.internal.used',
    ]);
    final percent = usedBytes != null && totalBytes != null && totalBytes > 0
        ? (usedBytes / totalBytes * 100).clamp(0.0, 100.0)
        : DeviceInfoReader.number(deviceInfo, const [
            'storage.sdcard.used_percent',
          ]);

    return SummaryCard(
      title: 'Storage',
      icon: Icons.storage,
      mainValue: percent,
      barValue: percent != null ? percent / 100 : null,
      barColor: percent != null && percent > 90 ? colors.danger : colors.accent,
      metrics: [
        ('Used', used ?? '0 B'),
        ('Free', free ?? '0 B'),
        ('/int', internal ?? '0 B'),
      ],
    );
  }
}
