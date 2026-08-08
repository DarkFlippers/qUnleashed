import 'package:flutter/material.dart';

const double kEditorFontSize = 13;
const double kEditorLineHeight = 1.4;
const double kEditorContentLeftPadding = 8;
const double kEditorContentRightPadding = 12;
const double kEditorGutterRightPadding = 6;

const TextStyle kEditorTextStyle = TextStyle(
  inherit: false,
  color: Color(0xffd6deeb),
  fontFamily: 'monospace',
  fontSize: kEditorFontSize,
  height: kEditorLineHeight,
  fontWeight: FontWeight.w400,
  fontStyle: FontStyle.normal,
  letterSpacing: 0,
  wordSpacing: 0,
  textBaseline: TextBaseline.alphabetic,
  leadingDistribution: TextLeadingDistribution.even,
  decoration: TextDecoration.none,
);

const StrutStyle kEditorStrutStyle = StrutStyle(
  fontFamily: 'monospace',
  fontSize: kEditorFontSize,
  height: kEditorLineHeight,
  fontWeight: FontWeight.w400,
  fontStyle: FontStyle.normal,
  leadingDistribution: TextLeadingDistribution.even,
  forceStrutHeight: true,
);

const TextStyle kEditorGutterTextStyle = TextStyle(
  inherit: false,
  fontFamily: 'monospace',
  fontSize: 11,
  fontWeight: FontWeight.w400,
  fontStyle: FontStyle.normal,
  letterSpacing: 0,
  wordSpacing: 0,
  textBaseline: TextBaseline.alphabetic,
  leadingDistribution: TextLeadingDistribution.even,
  decoration: TextDecoration.none,
);

const Color kEditorGutterBackground = Color(0xff0d1115);
const Color kEditorGutterForeground = Color(0xff4a5568);
const Color kEditorModifiedForeground = Color(0xffffa500);
const Color kEditorModifiedBackground = Color(0x15ffa500);

double? _lineExtent;

double editorLineExtent() {
  var value = _lineExtent;
  if (value != null) return value;
  final painter = TextPainter(
    text: const TextSpan(text: ' ', style: kEditorTextStyle),
    strutStyle: kEditorStrutStyle,
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout();
  value = painter.preferredLineHeight;
  painter.dispose();
  return _lineExtent = value;
}

double editorGutterWidth(int lineCount) {
  final digits = lineCount.toString().length;
  final width = digits * 7.5 + 14.0;
  return width < 34.0 ? 34.0 : width;
}
