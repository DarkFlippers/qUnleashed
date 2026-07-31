class FamParseException implements Exception {
  const FamParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FamCall {
  const FamCall(this.name, this.args, this.kwargs);

  final String name;
  final List<Object?> args;
  final Map<String, Object?> kwargs;

  Object? operator [](String key) => kwargs[key];
}

class FamName {
  const FamName(this.value);

  final String value;

  String get tail => value.contains('.') ? value.split('.').last : value;

  @override
  String toString() => value;
}

class FamParser {
  FamParser(this._source);

  final String _source;
  int _pos = 0;

  static List<FamCall> parseCalls(String source, Set<String> names) {
    final parser = FamParser(source);
    final calls = <FamCall>[];
    while (true) {
      parser._skipTrivia();
      if (parser._eof) break;
      final value = parser._parseExpression();
      if (value is FamCall && names.contains(value.name)) calls.add(value);
      parser._skipStatementEnd();
    }
    return calls;
  }

  bool get _eof => _pos >= _source.length;

  String get _char => _source[_pos];

  void _skipTrivia() {
    while (!_eof) {
      final c = _char;
      if (c == '#') {
        while (!_eof && _char != '\n') {
          _pos++;
        }
      } else if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
        _pos++;
      } else if (c == '\\' &&
          _pos + 1 < _source.length &&
          _source[_pos + 1] == '\n') {
        _pos += 2;
      } else {
        return;
      }
    }
  }

  void _skipStatementEnd() {
    while (!_eof && (_char == ';' || _char == '\n' || _char == '\r')) {
      _pos++;
    }
  }

  bool _match(String token) {
    _skipTrivia();
    if (_source.startsWith(token, _pos)) {
      _pos += token.length;
      return true;
    }
    return false;
  }

  void _expect(String token) {
    if (!_match(token)) {
      throw FamParseException(
        'Expected "$token" at offset $_pos in application.fam',
      );
    }
  }

  Object? _parseExpression() => _parseAdditive();

  Object? _parseAdditive() {
    var left = _parseMultiplicative();
    while (true) {
      _skipTrivia();
      if (_eof) return left;
      final op = _char;
      if (op != '+' && op != '-') return left;
      _pos++;
      final right = _parseMultiplicative();
      left = _applyOperator(op, left, right);
    }
  }

  Object? _parseMultiplicative() {
    var left = _parseUnary();
    while (true) {
      _skipTrivia();
      if (_eof) return left;
      final op = _char;
      if (op != '*' && op != '/' && op != '%') return left;
      if (op == '*' && _source.startsWith('**', _pos)) return left;
      _pos++;
      final right = _parseUnary();
      left = _applyOperator(op, left, right);
    }
  }

  Object? _parseUnary() {
    _skipTrivia();
    if (!_eof && _char == '-') {
      _pos++;
      final value = _parseUnary();
      if (value is int) return -value;
      if (value is double) return -value;
      throw const FamParseException('Unary minus on a non-number');
    }
    return _parsePrimary();
  }

  Object? _applyOperator(String op, Object? left, Object? right) {
    if (left is num && right is num) {
      switch (op) {
        case '+':
          return _asNum(left + right);
        case '-':
          return _asNum(left - right);
        case '*':
          return _asNum(left * right);
        case '/':
          return left / right;
        case '%':
          return _asNum(left % right);
      }
    }
    if (op == '+' && left is String && right is String) return left + right;
    if (op == '+' && left is List && right is List) return [...left, ...right];
    throw FamParseException('Unsupported operation "$op" in application.fam');
  }

  static num _asNum(num value) =>
      value is double && value == value.roundToDouble() ? value.toInt() : value;

  Object? _parsePrimary() {
    _skipTrivia();
    if (_eof) {
      throw const FamParseException('Unexpected end of application.fam');
    }

    final c = _char;
    if (c == '"' || c == "'") return _parseString();
    if (c == '[') return _parseSequence(']');
    if (c == '(') {
      final items = _parseSequence(')');
      return items.length == 1 ? items.first : items;
    }
    if (c == '{') return _parseDict();
    if (_isDigit(c)) return _parseNumber();
    if (_isIdentStart(c)) return _parseIdentifierOrCall();

    throw FamParseException('Unexpected character "$c" in application.fam');
  }

  String _parseString() {
    final buffer = StringBuffer();
    while (true) {
      _skipTrivia();
      if (_eof) break;
      final quote = _char;
      if (quote != '"' && quote != "'") break;

      final triple = _source.startsWith(quote * 3, _pos);
      final terminator = triple ? quote * 3 : quote;
      _pos += terminator.length;

      while (!_eof && !_source.startsWith(terminator, _pos)) {
        if (_char == r'\') {
          _pos++;
          if (_eof) break;
          buffer.write(_unescape(_char));
          _pos++;
        } else {
          buffer.write(_char);
          _pos++;
        }
      }
      if (_eof) throw const FamParseException('Unterminated string');
      _pos += terminator.length;
    }
    return buffer.toString();
  }

  static String _unescape(String c) => switch (c) {
    'n' => '\n',
    't' => '\t',
    'r' => '\r',
    '0' => '\x00',
    _ => c,
  };

  List<Object?> _parseSequence(String closing) {
    _pos++;
    final items = <Object?>[];
    while (true) {
      _skipTrivia();
      if (_eof) throw const FamParseException('Unterminated sequence');
      if (_match(closing)) return items;
      items.add(_parseExpression());
      _skipTrivia();
      if (_match(',')) continue;
      _expect(closing);
      return items;
    }
  }

  Map<Object?, Object?> _parseDict() {
    _pos++;
    final map = <Object?, Object?>{};
    while (true) {
      _skipTrivia();
      if (_eof) throw const FamParseException('Unterminated dict');
      if (_match('}')) return map;
      final key = _parseExpression();
      _expect(':');
      map[key] = _parseExpression();
      _skipTrivia();
      if (_match(',')) continue;
      _expect('}');
      return map;
    }
  }

  Object? _parseNumber() {
    final start = _pos;
    var isDouble = false;
    if (_source.startsWith('0x', _pos) || _source.startsWith('0X', _pos)) {
      _pos += 2;
      while (!_eof && _isHexDigit(_char)) {
        _pos++;
      }
      return int.parse(_source.substring(start + 2, _pos), radix: 16);
    }
    while (!_eof && (_isDigit(_char) || _char == '_')) {
      _pos++;
    }
    if (!_eof && _char == '.') {
      isDouble = true;
      _pos++;
      while (!_eof && _isDigit(_char)) {
        _pos++;
      }
    }
    final text = _source.substring(start, _pos).replaceAll('_', '');
    return isDouble ? double.parse(text) : int.parse(text);
  }

  Object? _parseIdentifierOrCall() {
    final start = _pos;
    while (!_eof && (_isIdentPart(_char) || _char == '.')) {
      _pos++;
    }
    final name = _source.substring(start, _pos);

    final savedPos = _pos;
    _skipTrivia();
    if (!_eof && _char == '(') {
      final args = <Object?>[];
      final kwargs = <String, Object?>{};
      _pos++;
      while (true) {
        _skipTrivia();
        if (_eof) throw const FamParseException('Unterminated call');
        if (_match(')')) break;
        final keyword = _tryParseKeyword();
        if (keyword != null) {
          kwargs[keyword] = _parseExpression();
        } else {
          args.add(_parseExpression());
        }
        _skipTrivia();
        if (_match(',')) continue;
        _expect(')');
        break;
      }
      return FamCall(name, args, kwargs);
    }
    _pos = savedPos;

    return switch (name) {
      'True' => true,
      'False' => false,
      'None' => null,
      _ => FamName(name),
    };
  }

  String? _tryParseKeyword() {
    _skipTrivia();
    final start = _pos;
    if (_eof || !_isIdentStart(_char)) return null;
    var pos = _pos;
    while (pos < _source.length && _isIdentPart(_source[pos])) {
      pos++;
    }
    final name = _source.substring(start, pos);
    var probe = pos;
    while (probe < _source.length &&
        (_source[probe] == ' ' || _source[probe] == '\t')) {
      probe++;
    }
    if (probe >= _source.length || _source[probe] != '=') return null;
    if (probe + 1 < _source.length && _source[probe + 1] == '=') return null;
    _pos = probe + 1;
    return name;
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) ^ 0x30 <= 9;

  static bool _isHexDigit(String c) {
    final code = c.toLowerCase().codeUnitAt(0);
    return _isDigit(c) || (code >= 0x61 && code <= 0x66);
  }

  static bool _isIdentStart(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        c == '_';
  }

  static bool _isIdentPart(String c) => _isIdentStart(c) || _isDigit(c);
}
