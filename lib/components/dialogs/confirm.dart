import 'package:flutter/material.dart';

import '../../theme/theme.dart';

class QConfirmDialog extends StatelessWidget {
  const QConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'OK',
    this.cancelLabel = 'Cancel',
    this.destructive = true,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    bool destructive = true,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => QConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AlertDialog(
      backgroundColor: colors.dialogBackground,
      title: Text(title, style: TextStyle(color: colors.dialogText)),
      content: Text(message, style: TextStyle(color: colors.dialogText)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel, style: TextStyle(color: colors.dialogMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmLabel,
            style: TextStyle(
              color: destructive ? colors.danger : colors.accent,
            ),
          ),
        ),
      ],
    );
  }
}
