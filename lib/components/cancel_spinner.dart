import 'package:flutter/material.dart';

import '../services/localization/l10n.dart';
import '../theme/theme.dart';

/// A spinner you press to call off what it is spinning for.
///
/// One control rather than a progress indicator with a cancel button beside
/// it. The two said one thing between them - this is running, and you may stop
/// it - and splitting them left a row of two small round shapes with no
/// visible relationship, in a trailing slot narrow enough that both had to
/// shrink to fit.
class QCancelSpinner extends StatelessWidget {
  const QCancelSpinner({
    super.key,
    required this.onCancel,
    this.size = 22,
    this.color,
    this.tooltip,
  });

  final VoidCallback? onCancel;
  final double size;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.appColors.info;
    return Tooltip(
      message: tooltip ?? context.l10n.commonCancel,
      child: InkResponse(
        onTap: onCancel,
        radius: size,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(strokeWidth: 2, color: tint),
              ),
              Icon(Icons.close, size: size * 0.52, color: tint),
            ],
          ),
        ),
      ),
    );
  }
}
