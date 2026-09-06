import '../../../services/localization/l10n.dart';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:qunleashed/components/appbar.dart';
import 'package:re_editor/re_editor.dart';

import '../../../components/dialogs/confirm.dart';
import '../../../components/notification.dart';
import '../../../components/path.dart';
import '../../../services/logging.dart';
import '../../../theme/theme.dart';
import 'document.dart';
import 'find_panel.dart';
import 'hex/binary.dart';
import 'hex/document.dart';
import 'hex/editor.dart';
import 'hex/find.dart';
import 'line_numbers.dart';
import 'style.dart';
import 'syntax.dart';
import 'toolbar.dart';

enum EditorMode { text, hex }

class TextEditorPage extends StatefulWidget {
  const TextEditorPage({
    super.key,
    required this.localPath,
    this.title,
    this.onSave,
    this.onRun,
  });

  final String localPath;
  final String? title;
  final Future<bool> Function(List<int> bytes)? onSave;
  final VoidCallback? onRun;

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<TextEditorPage> {
  final CodeLineEditingController _controller = CodeLineEditingController();
  late final CodeFindController _find = CodeFindController(_controller);

  late final String _name;
  late final CodeHighlightTheme _highlightTheme;

  EditorDocument? _doc;
  HexDocument? _hexDoc;
  HexFindController? _hexFind;
  EditorMode _mode = EditorMode.text;
  TextLineBreak _lineBreak = TextLineBreak.lf;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = widget.title ?? basename(widget.localPath.replaceAll('\\', '/'));
    _highlightTheme = editorHighlightTheme(_name);
    _controller.addListener(_onCodeChanged);
    _load();
  }

  @override
  void dispose() {
    _controller.removeListener(_onCodeChanged);
    _find.dispose();
    _controller.dispose();
    _doc?.dispose();
    _disposeHex();
    super.dispose();
  }

  void _disposeHex() {
    _hexFind?.dispose();
    _hexDoc?.dispose();
    _hexFind = null;
    _hexDoc = null;
  }

  void _openHex(List<int> bytes) {
    _disposeHex();
    final document = HexDocument(bytes);
    _hexDoc = document;
    _hexFind = HexFindController(document);
    _mode = EditorMode.hex;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    List<int>? bytes;
    try {
      bytes = await Future(() => io.File(widget.localPath).readAsBytesSync());
    } catch (e) {
      LogService.log('[TextEditor] read ${widget.localPath} failed: $e');
    }
    if (!mounted) return;
    final binary = bytes != null && looksBinary(bytes);
    setState(() {
      _loading = false;
      if (bytes == null) {
        _error = context.l10n.editorReadFailed;
      } else if (binary) {
        _openHex(bytes);
      } else {
        final text = utf8.decode(bytes, allowMalformed: true);
        _lineBreak = _lineBreakOf(text);
        _doc = EditorDocument.fromText(text);
        _controller.text = text;
      }
    });
    if (binary && mounted) {
      context.showNotification(
        context.l10n.hexBinaryOpened,
        type: QNotificationType.info,
      );
    }
  }

  /// Switches between the text editor and the hex table, carrying the current
  /// content over.
  Future<void> _toggleMode() async {
    if (_mode == EditorMode.hex) {
      final bytes = _hexDoc!.bytes;
      String? text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        final ok = await QConfirmDialog.show(
          context,
          title: context.l10n.hexNotTextTitle,
          message: context.l10n.hexNotTextMessage,
          confirmLabel: context.l10n.hexOpenAsText,
        );
        if (!ok) return;
        text = utf8.decode(bytes, allowMalformed: true);
      }
      if (!mounted) return;
      final decoded = text;
      setState(() {
        _disposeHex();
        _lineBreak = _lineBreakOf(decoded);
        _doc?.dispose();
        _doc = EditorDocument.fromText(decoded);
        _controller.text = decoded;
        _mode = EditorMode.text;
      });
      return;
    }
    final bytes = utf8.encode(_controller.codeLines.asString(_lineBreak));
    setState(() {
      _find.close();
      _openHex(bytes);
    });
  }

  void _onCodeChanged() => _doc?.update(_controller.codeLines);

  /// The editor keeps LF internally, so the file is written back with the
  /// line break it came with.
  static TextLineBreak _lineBreakOf(String text) {
    if (text.contains('\r\n')) return TextLineBreak.crlf;
    if (text.contains('\r')) return TextLineBreak.cr;
    return TextLineBreak.lf;
  }

  void _toggleFind() {
    if (_mode == EditorMode.hex) {
      _hexFind!.toggle();
      return;
    }
    if (_find.value == null) {
      _find.findMode();
    } else {
      _find.close();
    }
  }

  Future<void> _save() async {
    final doc = _doc;
    final hex = _hexDoc;
    if (_mode == EditorMode.hex ? hex == null : doc == null) return;
    setState(() => _saving = true);
    final bytes = _mode == EditorMode.hex
        ? hex!.bytes
        : utf8.encode(_controller.codeLines.asString(_lineBreak));
    var ok = true;
    try {
      await Future(
        () => io.File(widget.localPath).writeAsBytesSync(bytes, flush: true),
      );
    } catch (e) {
      LogService.log('[TextEditor] write ${widget.localPath} failed: $e');
      ok = false;
    }
    final onSave = widget.onSave;
    if (ok && onSave != null) ok = await onSave(bytes);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!ok) return;
      if (_mode == EditorMode.hex) {
        hex!.markSaved();
      } else {
        doc!.markSaved(_controller.codeLines);
      }
    });
    context.showNotification(
      ok ? context.l10n.editorSaved : context.l10n.editorSaveFailed,
      type: ok ? QNotificationType.good : QNotificationType.error,
    );
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: QPageAppBar(
        title: _name,
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        actions: [
          if (widget.onRun != null)
            QPageAppBarAction(
              tooltip: context.l10n.editorRun,
              onPressed: _loading ? null : widget.onRun,
              icon: const Icon(Icons.play_arrow),
            ),
          QPageAppBarAction(
            tooltip: context.l10n.findFind,
            onPressed: (_loading || !_hasContent) ? null : _toggleFind,
            icon: const Icon(Icons.search),
          ),
          QPageAppBarAction(
            tooltip: _mode == EditorMode.hex
                ? context.l10n.hexShowAsText
                : context.l10n.hexShowAsHex,
            onPressed: (_loading || !_hasContent) ? null : _toggleMode,
            icon: Icon(
              _mode == EditorMode.hex
                  ? Icons.notes_rounded
                  : Icons.data_array_rounded,
            ),
          ),
          QPageAppBarAction(
            tooltip: context.l10n.commonSave,
            onPressed: (_saving || _loading || !_hasContent) ? null : _save,
            icon: _saving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: colors.onAccent,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save),
          ),
        ],
      ),
      body: _buildBody(colors),
    );
  }

  bool get _hasContent =>
      _mode == EditorMode.hex ? _hexDoc != null : _doc != null;

  Widget _buildBody(QAppColors colors) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Text(error, style: TextStyle(color: colors.danger)),
      );
    }
    if (_mode == EditorMode.hex) {
      return HexEditor(document: _hexDoc!, find: _hexFind!);
    }
    final doc = _doc!;
    final root = _highlightTheme.theme['root'];
    return CodeEditor(
      controller: _controller,
      findController: _find,
      autofocus: false,
      chunkAnalyzer: const NonCodeChunkAnalyzer(),
      padding: const EdgeInsets.symmetric(vertical: 12),
      style: CodeEditorStyle(
        fontSize: kEditorFontSize,
        fontHeight: kEditorLineHeight,
        fontFamily: kEditorFontFamily,
        textColor: root?.color,
        backgroundColor: root?.backgroundColor ?? colors.terminalBackground,
        cursorColor: colors.accent,
        selectionColor: colors.accent.withValues(alpha: 0.35),
        highlightColor: colors.accent.withValues(alpha: 0.55),
        codeTheme: _highlightTheme,
      ),
      indicatorBuilder:
          (context, editingController, chunkController, notifier) {
            return EditorLineNumbers(
              controller: editingController,
              notifier: notifier,
              document: doc,
            );
          },
      findBuilder: (context, controller, readOnly) => EditorFindPanel(
        controller: controller,
        readOnly: readOnly,
        background: colors.accent,
        foreground: colors.onAccent,
      ),
      toolbarController: editorSelectionToolbar,
    );
  }
}
