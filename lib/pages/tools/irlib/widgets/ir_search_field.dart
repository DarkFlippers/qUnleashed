import 'package:flutter/material.dart';

import '../../../../theme.dart';

class IrSearchField extends StatelessWidget {
  const IrSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.textInputAction = TextInputAction.search,
    this.padding = const EdgeInsets.fromLTRB(14, 8, 14, 8),
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final TextInputAction textInputAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: padding,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: textInputAction,
        style: TextStyle(color: colors.textPrimary),
        cursorColor: colors.accent,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: colors.textMuted),
          filled: true,
          fillColor: colors.card,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          prefixIcon: Icon(Icons.search, color: colors.textMuted),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Clear',
                icon: Icon(Icons.close, color: colors.textMuted, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                  onClear?.call();
                },
              );
            },
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
