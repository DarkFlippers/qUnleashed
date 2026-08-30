import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../components/config.dart';
import '../../../../components/open_url.dart';
import '../../../../theme/theme.dart';

const String kOfwContributingUrl =
    'https://github.com/flipperdevices/flipper-application-catalog/blob/main/documentation/Contributing.md';
const String kAtpNewAppUrl =
    'https://github.com/xMasterX/all-the-plugins/issues/new?template=02_new_app.yml';

Color _firmwareColor(String shortName) => QAppConfig.firmware.firmwares
    .firstWhere((entry) => entry.shortName == shortName)
    .colors
    .primary;

class SubmitAppDialog extends StatelessWidget {
  const SubmitAppDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const SubmitAppDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: colors.dialogBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: media.height * 0.85,
        ),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.submitTitle,
                        style: TextStyle(
                          color: colors.dialogText,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: colors.textMuted,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                Text(
                  context.l10n.submitIntro,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                _SubmitOption(
                  icon: Icons.storefront_outlined,
                  color: _firmwareColor('ofw'),
                  title: context.l10n.submitOfficialTitle,
                  subtitle: 'flipper-application-catalog',
                  text: context.l10n.submitOfficialText,
                  actionLabel: context.l10n.submitOfficialAction,
                  actionIcon: Icons.menu_book_outlined,
                  onAction: () => openUrl(context, kOfwContributingUrl),
                ),
                const SizedBox(height: 12),
                _SubmitOption(
                  icon: Icons.extension,
                  color: _firmwareColor('unlshd'),
                  title: context.l10n.submitUnleashedTitle,
                  subtitle: 'all-the-plugins',
                  text: context.l10n.submitUnleashedText,
                  actionLabel: context.l10n.submitUnleashedAction,
                  actionIcon: Icons.add_circle_outline,
                  onAction: () => openUrl(context, kAtpNewAppUrl),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubmitOption extends StatelessWidget {
  const _SubmitOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.text,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String text;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                onAction();
              },
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(actionIcon, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(actionLabel, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
