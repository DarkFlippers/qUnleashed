import 'package:flutter/material.dart';

import '../../../theme/theme.dart';

InputDecoration plotterFieldDecoration(
  BuildContext context, {
  required String label,
}) {
  final colors = context.appColors;
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: label,
    isDense: true,
    filled: true,
    fillColor: colors.card,
    labelStyle: TextStyle(color: colors.textMuted, fontSize: 13),
    floatingLabelStyle: TextStyle(color: colors.accent, fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    enabledBorder: border(colors.divider),
    border: border(colors.divider),
    focusedBorder: border(colors.accent, 1.6),
  );
}

class PlotterCard extends StatelessWidget {
  const PlotterCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: child,
    );
  }
}
