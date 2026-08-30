import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../action_row.dart';
import '../info_line.dart';
import '../navigate_icon.dart';
import 'summary_card.dart';

class DeviceInfoCard extends StatelessWidget {
  const DeviceInfoCard({
    super.key,
    required this.entries,
    required this.onOpenFullInfo,
    required this.onExport,
  });

  final List<MapEntry<String, String>> entries;
  final VoidCallback onOpenFullInfo;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DashboardCard(
      title: context.l10n.deviceInfoTitle,
      icon: Icons.info_outline,
      trailing: InkWell(
        onTap: onOpenFullInfo,
        child: DeviceNavigateIcon(color: colors.textMuted),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                FlipperInfoLine(label: entries[i].key, value: entries[i].value),
                if (i != entries.length - 1)
                  Divider(height: 1, color: colors.divider),
              ],
            ],
          ),
          Divider(height: 1, color: colors.divider),
          FlipperActionRow(
            iconAsset: 'assets/ic/nav/navigate.svg',
            label: context.l10n.deviceFullInfo,
            color: colors.accent,
            onTap: onOpenFullInfo,
          ),
          Divider(height: 1, color: colors.divider),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onExport,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(Icons.copy, color: colors.accent, size: 20),
                    ),
                    Expanded(
                      child: Text(
                        context.l10n.deviceExport,
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
