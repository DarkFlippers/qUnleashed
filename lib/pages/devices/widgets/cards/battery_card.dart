import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../../models/device_info.dart';
import 'summary_card.dart';

class BatterySummaryCard extends StatelessWidget {
  const BatterySummaryCard({super.key, required this.deviceInfo});

  final Map<String, String> deviceInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final charge = DeviceInfoReader.number(deviceInfo, const [
      'power.charge_level',
      'power.charge',
      'charge_level',
      'charge',
    ]);
    final voltage = DeviceInfoReader.number(deviceInfo, const [
      'power.battery_voltage',
      'power.voltage_gauge',
      'power.voltage',
    ]);
    final current = DeviceInfoReader.number(deviceInfo, const [
      'power.battery_current',
      'power.current_gauge',
      'power.current',
    ]);
    final temp = DeviceInfoReader.number(deviceInfo, const [
      'power.battery_temp',
      'power.temperature_gauge',
      'power.temperature',
    ]);
    final charging = current != null && current > 5;

    return SummaryCard(
      title: context.l10n.cardBattery,
      icon: charging ? Icons.battery_charging_full : Icons.battery_full,
      mainValue: charge,
      barValue: charge != null ? charge / 100 : null,
      barColor: charge == null ? null : colors.accent,
      metrics: [
        (context.l10n.cardBatteryVoltage, '${((voltage ?? 0) * 0.001).toStringAsFixed(3)} V'),
        (context.l10n.cardBatteryCurrent, '${(current ?? 0).round()} mA'),
        (context.l10n.cardBatteryTemp, '${(temp ?? 0).toStringAsFixed(1)} C'),
      ],
    );
  }
}
