import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../style.dart';

class EditorLineView extends LeafRenderObjectWidget {
  const EditorLineView({
    super.key,
    required this.span,
    required this.number,
    required this.modified,
    required this.gutterWidth,
    required this.onTapAtOffset,
  });

  final TextSpan span;
  final int number;
  final bool modified;
  final double gutterWidth;
  final void Function(int offset) onTapAtOffset;

  @override
  RenderEditorLine createRenderObject(BuildContext context) => RenderEditorLine(
    span: span,
    number: number,
    modified: modified,
    gutterWidth: gutterWidth,
    onTapAtOffset: onTapAtOffset,
  );

  @override
  void updateRenderObject(BuildContext context, RenderEditorLine renderObject) {
    renderObject
      ..span = span
      ..number = number
      ..modified = modified
      ..gutterWidth = gutterWidth
      ..onTapAtOffset = onTapAtOffset;
  }
}

class RenderEditorLine extends RenderBox {
  RenderEditorLine({
    required TextSpan span,
    required int number,
    required bool modified,
    required double gutterWidth,
    required this.onTapAtOffset,
  }) : _span = span,
       _number = number,
       _modified = modified,
       _gutterWidth = gutterWidth;

  static final Paint _modifiedFill = Paint()..color = kEditorModifiedBackground;
  static final Paint _modifiedBar = Paint()..color = kEditorModifiedForeground;
  static final TextStyle _numberStyle = kEditorGutterTextStyle.copyWith(
    color: kEditorGutterForeground,
  );
  static final TextStyle _modifiedNumberStyle = kEditorGutterTextStyle.copyWith(
    color: kEditorModifiedForeground,
  );

  final TextPainter _content = TextPainter(
    textDirection: TextDirection.ltr,
    strutStyle: kEditorStrutStyle,
    textScaler: TextScaler.noScaling,
  );
  final TextPainter _gutter = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  );

  late final TapGestureRecognizer _tap = TapGestureRecognizer(debugOwner: this)
    ..onTapDown = _handleTapDown;

  TextSpan _span;
  int _number;
  bool _modified;
  double _gutterWidth;
  void Function(int offset) onTapAtOffset;

  set span(TextSpan value) {
    if (identical(_span, value)) return;
    _span = value;
    markNeedsLayout();
  }

  set number(int value) {
    if (_number == value) return;
    _number = value;
    markNeedsLayout();
  }

  set modified(bool value) {
    if (_modified == value) return;
    _modified = value;
    markNeedsLayout();
  }

  set gutterWidth(double value) {
    if (_gutterWidth == value) return;
    _gutterWidth = value;
    markNeedsLayout();
  }

  double get _contentLeft => _gutterWidth + kEditorContentLeftPadding;

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    _content
      ..text = _span
      ..layout(
        maxWidth: max(0, width - _contentLeft - kEditorContentRightPadding),
      );
    _gutter
      ..text = TextSpan(
        text: '$_number',
        style: _modified ? _modifiedNumberStyle : _numberStyle,
      )
      ..layout();
    size = Size(width, _content.height);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    if (_modified) {
      canvas.drawRect(
        Rect.fromLTWH(offset.dx, offset.dy, _gutterWidth, size.height),
        _modifiedFill,
      );
      canvas.drawRect(
        Rect.fromLTWH(offset.dx, offset.dy, 2, size.height),
        _modifiedBar,
      );
    }
    _gutter.paint(
      canvas,
      Offset(
        offset.dx + _gutterWidth - kEditorGutterRightPadding - _gutter.width,
        offset.dy + (_content.preferredLineHeight - _gutter.height) / 2,
      ),
    );
    _content.paint(canvas, Offset(offset.dx + _contentLeft, offset.dy));
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) _tap.addPointer(event);
  }

  void _handleTapDown(TapDownDetails details) {
    final local = globalToLocal(details.globalPosition);
    onTapAtOffset(
      _content
          .getPositionForOffset(Offset(local.dx - _contentLeft, local.dy))
          .offset,
    );
  }

  @override
  void dispose() {
    _tap.dispose();
    _content.dispose();
    _gutter.dispose();
    super.dispose();
  }
}

class EditorLineField extends StatelessWidget {
  const EditorLineField({
    super.key,
    required this.number,
    required this.modified,
    required this.gutterWidth,
    required this.child,
  });

  final int number;
  final bool modified;
  final double gutterWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: gutterWidth + kEditorContentLeftPadding,
            right: kEditorContentRightPadding,
          ),
          child: SizedBox(width: double.infinity, child: child),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: gutterWidth,
          child: DecoratedBox(
            decoration: modified
                ? const BoxDecoration(
                    color: kEditorModifiedBackground,
                    border: Border(
                      left: BorderSide(
                        color: kEditorModifiedForeground,
                        width: 2,
                      ),
                    ),
                  )
                : const BoxDecoration(),
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(
                  right: kEditorGutterRightPadding,
                ),
                child: SizedBox(
                  height: editorLineExtent(),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$number',
                      style: kEditorGutterTextStyle.copyWith(
                        color: modified
                            ? kEditorModifiedForeground
                            : kEditorGutterForeground,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
