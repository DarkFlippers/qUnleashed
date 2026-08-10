import 'package:flutter/material.dart';

import '../../../theme/colors/editor.dart';
import 'style.dart';
import 'syntax.dart';

const int _kCacheLimit = 4096;
const int _kMaxRenderedChars = 2000;

final RegExp _kCodePattern = RegExp(
  r'(?<comment>//.*|/\*.*?\*/|/\*.*)'
  r'|(?<string>'
  r"'(?:\\.|[^'\\])*'?"
  r'|"(?:\\.|[^"\\])*"?'
  r'|`(?:\\.|[^`\\])*`?)'
  r'|(?<number>\b0[xX][0-9a-fA-F]+\b|\b\d+(?:\.\d+)?\b)'
  r'|(?<word>[A-Za-z_$][A-Za-z0-9_$]*)',
);

final RegExp _kDuckyPattern = RegExp(
  r'(?<comment>^\s*(?:REM\b|#).*)'
  r'|(?<number>\b\d+\b)'
  r'|(?<word>[A-Za-z_][A-Za-z0-9_]*)',
);

class LineHighlighter {
  LineHighlighter._({
    required this.theme,
    required RegExp pattern,
    required Set<String> keywords,
    required bool code,
  }) : _pattern = pattern,
       _keywords = keywords,
       _code = code;

  factory LineHighlighter.forFileName(String name) {
    if (name.toLowerCase().endsWith('.txt')) {
      return LineHighlighter._(
        theme: duckyscriptEditorTheme,
        pattern: _kDuckyPattern,
        keywords: duckyscriptCommands,
        code: false,
      );
    }
    return LineHighlighter._(
      theme: dartEditorTheme,
      pattern: _kCodePattern,
      keywords: codeKeywords,
      code: true,
    );
  }

  final Map<String, TextStyle> theme;
  final RegExp _pattern;
  final Set<String> _keywords;
  final bool _code;

  final Map<String, TextSpan> _cache = <String, TextSpan>{};

  TextSpan spanFor(String line) {
    final cached = _cache[line];
    if (cached != null) return cached;
    final span = _build(line);
    if (_cache.length >= _kCacheLimit) _cache.clear();
    _cache[line] = span;
    return span;
  }

  TextSpan _build(String line) {
    final source = line.length > _kMaxRenderedChars
        ? '${line.substring(0, _kMaxRenderedChars)}…'
        : line;
    if (source.isEmpty) {
      return const TextSpan(text: '', style: kEditorTextStyle);
    }

    List<TextSpan>? children;
    var plain = 0;
    for (final match in _pattern.allMatches(source)) {
      final style = _styleFor(match, source);
      if (style == null) continue;
      children ??= <TextSpan>[];
      if (match.start > plain) {
        children.add(TextSpan(text: source.substring(plain, match.start)));
      }
      children.add(TextSpan(text: match.group(0), style: style));
      plain = match.end;
    }
    if (children == null) {
      return TextSpan(text: source, style: kEditorTextStyle);
    }
    if (plain < source.length) {
      children.add(TextSpan(text: source.substring(plain)));
    }
    return TextSpan(style: kEditorTextStyle, children: children);
  }

  TextStyle? _styleFor(RegExpMatch match, String source) {
    if (match.namedGroup('comment') != null) return theme['comment'];
    if (_code && match.namedGroup('string') != null) return theme['string'];
    if (match.namedGroup('number') != null) return theme['number'];
    final word = match.namedGroup('word');
    if (word == null) return null;
    if (_keywords.contains(_code ? word : word.toUpperCase())) {
      return theme['keyword'];
    }
    if (!_code) return null;
    if (codeLiterals.contains(word)) return theme['literal'];
    if (codeBuiltIns.contains(word)) return theme['built_in'];
    return _isCall(source, match.end) ? dartFunctionStyle : null;
  }

  static bool _isCall(String source, int from) {
    for (var i = from; i < source.length; i++) {
      final code = source.codeUnitAt(i);
      if (code == 0x20 || code == 0x09) continue;
      return code == 0x28;
    }
    return false;
  }
}
