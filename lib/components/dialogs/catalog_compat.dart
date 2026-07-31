import 'package:flutter/material.dart';

import '../../theme/theme.dart';

class CatalogCompatDialog extends StatelessWidget {
  const CatalogCompatDialog({
    super.key,
    required this.deviceApi,
    required this.serverApi,
    required this.compatApi,
    required this.onBuildFromSource,
    required this.onIgnoreAndContinue,
    required this.onDecline,
  });

  final String? deviceApi;
  final String? serverApi;
  final String? compatApi;
  final VoidCallback onBuildFromSource;
  final VoidCallback onIgnoreAndContinue;
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
            'The catalog has no builds for your firmware API. Pick how to '
            'proceed:',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.dialogText, fontSize: 13),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Column(
          children: [
            _CompatAction(
              primary: true,
              label: 'Compatibility mode - build from source',
              description:
                  'Downloads the app source bundle instead of a ready FAP '
                  'and compiles it locally for your firmware. Needs a '
                  'one-time SDK download, desktop only.',
              onPressed: onBuildFromSource,
            ),
            const SizedBox(height: 8),
            _CompatAction(
              label: compatApi != null
                  ? 'Ignore the warning and continue (API $compatApi)'
                  : 'Ignore the warning and continue',
              description:
                  'Installs builds made for another API. Such apps may '
                  'misbehave or fail to launch at all.',
              onPressed: onIgnoreAndContinue,
            ),
            const SizedBox(height: 8),
            _CompatAction(
              label: 'Apps manager only',
              description:
                  'Keeps the catalog closed, you can still manage apps '
                  'already installed on the device.',
              onPressed: onDecline,
            ),
          ],
        ),
      ],
    );
  }
}

class _CompatAction extends StatelessWidget {
  const _CompatAction({
    required this.label,
    required this.description,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final String description;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        primary
            ? FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(label, textAlign: TextAlign.center),
              )
            : OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.dialogMuted,
                  side: BorderSide(color: colors.dialogDivider),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(label, textAlign: TextAlign.center),
              ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.dialogMuted,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
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
