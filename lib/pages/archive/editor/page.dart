import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:qunleashed/components/appbar.dart';

import '../../../components/notification.dart';
import '../../../components/path.dart';
import '../../../services/logging.dart';
import '../../../theme/colors/editor.dart';
import '../../../theme/theme.dart';
import 'document.dart';
import 'highlighter.dart';
import 'style.dart';
import 'widgets/line_row.dart';

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
  static const String _zwsp = '\u200b';

  final ScrollController _scroll = ScrollController();
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode();
  final GlobalKey _fieldKey = GlobalKey();

  late final String _name;
  late final LineHighlighter _highlighter;

  EditorDocument? _doc;
  int? _editing;
  bool _editingModified = false;
  bool _retargeting = false;
  String _fieldText = '';

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = widget.title ?? basename(widget.localPath.replaceAll('\\', '/'));
    _highlighter = LineHighlighter.forFileName(_name);
    _focus.addListener(_onFocusChanged);
    _load();
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _field.dispose();
    _scroll.dispose();
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
        _error = 'Failed to read file';
      } else {
        _doc = EditorDocument.fromText(text);
      }
    });
  }

  void _onFocusChanged() {
    if (_focus.hasFocus || _editing == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _retargeting || _focus.hasFocus || _editing == null) {
        return;
      }
      setState(() => _editing = null);
    });
  }

  void _startEditing(int index, int offset) {
    final doc = _doc;
    if (doc == null) return;
    setState(() {
      _editing = index;
      _editingModified = doc.isModified(index);
    });
    _setField(doc.lineAt(index), offset);
    _focus.requestFocus();
  }

  void _setField(String line, int caret) {
    _fieldText = '$_zwsp$line';
    _field.value = TextEditingValue(
      text: _fieldText,
      selection: TextSelection.collapsed(
        offset: caret.clamp(0, line.length) + 1,
      ),
    );
  }

  void _moveEditing(EditorDocument doc, int index, int caret) {
    _retargeting = true;
    setState(() {
      _editing = index;
      _editingModified = doc.isModified(index);
    });
    _setField(doc.lineAt(index), caret);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_editing != null && !_focus.hasFocus) _focus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) => _retargeting = false);
    });
  }

  int _contentOffset(String value, int fieldOffset) => value
      .substring(0, fieldOffset.clamp(0, value.length))
      .replaceAll(_zwsp, '')
      .length;

  void _onFieldChanged(String value) {
    final doc = _doc;
    final index = _editing;
    if (doc == null || index == null) return;

    final previous = _fieldText;
    final selection = _field.selection;
    _fieldText = value;

    final backspacedIntoPreviousLine =
        index > 0 &&
        previous.startsWith(_zwsp) &&
        value == previous.substring(1) &&
        selection.isCollapsed &&
        selection.baseOffset == 0;
    if (backspacedIntoPreviousLine) {
      final caret = doc.mergeWithPrevious(index);
      _moveEditing(doc, index - 1, caret);
      return;
    }

    final content = value.replaceAll(_zwsp, '');
    final caret = _contentOffset(value, selection.baseOffset);

    if (content.contains('\n')) {
      final parts = content.split('\n');
      doc.replaceWithLines(index, parts);
      var target = index;
      var offset = 0;
      var consumed = 0;
      for (var i = 0; i < parts.length; i++) {
        final end = consumed + parts[i].length;
        if (caret <= end) {
          target = index + i;
          offset = caret - consumed;
          break;
        }
        consumed = end + 1;
      }
      _moveEditing(doc, target, offset);
      return;
    }

    doc.replace(index, content);
    if (value != '$_zwsp$content') _setField(content, caret);

    final modified = doc.isModified(index);
    if (modified != _editingModified) {
      setState(() => _editingModified = modified);
    }
  }

  Future<void> _save() async {
    final doc = _doc;
    if (doc == null) return;
    setState(() => _saving = true);
    final bytes = utf8.encode(doc.text);
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
      if (ok) doc.markSaved();
    });
    context.showNotification(
      ok ? 'Saved' : 'Save failed',
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
              tooltip: 'Run',
              onPressed: _loading ? null : widget.onRun,
              icon: const Icon(Icons.play_arrow),
            ),
          QPageAppBarAction(
            tooltip: 'Save',
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
    final gutterWidth = editorGutterWidth(doc.length);

    return MediaQuery.withNoTextScaling(
      child: ColoredBox(
        color:
            dartEditorTheme['root']?.backgroundColor ??
            colors.terminalBackground,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: gutterWidth,
              child: const ColoredBox(color: kEditorGutterBackground),
            ),
            Scrollbar(
              controller: _scroll,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: doc.length,
                addAutomaticKeepAlives: false,
                addSemanticIndexes: false,
                itemBuilder: (context, index) =>
                    _buildLine(doc, index, gutterWidth, colors),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLine(
    EditorDocument doc,
    int index,
    double gutterWidth,
    QAppColors colors,
  ) {
    if (index != _editing) {
      return EditorLineView(
        span: _highlighter.spanFor(doc.lineAt(index)),
        number: index + 1,
        modified: doc.isModified(index),
        gutterWidth: gutterWidth,
        onTapAtOffset: (offset) => _startEditing(index, offset),
      );
    }
    return EditorLineField(
      number: index + 1,
      modified: _editingModified,
      gutterWidth: gutterWidth,
      child: TextField(
        key: _fieldKey,
        controller: _field,
        focusNode: _focus,
        maxLines: null,
        style: kEditorTextStyle,
        strutStyle: kEditorStrutStyle,
        cursorColor: colors.accent,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        decoration: const InputDecoration(
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          isCollapsed: true,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: _onFieldChanged,
      ),
    );
  }
}
