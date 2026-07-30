import 'package:flutter/material.dart';

import '../../theme/theme.dart';

class CatalogCompatDialog extends StatelessWidget {
  const CatalogCompatDialog({
    super.key,
    required this.deviceApi,
    required this.serverApi,
    required this.compatApi,
    required this.onUseCompatibility,
    required this.onDecline,
  });

  final String? deviceApi;
  final String? serverApi;
  final String? compatApi;
  final VoidCallback onUseCompatibility;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AlertDialog(
      backgroundColor: colors.dialogBackground,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 56, color: Colors.amber.shade600),
          const SizedBox(height: 12),
          Text(
            'Catalog / firmware mismatch',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.dialogText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CatalogApiRow(
            label: 'Firmware API',
            value: deviceApi ?? '—',
            colors: colors,
          ),
          const SizedBox(height: 4),
          CatalogApiRow(
              label: 'Catalog API', value: serverApi ?? '—', colors: colors),
          const SizedBox(height: 14),
          Text(
            'The catalog has no builds for your firmware API. Apps installed '
            'in compatibility mode may work incorrectly or fail to launch.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.dialogText, fontSize: 13),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onUseCompatibility,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  compatApi != null
                      ? 'Use compatibility mode (API $compatApi)'
                      : 'Use compatibility mode',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onDecline,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.dialogMuted,
                  side: BorderSide(color: colors.dialogDivider),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Not now - apps manager only'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class CatalogIncompatibleDialog extends StatelessWidget {
  const CatalogIncompatibleDialog({
    super.key,
    required this.tooOld,
    required this.deviceApi,
    required this.serverApi,
    required this.onOpenManager,
    required this.onRecheck,
  });

  final bool tooOld;
  final String? deviceApi;
  final String? serverApi;
  final VoidCallback onOpenManager;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AlertDialog(
      backgroundColor: colors.dialogBackground,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            tooOld ? Icons.system_update : Icons.hourglass_top,
            size: 56,
            color: colors.dialogMuted,
          ),
          const SizedBox(height: 12),
          Text(
            'Catalog unavailable',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.dialogText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CatalogApiRow(
            label: 'Firmware API',
            value: deviceApi ?? '—',
            colors: colors,
          ),
          const SizedBox(height: 4),
          CatalogApiRow(
              label: 'Catalog API', value: serverApi ?? '—', colors: colors),
          const SizedBox(height: 14),
          Text(
            tooOld
                ? 'The firmware API is too old for the app catalog. Update '
                    'the firmware to use the catalog. Only the apps manager '
                    'is available, app updates are disabled.'
                : 'The firmware API is newer than the catalog supports. '
                    'Only the apps manager is available until the catalog '
                    'catches up, app updates are disabled.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.dialogText, fontSize: 13),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onOpenManager,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Open apps manager'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onRecheck,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.dialogMuted,
                  side: BorderSide(color: colors.dialogDivider),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Re-check compatibility'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class CatalogApiRow extends StatelessWidget {
  const CatalogApiRow({
    super.key,
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$label: ',
            style: TextStyle(color: colors.textPrimary, fontSize: 13)),
        Text(
          value,
          style: TextStyle(color: colors.accent, fontSize: 13),
        ),
      ],
    );
  }
}
