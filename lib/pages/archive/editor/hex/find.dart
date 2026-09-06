import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'document.dart';

enum HexSearchMode { hex, text }

class HexPattern {
  const HexPattern(this.values, this.masks);

  final Uint8List values;
  final Uint8List masks;

  int get length => values.length;
}

/// Search and replace over the bytes, in a hex pattern (with `?` wildcards) or
/// as text.
class HexFindController extends ChangeNotifier {
  HexFindController(this.document) {
    findInput.addListener(_onQueryChanged);
    document.addListener(_onDocumentChanged);
    _lastVersion = document.version;
  }

  final HexDocument document;
  final TextEditingController findInput = TextEditingController();
  final TextEditingController replaceInput = TextEditingController();
  final FocusNode findFocusNode = FocusNode();
  final FocusNode replaceFocusNode = FocusNode();

  bool _visible = false;
  bool _replaceMode = false;
  bool _matchCase = false;
  HexSearchMode _mode = HexSearchMode.hex;
  List<int> _matches = const [];
  int _index = -1;
  int _patternLength = 0;
  bool _invalid = false;
  int _lastVersion = 0;

  bool get visible => _visible;

  bool get replaceMode => _replaceMode;

  bool get matchCase => _matchCase;

  HexSearchMode get mode => _mode;

  List<int> get matches => _matches;

  int get index => _index;

  int get patternLength => _patternLength;

  bool get invalid => _invalid;

  HexRange? get currentMatch {
    if (_index < 0 || _index >= _matches.length) return null;
    return HexRange(_matches[_index], _matches[_index] + _patternLength);
  }

  /// Matches overlapping the `[start, end)` window, for a row of the table.
  List<int> matchesIn(int start, int end) {
    if (_patternLength == 0 || _matches.isEmpty) return const [];
    var low = 0;
    var high = _matches.length;
    final first = start - _patternLength + 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_matches[middle] < first) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final found = <int>[];
    for (var i = low; i < _matches.length && _matches[i] < end; i++) {
      found.add(_matches[i]);
    }
    return found;
  }

  void open({bool replace = false}) {
    _visible = true;
    if (replace) _replaceMode = true;
    _refresh();
    findFocusNode.requestFocus();
    notifyListeners();
  }

  void close() {
    if (!_visible) return;
    _visible = false;
    _matches = const [];
    _index = -1;
    notifyListeners();
  }

  void toggle() => _visible ? close() : open();

  void toggleReplaceMode() {
    _replaceMode = !_replaceMode;
    notifyListeners();
  }

  void toggleMatchCase() {
    _matchCase = !_matchCase;
    _refresh();
    notifyListeners();
  }

  void setMode(HexSearchMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _refresh();
    notifyListeners();
  }

  void next() {
    if (_matches.isEmpty) return;
    _index = (_index + 1) % _matches.length;
    _moveToMatch();
  }

  void previous() {
    if (_matches.isEmpty) return;
    _index = (_index - 1 + _matches.length) % _matches.length;
    _moveToMatch();
  }

  bool replaceCurrent() {
    final match = currentMatch;
    final replacement = _replacementBytes();
    if (match == null || replacement == null) return false;
    document.replaceRange(match.start, match.end, replacement);
    _refresh(preferOffset: match.start + replacement.length);
    notifyListeners();
    return true;
  }

  int replaceAll() {
    final replacement = _replacementBytes();
    if (replacement == null || _matches.isEmpty || _patternLength == 0) {
      return 0;
    }
    final targets = List<int>.from(_matches)..sort();
    for (var i = targets.length - 1; i >= 0; i--) {
      document.replaceRange(
        targets[i],
        targets[i] + _patternLength,
        replacement,
      );
    }
    _refresh();
    notifyListeners();
    return targets.length;
  }

  void refresh() {
    _refresh();
    notifyListeners();
  }

  void _onQueryChanged() {
    _refresh(preferOffset: document.cursor);
    notifyListeners();
  }

  void _onDocumentChanged() {
    if (document.version == _lastVersion) return;
    _lastVersion = document.version;
    if (!_visible) return;
    _refresh();
    notifyListeners();
  }

  void _moveToMatch() {
    final match = currentMatch;
    if (match == null) return;
    document.select(match.start, match.end);
    notifyListeners();
  }

  void _refresh({int? preferOffset}) {
    _lastVersion = document.version;
    final query = findInput.text;
    if (query.isEmpty) {
      _matches = const [];
      _index = -1;
      _patternLength = 0;
      _invalid = false;
      return;
    }
    final pattern = parseSearchPattern(query, _mode);
    if (pattern == null || pattern.length == 0) {
      _matches = const [];
      _index = -1;
      _patternLength = 0;
      _invalid = true;
      return;
    }
    _invalid = false;
    _patternLength = pattern.length;
    _matches = _search(pattern);
    if (_matches.isEmpty) {
      _index = -1;
      return;
    }
    final from = preferOffset ?? document.cursor;
    _index = _matches.indexWhere((offset) => offset >= from);
    if (_index < 0) _index = 0;
  }

  List<int> _search(HexPattern pattern) {
    final bytes = document.bytes;
    final ignoreCase = _mode == HexSearchMode.text && !_matchCase;
    final found = <int>[];
    final last = bytes.length - pattern.length;
    for (var start = 0; start <= last; start++) {
      var hit = true;
      for (var i = 0; i < pattern.length; i++) {
        final mask = pattern.masks[i];
        if (mask == 0) continue;
        final left = bytes[start + i] & mask;
        final right = pattern.values[i] & mask;
        if (left == right) continue;
        if (ignoreCase && _lowerAscii(left) == _lowerAscii(right)) continue;
        hit = false;
        break;
      }
      if (hit) found.add(start);
    }
    return found;
  }

  List<int>? _replacementBytes() {
    final text = replaceInput.text;
    if (_mode == HexSearchMode.text) return utf8.encode(text);
    final pattern = parseSearchPattern(text, HexSearchMode.hex);
    if (pattern == null) return null;
    if (pattern.masks.any((mask) => mask != 0xff)) return null;
    return pattern.values;
  }

  static int _lowerAscii(int byte) =>
      byte >= 0x41 && byte <= 0x5a ? byte + 0x20 : byte;

  @override
  void dispose() {
    document.removeListener(_onDocumentChanged);
    findInput.removeListener(_onQueryChanged);
    findInput.dispose();
    replaceInput.dispose();
    findFocusNode.dispose();
    replaceFocusNode.dispose();
    super.dispose();
  }
}

/// Parses the query typed in the find field: a hex byte string where `?` and
/// `??` stand for any nibble, or plain text encoded as UTF-8.
HexPattern? parseSearchPattern(String query, HexSearchMode mode) {
  if (mode == HexSearchMode.text) {
    final bytes = Uint8List.fromList(utf8.encode(query));
    return HexPattern(
      bytes,
      Uint8List(bytes.length)..fillRange(0, bytes.length, 0xff),
    );
  }
  final digits = <int>[];
  final wildcards = <bool>[];
  for (var i = 0; i < query.length; i++) {
    final code = query.codeUnitAt(i);
    if (code == 0x20 || code == 0x09 || code == 0x2c || code == 0x0a) continue;
    if (code == 0x3f) {
      digits.add(0);
      wildcards.add(true);
      continue;
    }
    if ((code == 0x78 || code == 0x58) &&
        digits.isNotEmpty &&
        digits.last == 0 &&
        !wildcards.last) {
      digits.removeLast();
      wildcards.removeLast();
      continue;
    }
    final value = _hexDigit(code);
    if (value == null) return null;
    digits.add(value);
    wildcards.add(false);
  }
  if (digits.isEmpty || digits.length.isOdd) return null;
  final count = digits.length ~/ 2;
  final values = Uint8List(count);
  final masks = Uint8List(count);
  for (var i = 0; i < count; i++) {
    final high = digits[i * 2];
    final low = digits[i * 2 + 1];
    values[i] = (high << 4) | low;
    masks[i] =
        (wildcards[i * 2] ? 0x00 : 0xf0) | (wildcards[i * 2 + 1] ? 0x00 : 0x0f);
  }
  return HexPattern(values, masks);
}

int? _hexDigit(int code) {
  if (code >= 0x30 && code <= 0x39) return code - 0x30;
  if (code >= 0x61 && code <= 0x66) return code - 0x61 + 10;
  if (code >= 0x41 && code <= 0x46) return code - 0x41 + 10;
  return null;
}
