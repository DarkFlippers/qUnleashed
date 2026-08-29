import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:re_editor/re_editor.dart';

import 'document.dart';
import 'style.dart';

/// Line numbers column, marking the lines that differ from the saved file.
class EditorLineNumbers extends LeafRenderObjectWidget {
  const EditorLineNumbers({
    super.key,
    required this.controller,
    required this.notifier,
    required this.document,
  });

  final CodeLineEditingController controller;
  final CodeIndicatorValueNotifier notifier;
  final EditorDocument document;

  @override
  RenderEditorLineNumbers createRenderObject(BuildContext context) =>
      RenderEditorLineNumbers(
        controller: controller,
        notifier: notifier,
        document: document,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderEditorLineNumbers renderObject,
  ) {
    renderObject
      ..controller = controller
      ..notifier = notifier
      ..document = document;
  }
}

class RenderEditorLineNumbers extends RenderBox {
  RenderEditorLineNumbers({
    required CodeLineEditingController controller,
    required CodeIndicatorValueNotifier notifier,
    required EditorDocument document,
  }) : _controller = controller,
       _notifier = notifier,
       _document = document,
       _lineCount = controller.lineCount;

  static final Paint _background = Paint()..color = kEditorGutterBackground;
  static final Paint _modifiedFill = Paint()..color = kEditorModifiedBackground;
  static final Paint _modifiedBar = Paint()..color = kEditorModifiedForeground;
  static const TextStyle _numberStyle = TextStyle(
    color: kEditorGutterForeground,
  );
  static const TextStyle _focusedNumberStyle = TextStyle(
    color: kEditorGutterFocusedForeground,
  );
  static const TextStyle _modifiedNumberStyle = TextStyle(
    color: kEditorModifiedForeground,
  );

  final TextPainter _painter = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  );

  CodeLineEditingController _controller;
  CodeIndicatorValueNotifier _notifier;
  EditorDocument _document;
  int _lineCount;

  set controller(CodeLineEditingController value) {
    if (_controller == value) return;
    if (attached) _controller.removeListener(_onCodeLinesChanged);
    _controller = value;
    if (attached) _controller.addListener(_onCodeLinesChanged);
    _onCodeLinesChanged();
  }

  set notifier(CodeIndicatorValueNotifier value) {
    if (_notifier == value) return;
    if (attached) _notifier.removeListener(markNeedsPaint);
    _notifier = value;
    if (attached) _notifier.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  set document(EditorDocument value) {
    if (_document == value) return;
    if (attached) _document.removeListener(markNeedsPaint);
    _document = value;
    if (attached) _document.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(covariant PipelineOwner owner) {
    _controller.addListener(_onCodeLinesChanged);
    _notifier.addListener(markNeedsPaint);
    _document.addListener(markNeedsPaint);
    super.attach(owner);
  }

  @override
  void detach() {
    _controller.removeListener(_onCodeLinesChanged);
    _notifier.removeListener(markNeedsPaint);
    _document.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is! PointerDownEvent) return;
    final position = globalToLocal(event.position);
    final paragraphs = _notifier.value?.paragraphs;
    if (paragraphs == null) return;
    for (final paragraph in paragraphs) {
      if (position.dy >= paragraph.top && position.dy < paragraph.bottom) {
        _controller.selectLine(paragraph.index);
        return;
      }
    }
  }

  @override
  void performLayout() {
    _painter
      ..text = TextSpan(
        text: '0' * max(kEditorMinNumberDigits, _lineCount.toString().length),
        style: kEditorGutterTextStyle,
      )
      ..layout();
    size = Size(
      _painter.width + kEditorGutterLeftPadding + kEditorGutterRightPadding,
      constraints.maxHeight,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    canvas.drawRect(offset & size, _background);
    final value = _notifier.value;
    if (value == null || value.paragraphs.isEmpty) return;
    canvas.save();
    canvas.clipRect(offset & size);
    for (final paragraph in value.paragraphs) {
      final top = offset.dy + paragraph.offset.dy;
      final modified = _document.isLineModified(paragraph.index);
      if (modified) {
        canvas.drawRect(
          Rect.fromLTWH(offset.dx, top, size.width, paragraph.height),
          _modifiedFill,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            offset.dx,
            top,
            kEditorModifiedBarWidth,
            paragraph.height,
          ),
          _modifiedBar,
        );
      }
      _painter
        ..text = TextSpan(
          text: '${paragraph.index + 1}',
          style: kEditorGutterTextStyle.merge(
            modified
                ? _modifiedNumberStyle
                : paragraph.index == value.focusedIndex
                ? _focusedNumberStyle
                : _numberStyle,
          ),
        )
        ..layout();
      _painter.paint(
        canvas,
        Offset(
          offset.dx + size.width - kEditorGutterRightPadding - _painter.width,
          top + (paragraph.preferredLineHeight - _painter.height) / 2,
        ),
      );
    }
    canvas.restore();
  }

  void _onCodeLinesChanged() {
    if (!attached) return;
    final count = _controller.lineCount;
    if (count == _lineCount) {
      markNeedsPaint();
      return;
    }
    final relayout =
        count.toString().length != _lineCount.toString().length;
    _lineCount = count;
    if (relayout) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }
}
