import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

/// Search and replace bar shown under the app bar while the find mode is on.
class EditorFindPanel extends StatelessWidget implements PreferredSizeWidget {
  const EditorFindPanel({
    super.key,
    required this.controller,
    required this.readOnly,
    required this.background,
    required this.foreground,
  });

  final CodeFindController controller;
  final bool readOnly;
  final Color background;
  final Color foreground;

  static const double _rowHeight = 44;

  @override
  Size get preferredSize {
    final value = controller.value;
    if (value == null) return Size.zero;
    return Size(
      double.infinity,
      value.replaceMode ? _rowHeight * 2 : _rowHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();
    return Container(
      color: background,
      width: double.infinity,
      height: preferredSize.height,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Column(
        children: [
          SizedBox(height: _rowHeight - 6, child: _buildFindRow(value)),
          if (value.replaceMode)
            SizedBox(height: _rowHeight, child: _buildReplaceRow()),
        ],
      ),
    );
  }

  Widget _buildFindRow(CodeFindValue value) {
    final result = value.result;
    final matches = result?.matches.length ?? 0;
    return Row(
      children: [
        _button(
          icon: value.replaceMode
              ? Icons.keyboard_arrow_down_rounded
              : Icons.keyboard_arrow_right_rounded,
          tooltip: 'Replace',
          onPressed: readOnly ? null : controller.toggleMode,
        ),
        Expanded(
          child: _input(
            controller: controller.findInputController,
            focusNode: controller.findInputFocusNode,
            hint: 'Find',
          ),
        ),
        _toggle(
          label: 'Aa',
          tooltip: 'Match case',
          selected: value.option.caseSensitive,
          onPressed: controller.toggleCaseSensitive,
        ),
        _toggle(
          label: '.*',
          tooltip: 'Regex',
          selected: value.option.regex,
          onPressed: controller.toggleRegex,
        ),
        SizedBox(
          width: 62,
          child: Text(
            matches == 0 ? 'no results' : '${result!.index + 1}/$matches',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground.withValues(alpha: 0.75),
              fontSize: 11,
            ),
          ),
        ),
        _button(
          icon: Icons.keyboard_arrow_up_rounded,
          tooltip: 'Previous',
          onPressed: matches == 0 ? null : controller.previousMatch,
        ),
        _button(
          icon: Icons.keyboard_arrow_down_rounded,
          tooltip: 'Next',
          onPressed: matches == 0 ? null : controller.nextMatch,
        ),
        _button(
          icon: Icons.close_rounded,
          tooltip: 'Close',
          onPressed: controller.close,
        ),
      ],
    );
  }

  Widget _buildReplaceRow() {
    final matches = controller.value?.result?.matches.length ?? 0;
    return Row(
      children: [
        const SizedBox(width: 32),
        Expanded(
          child: _input(
            controller: controller.replaceInputController,
            focusNode: controller.replaceInputFocusNode,
            hint: 'Replace with',
          ),
        ),
        _button(
          icon: Icons.find_replace_rounded,
          tooltip: 'Replace',
          onPressed: matches == 0 ? null : controller.replaceMatch,
        ),
        _button(
          icon: Icons.change_circle_outlined,
          tooltip: 'Replace all',
          onPressed: matches == 0 ? null : controller.replaceAllMatches,
        ),
        const SizedBox(width: 32),
      ],
    );
  }

  Widget _input({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      style: TextStyle(color: foreground, fontSize: 13),
      cursorColor: foreground,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: foreground.withValues(alpha: 0.6),
          fontSize: 13,
        ),
        filled: true,
        fillColor: foreground.withValues(alpha: 0.16),
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
          width: 30,
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
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
