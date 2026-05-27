import 'dart:convert';
import 'dart:math';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:highlight/highlight.dart' show Node, highlight;

import '../../theme.dart';
import '../../widgets/notification.dart';
import 'colors.dart';

const _kFontSize = 13.0;
const _kLineHeight = _kFontSize * 1.4;
const _kTopPadding = 12.0;
const _kLeftPadding = 8.0;
const _kRightPadding = 12.0;
const _kBottomPadding = 12.0;

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
  final GlobalKey _fieldKey = GlobalKey();
  late final FlipperClient _client;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<String> _savedLines = [];
  Set<int> _modifiedLines = {};
  int _lineCount = 1;

  // Y-координаты начала каждой физической строки, взятые прямо из RenderEditable.
  List<double> _lineY = [];

  double get _gutterWidth =>
      max(34.0, _lineCount.toString().length * 7.5 + 14.0);

  @override
  void initState() {
    super.initState();
    _text = _DartHighlightController();
    _client = widget.client ?? FlipperOneClient().get();
    _text.addListener(_onTextChanged);
    _load();
  }

  @override
  void dispose() {
    _text.removeListener(_onTextChanged);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // После каждого рендер-фрейма читаем позиции строк из RenderEditable.
  // getLocalRectForCaret возвращает Y относительно вьюпорта (уже вычтен scrollOffset).
  // Добавляем scrollOffset чтобы получить Y в координатах контента — они не меняются при скролле.
  void _readLinePositions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final re = _findRenderEditable(
        _fieldKey.currentContext?.findRenderObject(),
      );
      if (re == null) return;

      final scroll = _scroll.hasClients ? _scroll.offset : 0.0;
      final lines = _text.text.split('\n');
      final ys = <double>[];
      var offset = 0;
      for (final line in lines) {
        final viewportY = re.getLocalRectForCaret(TextPosition(offset: offset)).top;
        ys.add(viewportY + scroll); // конвертируем в контентные координаты
        offset += line.length + 1;
      }

      if (!listEquals(ys, _lineY)) {
        setState(() => _lineY = ys);
      }
    });
  }

  static RenderEditable? _findRenderEditable(RenderObject? ro) {
    if (ro is RenderEditable) return ro;
    RenderEditable? found;
    ro?.visitChildren((child) {
      found ??= _findRenderEditable(child);
    });
    return found;
  }

  void _onTextChanged() {
    final lines = _text.text.split('\n');
    final modified = _computeModified(_savedLines, lines);
    if (lines.length != _lineCount || !setEquals(modified, _modifiedLines)) {
      setState(() {
        _lineCount = lines.length;
        _modifiedLines = modified;
      });
    }
    _readLinePositions();
  }

  Set<int> _computeModified(List<String> saved, List<String> current) {
    var lo = 0;
    final minLen = min(saved.length, current.length);
    while (lo < minLen && saved[lo] == current[lo]) {
      lo++;
    }
    if (lo == saved.length && lo == current.length) return {};

    var hiS = saved.length;
    var hiC = current.length;
    while (hiS > lo && hiC > lo && saved[hiS - 1] == current[hiC - 1]) {
      hiS--;
      hiC--;
    }

    final s = saved.sublist(lo, hiS);
    final c = current.sublist(lo, hiC);
    final n = s.length;
    final m = c.length;
    if (n == 0) return {for (var i = lo; i < lo + m; i++) i};
    if (m == 0) return {};

    final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        dp[i][j] = s[i - 1] == c[j - 1]
            ? dp[i - 1][j - 1] + 1
            : max(dp[i - 1][j], dp[i][j - 1]);
      }
    }

    final modified = <int>{};
    var i = n, j = m;
    while (j > 0) {
      if (i > 0 && s[i - 1] == c[j - 1]) {
        i--;
        j--;
      } else if (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
        modified.add(lo + j - 1);
        j--;
      } else {
        i--;
      }
    }
    return modified;
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
    String decoded;
    try {
      decoded = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      decoded = String.fromCharCodes(bytes);
    }
    _savedLines = decoded.split('\n');
    _text.text = decoded;
    setState(() {
      _loading = false;
      _lineCount = _savedLines.length;
      _modifiedLines = {};
    });
    _readLinePositions();
  }

  Future<List<int>?> _readBytes(String path) async {
    try {
      final batch = await _client.storageRead(
        ReadRequest(path: path),
        timeout: const Duration(minutes: 5),
      );
      final bytes = <int>[];
      for (final r in batch.items) {
        if (r.hasFile()) bytes.addAll(r.file.data);
      }
      return bytes;
    } catch (e) {
      LogService.log('[TextEditor] read $path failed: $e');
      return null;
    }
  }

  Future<bool> _writeBytes(String path, List<int> data) async {
    try {
      await _client.storageWriteChunked(path, data);
      return true;
    } catch (e) {
      LogService.log('[TextEditor] write $path failed: $e');
      return false;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await _writeBytes(widget.remotePath, utf8.encode(_text.text));
    if (!mounted) return;
    if (ok) {
      _savedLines = _text.text.split('\n');
      setState(() {
        _saving = false;
        _modifiedLines = {};
      });
    } else {
      setState(() => _saving = false);
    }
    context.showNotification(
      ok ? 'Saved' : 'Save failed',
      type: ok ? QNotificationType.good : QNotificationType.error,
    );
    if (ok) Navigator.of(context).pop(true);
  }

  double _lastWidth = 0;

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
          ? Center(child: Text(_error!, style: TextStyle(color: colors.danger)))
          : Container(
              color:
                  dartEditorTheme['root']?.backgroundColor ??
                  colors.terminalBackground,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth != _lastWidth) {
                    _lastWidth = constraints.maxWidth;
                    _readLinePositions();
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Гаттер: цифры рисуются по Y из RenderEditable
                      AnimatedBuilder(
                        animation: _scroll,
                        builder: (context, _) => SizedBox(
                          width: _gutterWidth,
                          child: CustomPaint(
                            painter: _GutterPainter(
                              lineCount: _lineCount,
                              lineY: _lineY,
                              modifiedLines: _modifiedLines,
                              scrollOffset: _scroll.hasClients
                                  ? _scroll.offset
                                  : 0,
                            ),
                          ),
                        ),
                      ),
                      // Текстовое поле с переносами строк
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            _kLeftPadding,
                            _kTopPadding,
                            _kRightPadding,
                            _kBottomPadding,
                          ),
                          child: TextField(
                            key: _fieldKey,
                            controller: _text,
                            scrollController: _scroll,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            cursorColor: colors.accent,
                            style: const TextStyle(
                              color: Color(0xffd6deeb),
                              fontFamily: 'monospace',
                              fontSize: _kFontSize,
                              height: _kLineHeight / _kFontSize,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

class _GutterPainter extends CustomPainter {
  const _GutterPainter({
    required this.lineCount,
    required this.lineY,
    required this.modifiedLines,
    required this.scrollOffset,
  });

  final int lineCount;
  final List<double> lineY; // Y начала каждой физической строки из RenderEditable
  final Set<int> modifiedLines;
  final double scrollOffset;

  static const _bg = Color(0xff0d1115);
  static const _fg = Color(0xff4a5568);
  static const _modFg = Color(0xffffa500);
  static const _modBg = Color(0x15ffa500);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);

    for (var i = 0; i < lineCount; i++) {
      // Берём Y прямо из списка, заполненного из RenderEditable.
      // Fallback на арифметику только пока позиции ещё не пришли (первый кадр).
      final contentY = i < lineY.length ? lineY[i] : i * _kLineHeight;
      final top = _kTopPadding + contentY - scrollOffset;
      final bottom = top + _kLineHeight;
      if (bottom < 0 || top > size.height) continue;

      final modified = modifiedLines.contains(i);
      if (modified) {
        canvas.drawRect(
          Rect.fromLTWH(2, top, size.width - 2, _kLineHeight),
          Paint()..color = _modBg,
        );
        canvas.drawRect(
          Rect.fromLTWH(0, top, 2, _kLineHeight),
          Paint()..color = _modFg,
        );
      }

      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: modified ? _modFg : _fg,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(size.width - tp.width - 6, top + (_kLineHeight - tp.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_GutterPainter old) =>
      old.scrollOffset != scrollOffset ||
      old.lineCount != lineCount ||
      !setEquals(old.modifiedLines, modifiedLines) ||
      !listEquals(old.lineY, lineY);
}

class _DartHighlightController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final rootStyle = (style ?? const TextStyle()).merge(dartEditorTheme['root']);
    return TextSpan(
      style: rootStyle.copyWith(backgroundColor: Colors.transparent),
      children: _convert(
        highlight.parse(text, language: 'dart').nodes ?? [],
      ),
    );
  }

  static List<TextSpan> _convert(List<Node> nodes) =>
      nodes.map(_convertNode).toList();

  static TextSpan _convertNode(Node node) {
    final value = node.value;
    if (value != null) {
      final style = _styleFor(node.className);
      if (node.className == null || node.className == 'subst') {
        return TextSpan(children: _highlightFunctions(value, style));
      }
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

  static TextStyle? _styleFor(String? cls) {
    if (cls == null) return null;
    return dartEditorTheme[cls] ??
        dartEditorTheme[cls.replaceAll('.', '-')] ??
        dartEditorTheme[cls.split('.').last] ??
        dartEditorTheme[cls.split('-').last];
  }

  static final _fnPattern = RegExp(
    r'(?:\b[A-Za-z_][A-Za-z0-9_]*\s*\.\s*)?(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(',
  );

  static List<TextSpan> _highlightFunctions(String src, TextStyle? base) {
    final spans = <TextSpan>[];
    var idx = 0;
    for (final m in _fnPattern.allMatches(src)) {
      final name = m.namedGroup('name')!;
      final start = m.start + m.group(0)!.lastIndexOf(name);
      if (start < idx) continue;
      if (start > idx) {
        spans.add(TextSpan(text: src.substring(idx, start), style: base));
      }
      spans.add(TextSpan(text: name, style: dartFunctionStyle));
      idx = start + name.length;
    }
    if (idx < src.length) {
      spans.add(TextSpan(text: src.substring(idx), style: base));
    }
    return spans;
  }
}
