import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/theme.dart';
import 'document.dart';
import 'find.dart';
import 'find_panel.dart';
import 'inspector.dart';
import 'keypad.dart';
import 'style.dart';
import 'tools.dart';
import 'view.dart';

const double _kWideLayout = 900;
const double _kInspectorWidth = 268;

/// The hex editor: toolbar, search bar, byte table, inspector and status bar
/// around one [HexDocument].
class HexEditor extends StatefulWidget {
  const HexEditor({
    super.key,
    required this.document,
    required this.find,
    this.focusNode,
  });

  final HexDocument document;
  final HexFindController find;
  final FocusNode? focusNode;

  @override
  State<HexEditor> createState() => _HexEditorState();
}

class _HexEditorState extends State<HexEditor> {
  final GlobalKey<HexTableState> _tableKey = GlobalKey<HexTableState>();

  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  int? _bytesPerRow;
  int _effectiveBytesPerRow = 16;
  bool? _inspector;
  bool _keypad = false;

  @override
  void dispose() {
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _kWideLayout;
        final inspector = _inspector ?? wide;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HexToolbar(
              document: widget.document,
              bytesPerRow: _bytesPerRow,
              onBytesPerRow: (value) => setState(() => _bytesPerRow = value),
              inspectorVisible: inspector,
              onToggleInspector: () => _toggleInspector(wide, inspector),
              keypadVisible: _keypad,
              onToggleKeypad: () => setState(() => _keypad = !_keypad),
              showKeypadButton: !wide,
            ),
            HexFindPanel(
              controller: widget.find,
              background: colors.accent,
              foreground: colors.onAccent,
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildTable(colors)),
                  if (wide && inspector) ...[
                    Container(width: 1, color: colors.divider),
                    SizedBox(
                      width: _kInspectorWidth,
                      child: HexInspector(document: widget.document),
                    ),
                  ],
                ],
              ),
            ),
            if (_keypad)
              HexKeypad(
                document: widget.document,
                onClose: () => setState(() => _keypad = false),
              ),
            HexStatusBar(document: widget.document),
          ],
        );
      },
    );
  }

  Widget _buildTable(QAppColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _effectiveBytesPerRow = HexMetrics.resolveBytesPerRow(
          constraints.maxWidth,
          hexCharWidth(),
          hexOffsetDigits(widget.document.length),
          _bytesPerRow,
        );
        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: HexTable(
            key: _tableKey,
            document: widget.document,
            find: widget.find,
            bytesPerRow: _effectiveBytesPerRow,
            selectionColor: colors.accent.withValues(alpha: 0.35),
            focusNode: _focus,
          ),
        );
      },
    );
  }

  void _toggleInspector(bool wide, bool visible) {
    if (wide) {
      setState(() => _inspector = !visible);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.7,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: HexInspector(
            document: widget.document,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final document = widget.document;
    final keyboard = HardwareKeyboard.instance;
    final control = keyboard.isControlPressed || keyboard.isMetaPressed;
    final shift = keyboard.isShiftPressed;
    final key = event.logicalKey;
    final rowBytes = _effectiveBytesPerRow;

    if (control) {
      if (key == LogicalKeyboardKey.keyZ) {
        shift ? document.redo() : document.undo();
      } else if (key == LogicalKeyboardKey.keyY) {
        document.redo();
      } else if (key == LogicalKeyboardKey.keyA) {
        document.selectAll();
      } else if (key == LogicalKeyboardKey.keyC) {
        hexCopy(context, document, HexCopyFormat.hex);
      } else if (key == LogicalKeyboardKey.keyX) {
        hexCut(context, document);
      } else if (key == LogicalKeyboardKey.keyV) {
        hexPaste(context, document);
      } else if (key == LogicalKeyboardKey.keyF) {
        widget.find.open();
      } else if (key == LogicalKeyboardKey.keyH) {
        widget.find.open(replace: true);
      } else if (key == LogicalKeyboardKey.keyG) {
        hexPromptOffset(context, document);
      } else if (key == LogicalKeyboardKey.home) {
        document.moveTo(0, extend: shift);
      } else if (key == LogicalKeyboardKey.end) {
        document.moveTo(document.length, extend: shift);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      document.moveNibble(-1, extend: shift);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      document.moveNibble(1, extend: shift);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      document.moveBy(-rowBytes, extend: shift);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      document.moveBy(rowBytes, extend: shift);
    } else if (key == LogicalKeyboardKey.home) {
      document.moveTo(
        document.cursor - document.cursor % rowBytes,
        extend: shift,
      );
    } else if (key == LogicalKeyboardKey.end) {
      document.moveTo(
        document.cursor - document.cursor % rowBytes + rowBytes - 1,
        extend: shift,
      );
    } else if (key == LogicalKeyboardKey.pageUp) {
      document.moveBy(-_pageBytes(rowBytes), extend: shift);
    } else if (key == LogicalKeyboardKey.pageDown) {
      document.moveBy(_pageBytes(rowBytes), extend: shift);
    } else if (key == LogicalKeyboardKey.tab) {
      document.pane = document.pane == HexPane.hex
          ? HexPane.ascii
          : HexPane.hex;
    } else if (key == LogicalKeyboardKey.insert) {
      document.mode = document.mode == HexEditMode.insert
          ? HexEditMode.overwrite
          : HexEditMode.insert;
    } else if (key == LogicalKeyboardKey.backspace) {
      document.backspace();
    } else if (key == LogicalKeyboardKey.delete) {
      document.deleteForward();
    } else if (key == LogicalKeyboardKey.escape) {
      if (widget.find.visible) {
        widget.find.close();
      } else {
        document.clearSelection();
      }
    } else if (key == LogicalKeyboardKey.f3) {
      shift ? widget.find.previous() : widget.find.next();
    } else {
      return _onCharacter(event);
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _onCharacter(KeyEvent event) {
    final character = event.character;
    if (character == null || character.isEmpty) {
      return KeyEventResult.ignored;
    }
    final code = character.codeUnitAt(0);
    final document = widget.document;
    if (document.pane == HexPane.ascii) {
      if (code < 0x20 || code > 0xff) return KeyEventResult.ignored;
      document.inputByte(code);
      return KeyEventResult.handled;
    }
    final digit = _hexDigit(code);
    if (digit == null) return KeyEventResult.ignored;
    document.inputNibble(digit);
    return KeyEventResult.handled;
  }

  int _pageBytes(int rowBytes) =>
      (_tableKey.currentState?.pageRows ?? 8) * rowBytes;

  static int? _hexDigit(int code) {
    if (code >= 0x30 && code <= 0x39) return code - 0x30;
    if (code >= 0x61 && code <= 0x66) return code - 0x61 + 10;
    if (code >= 0x41 && code <= 0x46) return code - 0x41 + 10;
    return null;
  }
}
