import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'document.dart';
import 'find.dart';
import 'style.dart';

class HexMetrics {
  const HexMetrics({
    required this.charWidth,
    required this.bytesPerRow,
    required this.offsetDigits,
  });

  final double charWidth;
  final int bytesPerRow;
  final int offsetDigits;

  double get byteWidth => charWidth * 2;

  double get cellStride => byteWidth + kHexCellGap;

  double get offsetWidth =>
      kHexEdgePadding + charWidth * offsetDigits + kHexOffsetGap;

  double hexCellLeft(int column) =>
      offsetWidth +
      column * cellStride +
      (column ~/ kHexGroupSize) * kHexGroupGap;

  double get hexAreaRight => hexCellLeft(bytesPerRow - 1) + byteWidth;

  double get asciiLeft => hexAreaRight + kHexPaneGap;

  double get asciiStride => charWidth + kHexAsciiCellGap;

  double asciiCellLeft(int column) => asciiLeft + column * asciiStride;

  double get totalWidth =>
      asciiCellLeft(bytesPerRow - 1) + charWidth + kHexEdgePadding;

  Rect hexCellRect(int column, double height) {
    final left = hexCellLeft(column);
    final previousRight = column == 0
        ? left - kHexCellGap
        : hexCellLeft(column - 1) + byteWidth;
    final nextLeft = column == bytesPerRow - 1
        ? left + byteWidth + kHexCellGap
        : hexCellLeft(column + 1);
    return Rect.fromLTRB(
      (left + previousRight) / 2,
      0,
      (left + byteWidth + nextLeft) / 2,
      height,
    );
  }

  Rect asciiCellRect(int column, double height) => Rect.fromLTWH(
    asciiCellLeft(column) - kHexAsciiCellGap / 2,
    0,
    asciiStride,
    height,
  );

  ({HexPane pane, int column})? cellAt(double x) {
    if (x >= asciiLeft - kHexPaneGap / 2) {
      final column = ((x - asciiLeft) / asciiStride).floor();
      return (pane: HexPane.ascii, column: column.clamp(0, bytesPerRow - 1));
    }
    if (x < offsetWidth) return (pane: HexPane.hex, column: 0);
    var best = 0;
    var bestDistance = double.infinity;
    for (var column = 0; column < bytesPerRow; column++) {
      final center = hexCellLeft(column) + byteWidth / 2;
      final distance = (x - center).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = column;
      }
    }
    return (pane: HexPane.hex, column: best);
  }

  static int resolveBytesPerRow(
    double width,
    double charWidth,
    int offsetDigits,
    int? requested,
  ) {
    if (requested != null) return requested;
    var best = kHexBytesPerRowChoices.first;
    for (final candidate in kHexBytesPerRowChoices) {
      final metrics = HexMetrics(
        charWidth: charWidth,
        bytesPerRow: candidate,
        offsetDigits: offsetDigits,
      );
      if (metrics.totalWidth > width) break;
      best = candidate;
    }
    return best;
  }
}

double? _charWidth;

double hexCharWidth() {
  if (_charWidth != null) return _charWidth!;
  final painter = TextPainter(
    text: const TextSpan(text: '0000000000000000', style: kHexTextStyle),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout();
  _charWidth = painter.width / 16;
  painter.dispose();
  return _charWidth!;
}

final Map<(String, Color), TextPainter> _glyphs = {};

TextPainter _glyph(String text, Color color) => _glyphs.putIfAbsent(
  (text, color),
  () => TextPainter(
    text: TextSpan(
      text: text,
      style: kHexTextStyle.copyWith(color: color),
    ),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout(),
);

/// The byte table itself: offsets, hex cells and the decoded column, with the
/// cursor, the selection and the search matches painted over them.
class HexTable extends StatefulWidget {
  const HexTable({
    super.key,
    required this.document,
    required this.find,
    required this.bytesPerRow,
    required this.selectionColor,
    required this.focusNode,
  });

  final HexDocument document;
  final HexFindController find;
  final int bytesPerRow;
  final Color selectionColor;
  final FocusNode focusNode;

  @override
  State<HexTable> createState() => HexTableState();
}

class HexTableState extends State<HexTable> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();
  final GlobalKey _bodyKey = GlobalKey();
  final ValueNotifier<bool> _caret = ValueNotifier<bool>(true);

  late Listenable _repaint;
  Timer? _blink;
  Timer? _autoScroll;
  double _autoScrollSpeed = 0;
  bool _dragging = false;
  int _lastCursor = -1;
  int _lastVersion = -1;

  @override
  void initState() {
    super.initState();
    _repaint = Listenable.merge([widget.document, widget.find, _caret]);
    widget.document.addListener(_onDocumentChanged);
    widget.focusNode.addListener(_onFocusChanged);
    _restartBlink();
  }

  @override
  void didUpdateWidget(covariant HexTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document ||
        oldWidget.find != widget.find) {
      oldWidget.document.removeListener(_onDocumentChanged);
      widget.document.addListener(_onDocumentChanged);
      _repaint = Listenable.merge([widget.document, widget.find, _caret]);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    _blink?.cancel();
    _autoScroll?.cancel();
    widget.document.removeListener(_onDocumentChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    _vertical.dispose();
    _horizontal.dispose();
    _caret.dispose();
    super.dispose();
  }

  int get bytesPerRow => widget.bytesPerRow;

  int get rowCount => widget.document.length ~/ bytesPerRow + 1;

  int get pageRows {
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    final height = box?.size.height ?? kHexRowHeight * 8;
    return max(1, (height / kHexRowHeight).floor() - 1);
  }

  void revealOffset(int offset, {bool animate = false}) {
    if (!_vertical.hasClients) return;
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    final height = box?.size.height ?? 0;
    if (height <= 0) return;
    final row = offset ~/ bytesPerRow;
    final top = row * kHexRowHeight;
    final bottom = top + kHexRowHeight;
    final position = _vertical.position;
    var target = position.pixels;
    if (top < position.pixels) {
      target = top;
    } else if (bottom > position.pixels + height) {
      target = bottom - height;
    } else {
      return;
    }
    target = target
        .clamp(
          position.minScrollExtent,
          max(position.minScrollExtent, position.maxScrollExtent),
        )
        .toDouble();
    if (animate) {
      _vertical.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else {
      _vertical.jumpTo(target);
    }
  }

  void _onDocumentChanged() {
    final document = widget.document;
    if (document.version != _lastVersion) {
      _lastVersion = document.version;
      setState(() {});
    }
    if (document.cursor == _lastCursor) return;
    _lastCursor = document.cursor;
    _restartBlink();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) revealOffset(document.cursor);
    });
  }

  void _onFocusChanged() {
    _restartBlink();
    if (mounted) setState(() {});
  }

  void _restartBlink() {
    _blink?.cancel();
    _caret.value = true;
    if (!widget.focusNode.hasFocus) return;
    _blink = Timer.periodic(const Duration(milliseconds: 530), (_) {
      _caret.value = !_caret.value;
    });
  }

  HexMetrics _metrics() => HexMetrics(
    charWidth: hexCharWidth(),
    bytesPerRow: bytesPerRow,
    offsetDigits: hexOffsetDigits(widget.document.length),
  );

  int? _offsetAt(Offset position, HexMetrics metrics, {required bool select}) {
    final row = ((position.dy + _vertical.offset) / kHexRowHeight).floor();
    if (row < 0) return 0;
    final cell = metrics.cellAt(position.dx);
    if (cell == null) return null;
    if (widget.document.pane != cell.pane) widget.document.pane = cell.pane;
    final offset = row * bytesPerRow + cell.column;
    final last = widget.document.length - (select ? 1 : 0);
    return offset.clamp(0, max(0, last));
  }

  Offset? _localInBody(Offset globalPosition) {
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.globalToLocal(globalPosition);
  }

  void _placeCursor(Offset globalPosition, HexMetrics metrics, bool extend) {
    final local = _localInBody(globalPosition);
    if (local == null) return;
    final offset = _offsetAt(local, metrics, select: extend);
    if (offset == null) return;
    widget.focusNode.requestFocus();
    widget.document.moveTo(offset, extend: extend);
    _restartBlink();
  }

  void _extendTo(Offset globalPosition, HexMetrics metrics) {
    final local = _localInBody(globalPosition);
    if (local == null) return;
    final offset = _offsetAt(local, metrics, select: true);
    if (offset == null) return;
    widget.document.moveTo(offset, extend: true);
    _updateAutoScroll(local);
  }

  void _updateAutoScroll(Offset local) {
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    final height = box?.size.height ?? 0;
    const edge = 24.0;
    if (local.dy < edge) {
      _autoScrollSpeed = -((edge - local.dy) / edge) * kHexRowHeight;
    } else if (local.dy > height - edge) {
      _autoScrollSpeed = ((local.dy - (height - edge)) / edge) * kHexRowHeight;
    } else {
      _autoScrollSpeed = 0;
    }
    if (_autoScrollSpeed == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_vertical.hasClients || !_dragging) return;
      final position = _vertical.position;
      final double target = (position.pixels + _autoScrollSpeed).clamp(
        position.minScrollExtent,
        max(position.minScrollExtent, position.maxScrollExtent),
      );
      if (target != position.pixels) _vertical.jumpTo(target);
    });
  }

  void _endDrag() {
    _dragging = false;
    _autoScrollSpeed = 0;
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _metrics();
        final width = max(metrics.totalWidth, constraints.maxWidth);
        return Scrollbar(
          controller: _horizontal,
          thumbVisibility: metrics.totalWidth > constraints.maxWidth,
          notificationPredicate: (notification) => notification.depth == 1,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  SizedBox(
                    height: kHexHeaderHeight,
                    child: CustomPaint(
                      size: Size(width, kHexHeaderHeight),
                      painter: _HexHeaderPainter(
                        document: widget.document,
                        metrics: metrics,
                        repaint: widget.document,
                      ),
                    ),
                  ),
                  Expanded(child: _buildBody(metrics, width)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(HexMetrics metrics, double width) {
    return Listener(
      onPointerDown: (event) {
        if (event.kind != PointerDeviceKind.mouse) return;
        if (event.buttons & kPrimaryMouseButton == 0) return;
        _dragging = true;
        _placeCursor(
          event.position,
          metrics,
          HardwareKeyboard.instance.isShiftPressed,
        );
      },
      onPointerMove: (event) {
        if (!_dragging || event.kind != PointerDeviceKind.mouse) return;
        if (event.buttons & kPrimaryMouseButton == 0) return;
        _extendTo(event.position, metrics);
      },
      onPointerUp: (event) => _endDrag(),
      onPointerCancel: (event) => _endDrag(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          if (details.kind == PointerDeviceKind.mouse) return;
          _placeCursor(details.globalPosition, metrics, false);
        },
        onLongPressStart: (details) {
          _dragging = true;
          _placeCursor(details.globalPosition, metrics, false);
          HapticFeedback.selectionClick();
        },
        onLongPressMoveUpdate: (details) =>
            _extendTo(details.globalPosition, metrics),
        onLongPressEnd: (details) => _endDrag(),
        child: Container(
          key: _bodyKey,
          color: kHexBackground,
          child: ListView.builder(
            controller: _vertical,
            itemExtent: kHexRowHeight,
            itemCount: rowCount,
            padding: EdgeInsets.zero,
            itemBuilder: (context, index) => CustomPaint(
              size: Size(width, kHexRowHeight),
              painter: _HexRowPainter(
                document: widget.document,
                find: widget.find,
                metrics: metrics,
                row: index,
                caret: _caret,
                focused: widget.focusNode.hasFocus,
                selectionColor: widget.selectionColor,
                repaint: _repaint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HexHeaderPainter extends CustomPainter {
  _HexHeaderPainter({
    required this.document,
    required this.metrics,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final HexDocument document;
  final HexMetrics metrics;

  static final Paint _background = Paint()..color = kHexHeaderBackground;
  static final Paint _divider = Paint()..color = kHexDivider;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _background);
    canvas.drawRect(Rect.fromLTWH(0, size.height - 1, size.width, 1), _divider);
    final activeColumn = document.cursor % metrics.bytesPerRow;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(0, 0, metrics.offsetWidth - kHexOffsetGap, size.height),
    );
    _paint(
      canvas,
      _glyph('ADDR', kHexHeaderForeground),
      kHexEdgePadding,
      size.height,
    );
    canvas.restore();
    for (var column = 0; column < metrics.bytesPerRow; column++) {
      final active = column == activeColumn;
      final glyph = _glyph(
        hexByteText(column),
        active ? kHexHeaderActiveForeground : kHexHeaderForeground,
      );
      _paint(canvas, glyph, metrics.hexCellLeft(column), size.height);
    }
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        metrics.asciiLeft,
        0,
        size.width - metrics.asciiLeft,
        size.height,
      ),
    );
    _paint(
      canvas,
      _glyph('DECODED', kHexHeaderForeground),
      metrics.asciiLeft,
      size.height,
    );
    canvas.restore();
  }

  void _paint(Canvas canvas, TextPainter glyph, double left, double height) {
    glyph.paint(canvas, Offset(left, (height - glyph.height) / 2));
  }

  @override
  bool shouldRepaint(covariant _HexHeaderPainter oldDelegate) =>
      oldDelegate.metrics != metrics || oldDelegate.document != document;
}

class _HexRowPainter extends CustomPainter {
  _HexRowPainter({
    required this.document,
    required this.find,
    required this.metrics,
    required this.row,
    required this.caret,
    required this.focused,
    required this.selectionColor,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final HexDocument document;
  final HexFindController find;
  final HexMetrics metrics;
  final int row;
  final ValueNotifier<bool> caret;
  final bool focused;
  final Color selectionColor;

  static final Paint _offsetBackground = Paint()..color = kHexOffsetBackground;
  static final Paint _stripe = Paint()..color = kHexRowStripe;
  static final Paint _currentRow = Paint()..color = kHexCurrentRow;
  static final Paint _modified = Paint()..color = kHexModifiedBackground;
  static final Paint _match = Paint()..color = kHexMatchBackground;
  static final Paint _currentMatch = Paint()
    ..color = kHexCurrentMatchBackground;
  static final Paint _cursorCell = Paint()..color = kHexCursorCellBackground;
  static final Paint _caretPaint = Paint()..color = kHexCaret;
  static final Paint _cursorBorder = Paint()
    ..color = kHexCursorBorder
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  static final Paint _idleBorder = Paint()
    ..color = kHexCursorIdleBorder
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final bytesPerRow = metrics.bytesPerRow;
    final base = row * bytesPerRow;
    final length = document.length;
    final cursor = document.cursor;
    final selection = document.selection;
    final currentMatch = find.currentMatch;
    final onCursorRow = cursor >= base && cursor < base + bytesPerRow;
    final selectionPaint = Paint()..color = selectionColor;

    if (onCursorRow) {
      canvas.drawRect(Offset.zero & size, _currentRow);
    } else if (row.isOdd) {
      canvas.drawRect(Offset.zero & size, _stripe);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, metrics.offsetWidth - kHexOffsetGap / 2, size.height),
      _offsetBackground,
    );
    if (base <= length) {
      final offsetGlyph = _glyph(
        hexOffsetText(base, metrics.offsetDigits),
        onCursorRow ? kHexOffsetFocusedForeground : kHexOffsetForeground,
      );
      offsetGlyph.paint(
        canvas,
        Offset(kHexEdgePadding, (size.height - offsetGlyph.height) / 2),
      );
    }

    final matches = find.matchesIn(base, base + bytesPerRow);
    final patternLength = find.patternLength;

    for (var column = 0; column < bytesPerRow; column++) {
      final offset = base + column;
      final hexRect = metrics.hexCellRect(column, size.height);
      final asciiRect = metrics.asciiCellRect(column, size.height);
      if (offset >= length) {
        if (offset == cursor && offset == length) {
          _paintCursor(canvas, hexRect, asciiRect, null);
        }
        continue;
      }
      final byte = document.byteAt(offset);
      final modified = document.isByteModified(offset);
      final selected = selection != null && selection.contains(offset);
      final inMatch = _covered(matches, patternLength, offset);
      final inCurrentMatch =
          currentMatch != null && currentMatch.contains(offset);

      if (modified) {
        canvas.drawRect(hexRect, _modified);
        canvas.drawRect(asciiRect, _modified);
      }
      if (inMatch) {
        final paint = inCurrentMatch ? _currentMatch : _match;
        canvas.drawRect(hexRect, paint);
        canvas.drawRect(asciiRect, paint);
      }
      if (selected) {
        canvas.drawRect(hexRect, selectionPaint);
        canvas.drawRect(asciiRect, selectionPaint);
      }

      final color = modified ? kHexModifiedForeground : hexByteColor(byte);
      final hexGlyph = _glyph(hexByteText(byte), color);
      hexGlyph.paint(
        canvas,
        Offset(
          metrics.hexCellLeft(column),
          (size.height - hexGlyph.height) / 2,
        ),
      );
      final printable = hexIsPrintable(byte);
      final asciiGlyph = _glyph(
        printable ? String.fromCharCode(byte) : '.',
        modified
            ? kHexModifiedForeground
            : (printable ? kHexBytePrintable : kHexPlaceholderForeground),
      );
      asciiGlyph.paint(
        canvas,
        Offset(
          metrics.asciiCellLeft(column),
          (size.height - asciiGlyph.height) / 2,
        ),
      );

      if (offset == cursor) {
        _paintCursor(canvas, hexRect, asciiRect, column);
      }
    }
  }

  void _paintCursor(Canvas canvas, Rect hexRect, Rect asciiRect, int? column) {
    final hexActive = document.pane == HexPane.hex;
    final activeRect = hexActive ? hexRect : asciiRect;
    final idleRect = hexActive ? asciiRect : hexRect;
    canvas.drawRect(activeRect, _cursorCell);
    canvas.drawRect(activeRect.deflate(0.5), _cursorBorder);
    canvas.drawRect(idleRect.deflate(0.5), _idleBorder);
    if (!focused || !caret.value) return;
    final double caretLeft;
    if (hexActive) {
      caretLeft = column == null
          ? hexRect.left + kHexCellGap / 2
          : metrics.hexCellLeft(column) + document.nibble * metrics.charWidth;
    } else {
      caretLeft = asciiRect.left + kHexAsciiCellGap / 2;
    }
    canvas.drawRect(
      Rect.fromLTWH(caretLeft, 2, 2, activeRect.height - 4),
      _caretPaint,
    );
  }

  bool _covered(List<int> matches, int patternLength, int offset) {
    for (final start in matches) {
      if (offset >= start && offset < start + patternLength) return true;
    }
    return false;
  }

  @override
  bool shouldRepaint(covariant _HexRowPainter oldDelegate) => true;
}
