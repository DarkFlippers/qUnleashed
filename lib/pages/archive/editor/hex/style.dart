import 'package:flutter/material.dart';

import '../style.dart';

const double kHexFontSize = 13;
const double kHexRowHeight = 20;
const double kHexHeaderHeight = 26;
const double kHexEdgePadding = 10;
const double kHexOffsetGap = 12;
const double kHexCellGap = 5;
const double kHexGroupGap = 9;
const int kHexGroupSize = 8;
const double kHexPaneGap = 16;
const double kHexAsciiCellGap = 1;
const int kHexMinOffsetDigits = 4;
const List<int> kHexBytesPerRowChoices = [4, 8, 16, 24, 32, 48, 64];

const TextStyle kHexTextStyle = TextStyle(
  inherit: false,
  fontFamily: kEditorFontFamily,
  fontSize: kHexFontSize,
  fontWeight: FontWeight.w400,
  fontStyle: FontStyle.normal,
  letterSpacing: 0,
  wordSpacing: 0,
  textBaseline: TextBaseline.alphabetic,
  leadingDistribution: TextLeadingDistribution.even,
  decoration: TextDecoration.none,
  height: 1,
);

const Color kHexBackground = Color(0xff101317);
const Color kHexHeaderBackground = Color(0xff0d1115);
const Color kHexOffsetBackground = Color(0xff0d1115);
const Color kHexDivider = Color(0xff1c2229);
const Color kHexOffsetForeground = Color(0xff4a5568);
const Color kHexOffsetFocusedForeground = Color(0xffd6deeb);
const Color kHexHeaderForeground = Color(0xff566370);
const Color kHexHeaderActiveForeground = Color(0xffffcb6b);
const Color kHexRowStripe = Color(0x06ffffff);
const Color kHexCurrentRow = Color(0x0dffffff);
const Color kHexMatchBackground = Color(0x59ffcb6b);
const Color kHexCurrentMatchBackground = Color(0x99ffcb6b);
const Color kHexCursorCellBackground = Color(0x33ffffff);
const Color kHexCursorBorder = Color(0xff82aaff);
const Color kHexCursorIdleBorder = Color(0x5582aaff);
const Color kHexCaret = Color(0xff82aaff);
const Color kHexModifiedForeground = kEditorModifiedForeground;
const Color kHexModifiedBackground = kEditorModifiedBackground;
const Color kHexPlaceholderForeground = Color(0xff2b333c);

const Color kHexByteZero = Color(0xff44505c);
const Color kHexByteWhitespace = Color(0xff7fdbca);
const Color kHexByteControl = Color(0xffc792ea);
const Color kHexBytePrintable = Color(0xffc3e88d);
const Color kHexByteHigh = Color(0xff9aaec4);
const Color kHexByteFull = Color(0xffff5874);

/// Colour a byte gets in the table, so a glance tells zeros, text, control
/// bytes and 0xFF padding apart.
Color hexByteColor(int byte) {
  if (byte == 0x00) return kHexByteZero;
  if (byte == 0xff) return kHexByteFull;
  if (byte == 0x09 ||
      byte == 0x0a ||
      byte == 0x0b ||
      byte == 0x0c ||
      byte == 0x0d ||
      byte == 0x20) {
    return kHexByteWhitespace;
  }
  if (byte < 0x20 || byte == 0x7f) return kHexByteControl;
  if (byte < 0x7f) return kHexBytePrintable;
  return kHexByteHigh;
}

bool hexIsPrintable(int byte) => byte >= 0x20 && byte < 0x7f;

String hexByteText(int byte) =>
    byte.toRadixString(16).toUpperCase().padLeft(2, '0');

String hexOffsetText(int offset, int digits) =>
    offset.toRadixString(16).toUpperCase().padLeft(digits, '0');

int hexOffsetDigits(int length) {
  final digits = (length <= 1 ? 1 : length - 1).toRadixString(16).length;
  return digits < kHexMinOffsetDigits ? kHexMinOffsetDigits : digits;
}
