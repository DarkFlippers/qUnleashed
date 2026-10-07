import 'package:flutter/material.dart';

import '../services/localization/l10n.dart';
import '../theme/theme.dart';

/// A plain cross that calls off the transfer it sits beside.
///
/// The progress it belongs to is drawn elsewhere - a row fill, a bar - so
/// unlike [QCancelSpinner] this carries no spinner of its own.
class QCancelButton extends StatelessWidget {
  const QCancelButton({
    super.key,
    required this.onCancel,
    this.size = 20,
    this.color,
  });

  final VoidCallback? onCancel;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.commonCancel,
      child: InkResponse(
        onTap: onCancel,
        radius: size,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.close_rounded,
            size: size * 0.85,
            color: color ?? context.appColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
