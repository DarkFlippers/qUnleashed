import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show Node, highlight;

import '../../theme.dart';
import '../../widgets/notification.dart';
import 'colors.dart';

class TextEditorPage extends StatefulWidget {
  const TextEditorPage({super.key, required this.remotePath, this.client});

  final String remotePath;
  final FlipperClient? client;

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<TextEditorPage> {
  late final _DartHighlightController _text;
  final ScrollController _scroll = ScrollController();
  late final FlipperClient _client;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = _DartHighlightController();
    _client = widget.client ?? FlipperOneClient().get();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final bytes = await _readBytes(widget.remotePath);
    if (!mounted) return;
    if (bytes == null) {
      setState(() {
        _loading = false;
        _error = 'Failed to read file';
      });
      return;
    }
    try {
      _text.text = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      _text.text = String.fromCharCodes(bytes);
    }
    setState(() => _loading = false);
  }

  Future<List<int>?> _readBytes(String remotePath) async {
    try {
      final batch = await _client.storageRead(
        ReadRequest(path: remotePath),
        timeout: const Duration(minutes: 5),
      );
      final bytes = <int>[];
      for (final r in batch.items) {
        if (r.hasFile()) bytes.addAll(r.file.data);
      }
      return bytes;
    } catch (e) {
      LogService.log('[TextEditor] read $remotePath failed: $e');
      return null;
    }
  }

  Future<bool> _writeBytes(String remotePath, List<int> data) async {
    try {
      await _client.storageWriteChunked(remotePath, data);
      return true;
    } catch (e) {
      LogService.log('[TextEditor] write $remotePath failed: $e');
      return false;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await _writeBytes(widget.remotePath, utf8.encode(_text.text));
    if (!mounted) return;
    setState(() => _saving = false);
    context.showNotification(
      ok ? 'Saved' : 'Save failed',
      type: ok ? QNotificationType.good : QNotificationType.error,
    );
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final name = widget.remotePath.split('/').last;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Save',
            onPressed: _saving || _loading ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : _error != null
          ? Center(
              child: Text(_error!, style: TextStyle(color: colors.danger)),
            )
          : Container(
              color:
                  dartEditorTheme['root']?.backgroundColor ??
                  colors.terminalBackground,
              child: TextField(
                controller: _text,
                scrollController: _scroll,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                cursorColor: colors.accent,
                style: _editorTextStyle(colors),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 12),
                ),
              ),
            ),
    );
  }

  TextStyle _editorTextStyle(QAppColors colors) {
    return TextStyle(
      color: dartEditorTheme['root']?.color ?? colors.terminalText,
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.4,
    );
  }
}

class _DartHighlightController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final rootStyle =
        style?.merge(dartEditorTheme['root']) ??
        const TextStyle().merge(dartEditorTheme['root']);
    return TextSpan(
      style: rootStyle.copyWith(backgroundColor: Colors.transparent),
      children: _convert(highlight.parse(text, language: 'dart').nodes ?? []),
    );
  }

  List<TextSpan> _convert(List<Node> nodes) {
    final spans = <TextSpan>[];
    for (final node in nodes) {
      spans.add(_convertNode(node));
    }
    return spans;
  }

  TextSpan _convertNode(Node node) {
    final value = node.value;
    if (value != null) {
      final style = _styleFor(node.className);
      if (_canApplyFunctionHints(node.className)) {
        return TextSpan(children: _highlightFunctionHints(value, style));
      }
      if (style == null) return TextSpan(text: value);
      return TextSpan(text: value, style: style);
    }

    final children = node.children;
    if (children == null || children.isEmpty) {
      return TextSpan(style: _styleFor(node.className));
    }

    return TextSpan(
      style: _styleFor(node.className),
      children: _convert(children),
    );
  }

  TextStyle? _styleFor(String? className) {
    if (className == null) return null;
    return dartEditorTheme[className] ??
        dartEditorTheme[className.replaceAll('.', '-')] ??
        dartEditorTheme[className.split('.').last] ??
        dartEditorTheme[className.split('-').last];
  }

  bool _canApplyFunctionHints(String? className) {
    return className == null || className == 'subst';
  }

  List<TextSpan> _highlightFunctionHints(String source, TextStyle? baseStyle) {
    final spans = <TextSpan>[];
    final matches = _functionPattern.allMatches(source).toList();
    var index = 0;

    for (final match in matches) {
      final name = match.namedGroup('name')!;
      final nameStart = match.start + match.group(0)!.lastIndexOf(name);
      if (nameStart < index) continue;

      if (nameStart > index) {
        spans.add(TextSpan(text: source.substring(index, nameStart), style: baseStyle));
      }

      spans.add(TextSpan(text: name, style: dartFunctionStyle));
      index = nameStart + name.length;
    }

    if (index < source.length) {
      spans.add(TextSpan(text: source.substring(index), style: baseStyle));
    }

    return spans;
  }

  static final _functionPattern = RegExp(
    r'(?:\b[A-Za-z_][A-Za-z0-9_]*\s*\.\s*)?(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(',
  );
}
