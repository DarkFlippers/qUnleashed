import 'dart:math';

import 'package:diffutil_dart/diffutil.dart';
import 'package:flutter/foundation.dart';
import 'package:re_editor/re_editor.dart';

/// Keeps the last saved snapshot of the file and tells which lines differ from
/// it, so the gutter can mark them.
///
/// The lines are diffed against the snapshot, so only the lines that were
/// really edited, added or split are marked, whatever the edit was.
class EditorDocument extends ChangeNotifier {
  EditorDocument.fromText(String text) : _saved = text.textLines;

  List<String> _saved;
  CodeLines? _lines;
  List<bool> _marks = const [];

  bool get isModified => _marks.contains(true);

  bool isLineModified(int index) =>
      index >= 0 && index < _marks.length && _marks[index];

  void update(CodeLines lines) {
    if (identical(_lines, lines)) return;
    _lines = lines;
    _marks = _diff(_saved, _linesOf(lines));
    notifyListeners();
  }

  void markSaved(CodeLines lines) {
    _saved = _linesOf(lines);
    _lines = lines;
    if (_marks.isEmpty) return;
    _marks = const [];
    notifyListeners();
  }

  static List<String> _linesOf(CodeLines lines) => [
    for (final segment in lines.segments)
      for (final line in segment) line.text,
  ];

  /// Replays the edit operations on a list of marks, so every line of [current]
  /// ends up marked only if it is not carried over from [saved].
  ///
  /// The lines shared at both ends are cut off first: they can never be part of
  /// an edit, and diffing only the window between them keeps a keystroke in a
  /// long file cheap.
  static List<bool> _diff(List<String> saved, List<String> current) {
    final common = min(saved.length, current.length);
    var head = 0;
    while (head < common && saved[head] == current[head]) {
      head++;
    }
    var tail = 0;
    while (tail < common - head &&
        saved[saved.length - 1 - tail] == current[current.length - 1 - tail]) {
      tail++;
    }

    final savedWindow = saved.sublist(head, saved.length - tail);
    final marks = List<bool>.filled(savedWindow.length, false, growable: true);
    final updates = calculateListDiff<String>(
      savedWindow,
      current.sublist(head, current.length - tail),
      detectMoves: false,
    ).getUpdates();
    for (final update in updates) {
      update.when(
        insert: (position, count) =>
            marks.insertAll(position, List<bool>.filled(count, true)),
        remove: (position, count) =>
            marks.removeRange(position, position + count),
        change: (position, _) => marks[position] = true,
        move: (from, to) => marks.insert(to, marks.removeAt(from)),
      );
    }
    return [
      ...List<bool>.filled(head, false),
      ...marks,
      ...List<bool>.filled(tail, false),
    ];
  }
}
