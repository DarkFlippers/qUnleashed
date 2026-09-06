import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../style.dart';
import 'find.dart';

/// Search and replace bar for the hex table: a hex pattern with `?` wildcards
/// or plain text.
class HexFindPanel extends StatelessWidget {
  const HexFindPanel({
    super.key,
    required this.controller,
    required this.background,
    required this.foreground,
  });

  final HexFindController controller;
  final Color background;
  final Color foreground;

  static const double _rowHeight = 44;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.visible) return const SizedBox.shrink();
        return Container(
          color: background,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: _rowHeight - 6, child: _findRow(context)),
              if (controller.replaceMode)
                SizedBox(height: _rowHeight, child: _replaceRow(context)),
            ],
          ),
        );
      },
    );
  }

  Widget _findRow(BuildContext context) {
    final matches = controller.matches.length;
    final hex = controller.mode == HexSearchMode.hex;
    return Row(
      children: [
        _button(
          icon: controller.replaceMode
              ? Icons.keyboard_arrow_down_rounded
              : Icons.keyboard_arrow_right_rounded,
          tooltip: l10n.findReplace,
          onPressed: controller.toggleReplaceMode,
        ),
        Expanded(
          child: _input(
            controller: controller.findInput,
            focusNode: controller.findFocusNode,
            hint: hex ? l10n.hexPatternHint : l10n.findFind,
            invalid: controller.invalid,
          ),
        ),
        _toggle(
          label: 'HEX',
          tooltip: l10n.hexSearchHex,
          selected: hex,
          onPressed: () => controller.setMode(HexSearchMode.hex),
        ),
        _toggle(
          label: 'TXT',
          tooltip: l10n.hexSearchText,
          selected: !hex,
          onPressed: () => controller.setMode(HexSearchMode.text),
        ),
        if (!hex)
          _toggle(
            label: 'Aa',
            tooltip: l10n.findMatchCase,
            selected: controller.matchCase,
            onPressed: controller.toggleMatchCase,
          ),
        SizedBox(
          width: 62,
          child: Text(
            controller.invalid
                ? l10n.hexInvalidPattern
                : matches == 0
                ? l10n.findNoResults
                : '${controller.index + 1}/$matches',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: controller.invalid
                  ? const Color(0xffff5874)
                  : foreground.withValues(alpha: 0.75),
              fontSize: 11,
            ),
          ),
        ),
        _button(
          icon: Icons.keyboard_arrow_up_rounded,
          tooltip: l10n.findPrevious,
          onPressed: matches == 0 ? null : controller.previous,
        ),
        _button(
          icon: Icons.keyboard_arrow_down_rounded,
          tooltip: l10n.findNext,
          onPressed: matches == 0 ? null : controller.next,
        ),
        _button(
          icon: Icons.close_rounded,
          tooltip: l10n.commonClose,
          onPressed: controller.close,
        ),
      ],
    );
  }

  Widget _replaceRow(BuildContext context) {
    final matches = controller.matches.length;
    return Row(
      children: [
        const SizedBox(width: 32),
        Expanded(
          child: _input(
            controller: controller.replaceInput,
            focusNode: controller.replaceFocusNode,
            hint: controller.mode == HexSearchMode.hex
                ? l10n.hexReplaceHexHint
                : l10n.findReplaceWith,
            invalid: false,
          ),
        ),
        _button(
          icon: Icons.find_replace_rounded,
          tooltip: l10n.findReplace,
          onPressed: matches == 0 ? null : controller.replaceCurrent,
        ),
        _button(
          icon: Icons.change_circle_outlined,
          tooltip: l10n.findReplaceAll,
          onPressed: matches == 0 ? null : controller.replaceAll,
        ),
        const SizedBox(width: 32),
      ],
    );
  }

  Widget _input({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required bool invalid,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      style: TextStyle(
        color: foreground,
        fontSize: 13,
        fontFamily: kEditorFontFamily,
      ),
      cursorColor: foreground,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: foreground.withValues(alpha: 0.6),
          fontSize: 13,
        ),
        filled: true,
        fillColor: foreground.withValues(alpha: invalid ? 0.08 : 0.16),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _button({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      color: foreground,
      disabledColor: foreground.withValues(alpha: 0.35),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      onPressed: onPressed,
    );
  }

  Widget _toggle({
    required String label,
    required String tooltip,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 34,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: selected
                ? foreground.withValues(alpha: 0.24)
                : Colors.transparent,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: foreground.withValues(alpha: selected ? 1 : 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
