import 'package:flutter/material.dart';

const double kEditorFontSize = 13;
const double kEditorLineHeight = 1.4;
const String kEditorFontFamily = 'monospace';
const double kEditorGutterLeftPadding = 8;
const double kEditorGutterRightPadding = 8;
const double kEditorModifiedBarWidth = 2;
const int kEditorMinNumberDigits = 3;

const TextStyle kEditorGutterTextStyle = TextStyle(
  inherit: false,
  fontFamily: kEditorFontFamily,
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
const Color kEditorGutterFocusedForeground = Color(0xffd6deeb);
const Color kEditorModifiedForeground = Color(0xffffa500);
const Color kEditorModifiedBackground = Color(0x15ffa500);
