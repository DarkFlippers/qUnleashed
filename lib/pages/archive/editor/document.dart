class EditorDocument {
  EditorDocument._(this._lines, this._saved, this._origin);

  factory EditorDocument.fromText(String text) {
    final lines = text.split('\n');
    return EditorDocument._(
      List<String>.of(lines),
      List<String>.of(lines),
      List<int>.generate(lines.length, (i) => i),
    );
  }

  final List<String> _lines;
  final List<int> _origin;
  List<String> _saved;

  int get length => _lines.length;

  String lineAt(int index) => _lines[index];

  String get text => _lines.join('\n');

  bool isModified(int index) {
    final origin = _origin[index];
    if (origin < 0 || origin >= _saved.length) return true;
    return _lines[index] != _saved[origin];
  }

  void replace(int index, String value) => _lines[index] = value;

  void replaceWithLines(int index, List<String> parts) {
    _lines[index] = parts.first;
    if (parts.length == 1) return;
    final rest = parts.sublist(1);
    _lines.insertAll(index + 1, rest);
    _origin.insertAll(index + 1, List<int>.filled(rest.length, -1));
  }

  int mergeWithPrevious(int index) {
    final caret = _lines[index - 1].length;
    _lines[index - 1] = _lines[index - 1] + _lines[index];
    _lines.removeAt(index);
    _origin.removeAt(index);
    return caret;
  }

  void markSaved() {
    _saved = List<String>.of(_lines);
    for (var i = 0; i < _origin.length; i++) {
      _origin[i] = i;
    }
  }
}
