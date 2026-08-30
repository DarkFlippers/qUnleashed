import '../../../services/localization/l10n.dart';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:qunleashed/components/appbar.dart';
import 'package:re_editor/re_editor.dart';

import '../../../components/notification.dart';
import '../../../components/path.dart';
import '../../../services/logging.dart';
import '../../../theme/theme.dart';
import 'document.dart';
import 'find_panel.dart';
import 'line_numbers.dart';
import 'style.dart';
import 'syntax.dart';
import 'toolbar.dart';

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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    String? text;
    try {
      final bytes = await Future(
        () => io.File(widget.localPath).readAsBytesSync(),
      );
      text = utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      LogService.log('[TextEditor] read ${widget.localPath} failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (text == null) {
        _error = context.l10n.editorReadFailed;
      } else {
        _lineBreak = _lineBreakOf(text);
        _doc = EditorDocument.fromText(text);
        _controller.text = text;
      }
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
    if (_find.value == null) {
      _find.findMode();
    } else {
      _find.close();
    }
  }

  Future<void> _save() async {
    final doc = _doc;
    if (doc == null) return;
    setState(() => _saving = true);
    final bytes = utf8.encode(_controller.codeLines.asString(_lineBreak));
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
      if (ok) doc.markSaved(_controller.codeLines);
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
            onPressed: (_loading || _doc == null) ? null : _toggleFind,
            icon: const Icon(Icons.search),
          ),
          QPageAppBarAction(
            tooltip: context.l10n.commonSave,
            onPressed: (_saving || _loading || _doc == null) ? null : _save,
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
      indicatorBuilder: (context, editingController, chunkController, notifier) {
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
