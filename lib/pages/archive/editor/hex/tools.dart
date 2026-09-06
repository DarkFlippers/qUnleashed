import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../components/notification.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../style.dart';
import 'document.dart';
import 'style.dart';

enum HexCopyFormat { hex, cArray, base64, text }

/// Toolbar over the byte table: history, edit mode, clipboard, block tools and
/// the layout switches.
class HexToolbar extends StatelessWidget {
  const HexToolbar({
    super.key,
    required this.document,
    required this.bytesPerRow,
    required this.onBytesPerRow,
    required this.inspectorVisible,
    required this.onToggleInspector,
    required this.keypadVisible,
    required this.onToggleKeypad,
    required this.showKeypadButton,
  });

  final HexDocument document;
  final int? bytesPerRow;
  final ValueChanged<int?> onBytesPerRow;
  final bool inspectorVisible;
  final VoidCallback onToggleInspector;
  final bool keypadVisible;
  final VoidCallback onToggleKeypad;
  final bool showKeypadButton;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: document,
      builder: (context, _) {
        final selection = document.selection;
        final insert = document.mode == HexEditMode.insert;
        return Container(
          height: 42,
          decoration: BoxDecoration(
            color: colors.card,
            border: Border(bottom: BorderSide(color: colors.divider, width: 1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      _button(
                        colors,
                        icon: Icons.undo_rounded,
                        tooltip: l10n.hexUndo,
                        onPressed: document.canUndo ? document.undo : null,
                      ),
                      _button(
                        colors,
                        icon: Icons.redo_rounded,
                        tooltip: l10n.hexRedo,
                        onPressed: document.canRedo ? document.redo : null,
                      ),
                      _divider(colors),
                      _button(
                        colors,
                        icon: insert
                            ? Icons.text_rotation_none_rounded
                            : Icons.edit_rounded,
                        tooltip: insert
                            ? l10n.hexInsertMode
                            : l10n.hexOverwriteMode,
                        selected: insert,
                        onPressed: () => document.mode = insert
                            ? HexEditMode.overwrite
                            : HexEditMode.insert,
                      ),
                      _button(
                        colors,
                        icon: Icons.my_location_rounded,
                        tooltip: l10n.hexGoTo,
                        onPressed: () => hexPromptOffset(context, document),
                      ),
                      _divider(colors),
                      _copyMenu(context, colors),
                      _button(
                        colors,
                        icon: Icons.content_paste_rounded,
                        tooltip: l10n.hexPaste,
                        onPressed: () => hexPaste(context, document),
                      ),
                      _divider(colors),
                      _button(
                        colors,
                        icon: Icons.format_color_fill_rounded,
                        tooltip: l10n.hexFill,
                        onPressed: selection == null
                            ? null
                            : () => hexPromptFill(context, document, selection),
                      ),
                      _button(
                        colors,
                        icon: Icons.add_box_outlined,
                        tooltip: l10n.hexInsertBytes,
                        onPressed: () => hexPromptInsert(context, document),
                      ),
                      _button(
                        colors,
                        icon: Icons.text_fields_rounded,
                        tooltip: l10n.hexInsertText,
                        onPressed: () => hexPromptText(context, document),
                      ),
                      _button(
                        colors,
                        icon: Icons.backspace_outlined,
                        tooltip: l10n.hexDeleteSelection,
                        onPressed: selection == null
                            ? null
                            : document.deleteSelection,
                      ),
                    ],
                  ),
                ),
              ),
              _divider(colors),
              _rowsMenu(context, colors),
              _button(
                colors,
                icon: Icons.table_chart_outlined,
                tooltip: l10n.hexInspector,
                selected: inspectorVisible,
                onPressed: onToggleInspector,
              ),
              if (showKeypadButton)
                _button(
                  colors,
                  icon: Icons.dialpad_rounded,
                  tooltip: l10n.hexKeypad,
                  selected: keypadVisible,
                  onPressed: onToggleKeypad,
                ),
              const SizedBox(width: 4),
            ],
          ),
        );
      },
    );
  }

  Widget _copyMenu(BuildContext context, QAppColors colors) {
    return PopupMenuButton<HexCopyFormat>(
      tooltip: l10n.hexCopyAs,
      color: colors.dialogBackground,
      padding: EdgeInsets.zero,
      onSelected: (format) => hexCopy(context, document, format),
      itemBuilder: (context) => [
        _menuItem(colors, HexCopyFormat.hex, l10n.hexCopyHex),
        _menuItem(colors, HexCopyFormat.cArray, l10n.hexCopyCArray),
        _menuItem(colors, HexCopyFormat.base64, l10n.hexCopyBase64),
        _menuItem(colors, HexCopyFormat.text, l10n.hexCopyText),
      ],
      child: _face(colors, Icons.copy_rounded),
    );
  }

  Widget _rowsMenu(BuildContext context, QAppColors colors) {
    return PopupMenuButton<int>(
      tooltip: l10n.hexBytesPerRow,
      color: colors.dialogBackground,
      padding: EdgeInsets.zero,
      onSelected: (value) => onBytesPerRow(value == 0 ? null : value),
      itemBuilder: (context) => [
        _menuItem(colors, 0, l10n.hexAuto, selected: bytesPerRow == null),
        for (final choice in kHexBytesPerRowChoices)
          _menuItem(colors, choice, '$choice', selected: bytesPerRow == choice),
      ],
      child: _face(colors, Icons.view_column_outlined),
    );
  }

  Widget _face(QAppColors colors, IconData icon) => Container(
    width: 34,
    height: 34,
    alignment: Alignment.center,
    child: Icon(icon, size: 18, color: colors.textSecondary),
  );

  PopupMenuItem<T> _menuItem<T>(
    QAppColors colors,
    T value,
    String label, {
    bool selected = false,
  }) {
    return PopupMenuItem<T>(
      value: value,
      height: 38,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: colors.dialogText, fontSize: 13),
            ),
          ),
          if (selected)
            Icon(Icons.check_rounded, size: 16, color: colors.accent),
        ],
      ),
    );
  }

  Widget _button(
    QAppColors colors, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool selected = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: selected ? colors.accent : Colors.transparent,
            ),
            child: Icon(
              icon,
              size: 18,
              color: onPressed == null
                  ? colors.textMuted
                  : selected
                  ? colors.onAccent
                  : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider(QAppColors colors) => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 5),
    color: colors.divider,
  );
}

/// Cursor, selection and file facts under the table.
class HexStatusBar extends StatelessWidget {
  const HexStatusBar({super.key, required this.document});

  final HexDocument document;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: document,
      builder: (context, _) {
        final selection = document.selection;
        final cursor = document.cursor;
        final byte = cursor < document.length ? document.byteAt(cursor) : null;
        final resized = document.length != document.savedLength;
        return Container(
          height: 28,
          decoration: BoxDecoration(
            color: colors.card,
            border: Border(top: BorderSide(color: colors.divider, width: 1)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                _cell(
                  colors,
                  l10n.hexStatusOffset,
                  '0x${hexOffsetText(cursor, 4)} · $cursor',
                ),
                if (byte != null)
                  _cell(
                    colors,
                    l10n.hexStatusByte,
                    '0x${hexByteText(byte)} · $byte',
                  ),
                _cell(
                  colors,
                  l10n.hexStatusSelection,
                  selection == null
                      ? '—'
                      : '${selection.length} · 0x${hexOffsetText(selection.start, 4)}',
                ),
                _cell(
                  colors,
                  l10n.hexStatusSize,
                  resized
                      ? '${document.savedLength} → ${document.length}'
                      : '${document.length}',
                  highlight: resized,
                ),
                _cell(
                  colors,
                  l10n.hexStatusModified,
                  '${document.modifiedCount}',
                  highlight: document.modifiedCount > 0,
                ),
                _cell(
                  colors,
                  l10n.hexStatusMode,
                  document.mode == HexEditMode.insert ? 'INS' : 'OVR',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cell(
    QAppColors colors,
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 10,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              color: highlight ? kHexModifiedForeground : colors.textPrimary,
              fontSize: 11,
              fontFamily: kEditorFontFamily,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> hexCopy(
  BuildContext context,
  HexDocument document,
  HexCopyFormat format,
) async {
  final selection = document.selection;
  final bytes = selection != null
      ? document.range(selection.start, selection.end)
      : (document.cursor < document.length
            ? document.range(document.cursor, document.cursor + 1)
            : Uint8List(0));
  if (bytes.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: hexFormatBytes(bytes, format)));
  if (!context.mounted) return;
  context.showNotification(l10n.hexCopied, type: QNotificationType.good);
}

Future<void> hexCut(BuildContext context, HexDocument document) async {
  final selection = document.selection;
  if (selection == null) return;
  await hexCopy(context, document, HexCopyFormat.hex);
  document.deleteRange(selection.start, selection.end);
}

Future<void> hexPaste(BuildContext context, HexDocument document) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text;
  if (text == null || text.isEmpty) {
    if (!context.mounted) return;
    context.showNotification(
      l10n.hexClipboardEmpty,
      type: QNotificationType.warning,
    );
    return;
  }
  final bytes = hexParseClipboard(text);
  final selection = document.selection;
  if (selection != null) document.deleteRange(selection.start, selection.end);
  document.writeBytes(
    document.cursor,
    bytes,
    insert: document.mode == HexEditMode.insert || selection != null,
  );
  if (!context.mounted) return;
  context.showNotification(
    l10n.hexPastedBytes(bytes.length),
    type: QNotificationType.good,
  );
}

String hexFormatBytes(List<int> bytes, HexCopyFormat format) {
  switch (format) {
    case HexCopyFormat.hex:
      return bytes.map(hexByteText).join(' ');
    case HexCopyFormat.cArray:
      return bytes.map((byte) => '0x${hexByteText(byte)}').join(', ');
    case HexCopyFormat.base64:
      return base64Encode(bytes);
    case HexCopyFormat.text:
      return utf8.decode(bytes, allowMalformed: true);
  }
}

/// Clipboard text becomes bytes: a hex byte string when it reads as one, the
/// raw UTF-8 text otherwise.
Uint8List hexParseClipboard(String text) {
  final compact = text.replaceAll(RegExp(r'(0x)|[\s,;]'), '');
  if (compact.isNotEmpty &&
      compact.length.isEven &&
      RegExp(r'^[0-9a-fA-F]+$').hasMatch(compact)) {
    final bytes = Uint8List(compact.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(compact.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
  return Uint8List.fromList(utf8.encode(text));
}

/// Parses `0x1F`, `1F` (hex by default) and `31d` (decimal).
int? hexParseOffset(String text) {
  var value = text.trim().toLowerCase();
  if (value.isEmpty) return null;
  if (value.startsWith('0x')) {
    return int.tryParse(value.substring(2), radix: 16);
  }
  if (value.endsWith('d')) {
    return int.tryParse(value.substring(0, value.length - 1));
  }
  return int.tryParse(value, radix: 16);
}

Future<void> hexPromptOffset(BuildContext context, HexDocument document) async {
  final value = await _prompt(
    context,
    title: l10n.hexGoTo,
    hint: l10n.hexGoToHint,
  );
  if (value == null) return;
  final offset = hexParseOffset(value);
  if (!context.mounted) return;
  if (offset == null || offset < 0 || offset > document.length) {
    context.showNotification(
      l10n.hexOffsetOutOfRange,
      type: QNotificationType.error,
    );
    return;
  }
  document.moveTo(offset);
}

Future<void> hexPromptFill(
  BuildContext context,
  HexDocument document,
  HexRange range,
) async {
  final value = await _prompt(
    context,
    title: l10n.hexFill,
    hint: l10n.hexByteValueHint,
  );
  if (value == null) return;
  final byte = hexParseOffset(value);
  if (!context.mounted) return;
  if (byte == null || byte < 0 || byte > 0xff) {
    context.showNotification(
      l10n.hexInvalidValue,
      type: QNotificationType.error,
    );
    return;
  }
  document.fillRange(range.start, range.end, byte);
}

Future<void> hexPromptInsert(BuildContext context, HexDocument document) async {
  final value = await _prompt(
    context,
    title: l10n.hexInsertBytes,
    hint: l10n.hexInsertHint,
  );
  if (value == null) return;
  final parts = value.split(RegExp(r'[\s*x×]+'))..removeWhere((p) => p.isEmpty);
  final count = int.tryParse(parts.isEmpty ? '' : parts.first);
  final byte = parts.length > 1 ? hexParseOffset(parts[1]) : 0;
  if (!context.mounted) return;
  if (count == null || count <= 0 || byte == null || byte < 0 || byte > 0xff) {
    context.showNotification(
      l10n.hexInvalidValue,
      type: QNotificationType.error,
    );
    return;
  }
  document.insertZeros(document.cursor, count, byte);
}

Future<void> hexPromptText(BuildContext context, HexDocument document) async {
  final value = await _prompt(
    context,
    title: l10n.hexInsertText,
    hint: l10n.hexInsertTextHint,
    monospace: false,
  );
  if (value == null || value.isEmpty) return;
  final bytes = utf8.encode(value);
  document.writeBytes(
    document.cursor,
    bytes,
    insert: document.mode == HexEditMode.insert,
  );
}

Future<String?> _prompt(
  BuildContext context, {
  required String title,
  required String hint,
  bool monospace = true,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      final colors = context.appColors;
      return AlertDialog(
        backgroundColor: colors.dialogBackground,
        title: Text(title, style: TextStyle(color: colors.dialogText)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(
            color: colors.dialogText,
            fontFamily: monospace ? kEditorFontFamily : null,
          ),
          cursorColor: colors.accent,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: colors.dialogMuted),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colors.dialogDivider),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colors.accent),
            ),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              l10n.commonCancel,
              style: TextStyle(color: colors.dialogMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.commonOk, style: TextStyle(color: colors.accent)),
          ),
        ],
      );
    },
  ).whenComplete(controller.dispose);
}
