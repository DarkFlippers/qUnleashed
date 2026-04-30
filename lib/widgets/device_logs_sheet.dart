import 'package:flutter/material.dart';

import '../theme.dart';
import 'device_shell.dart';

void showDeviceLogsSheet(
  BuildContext context, {
  required List<String> logs,
  required VoidCallback onClear,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.appColors.transparent,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.92,
      minChildSize: 0.45,
      builder: (context, controller) => DeviceLogsSheet(
        controller: controller,
        logs: logs,
        onClear: onClear,
      ),
    ),
  );
}

class DeviceLogsSheet extends StatelessWidget {
  const DeviceLogsSheet({
    super.key,
    required this.controller,
    required this.logs,
    required this.onClear,
  });

  final ScrollController controller;
  final List<String> logs;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: colors.divider,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
            child: Row(
              children: [
                Text(
                  'Logs',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onClear,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          Expanded(
            child: FlipperPageCard(
              child: logs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'No logs yet.',
                          style: TextStyle(color: colors.textMuted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.all(12),
                      itemCount: logs.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SelectableText(
                          _normalizeLine(logs[i]),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.4,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  static String _normalizeLine(String line) {
    return line.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }
}
