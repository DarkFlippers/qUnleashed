import 'package:flutter/material.dart';

import '../theme.dart';
import 'device_shell.dart';

void showDeviceFullInfoSheet(
  BuildContext context, {
  required String title,
  required List<Widget> cards,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.appColors.transparent,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.6,
      builder: (context, controller) {
        final colors = context.appColors;
        return Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: controller,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ...cards.expand((card) => [card, const SizedBox(height: 14)]),
            ],
          ),
        );
      },
    ),
  );
}

class RawInfoCard extends StatelessWidget {
  const RawInfoCard({
    super.key,
    required this.entries,
  });

  final Map<String, String> entries;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final sorted = entries.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return FlipperPageCard(
      title: 'Raw Data',
      child: sorted.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No data received.',
                style: TextStyle(fontSize: 14, color: colors.textMuted),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < sorted.length; i++) ...[
                  FlipperInfoLine(label: sorted[i].key, value: sorted[i].value),
                  if (i != sorted.length - 1) Divider(height: 1, color: colors.divider),
                ],
              ],
            ),
    );
  }
}
