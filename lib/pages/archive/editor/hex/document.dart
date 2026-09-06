import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

const int kHexNewByte = 0xffffffff;

enum HexEditMode { overwrite, insert }

enum HexPane { hex, ascii }

@immutable
class HexRange {
  const HexRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;

  bool contains(int offset) => offset >= start && offset < end;

  bool overlaps(int start, int end) => start < this.end && end > this.start;
}

class _HexEdit {
  _HexEdit({
    required this.start,
    required this.removed,
    required this.removedOrigin,
    required this.inserted,
    required this.insertedOrigin,
    required this.cursorBefore,
    required this.nibbleBefore,
    required this.anchorBefore,
  });

  final int start;
  final Uint8List removed;
  final Uint32List removedOrigin;
  Uint8List inserted;
  Uint32List insertedOrigin;
  final int cursorBefore;
  final int nibbleBefore;
  final int? anchorBefore;
}

/// The bytes of the edited file, the cursor and the selection over them.
///
/// Every byte carries the index it came from in the saved snapshot, so an
/// insertion or a deletion shifts the marks with the bytes and only the bytes
/// that really differ from the file on disk are painted as modified.
class HexDocument extends ChangeNotifier {
  HexDocument(List<int> bytes)
    : _bytes = Uint8List.fromList(bytes),
      _saved = Uint8List.fromList(bytes),
      _origin = _identityOrigin(bytes.length);

  Uint8List _bytes;
  Uint8List _saved;
  Uint32List _origin;

  final List<_HexEdit> _undo = [];
  final List<_HexEdit> _redo = [];

  int _cursor = 0;
  int _nibble = 0;
  int? _anchor;
  int _modifiedCount = 0;
  int _version = 0;
  bool _mergeNibble = false;
  HexEditMode _mode = HexEditMode.overwrite;
  HexPane _pane = HexPane.hex;

  Uint8List get bytes => _bytes;

  int get length => _bytes.length;

  int get savedLength => _saved.length;

  int get cursor => _cursor;

  int get nibble => _nibble;

  int? get anchor => _anchor;

  int get modifiedCount => _modifiedCount;

  /// Bumped on every change of the bytes, so listeners can tell a real edit
  /// from a cursor move.
  int get version => _version;

  bool get isModified => _modifiedCount > 0 || _bytes.length != _saved.length;

  bool get canUndo => _undo.isNotEmpty;

  bool get canRedo => _redo.isNotEmpty;

  HexEditMode get mode => _mode;

  HexPane get pane => _pane;

  set mode(HexEditMode value) {
    if (_mode == value) return;
    _mode = value;
    _mergeNibble = false;
    notifyListeners();
  }

  set pane(HexPane value) {
    if (_pane == value) return;
    _pane = value;
    _nibble = 0;
    _mergeNibble = false;
    notifyListeners();
  }

  int byteAt(int index) => _bytes[index];

  Uint8List range(int start, int end) =>
      Uint8List.fromList(_bytes.sublist(start, end));

  bool isByteModified(int index) {
    final origin = _origin[index];
    return origin == kHexNewByte || _saved[origin] != _bytes[index];
  }

  HexRange? get selection {
    final anchor = _anchor;
    if (anchor == null || _bytes.isEmpty) return null;
    final start = min(anchor, _cursor);
    final end = min(max(anchor, _cursor) + 1, _bytes.length);
    if (end <= start) return null;
    return HexRange(start, end);
  }

  Uint8List get selectedBytes {
    final range = selection;
    if (range == null) return Uint8List(0);
    return Uint8List.fromList(_bytes.sublist(range.start, range.end));
  }

  void moveTo(int offset, {int nibble = 0, bool extend = false}) {
    final target = offset.clamp(0, _bytes.length);
    if (extend) {
      _anchor ??= _cursor;
    } else {
      _anchor = null;
    }
    _cursor = target;
    _nibble = target >= _bytes.length ? 0 : nibble;
    _mergeNibble = false;
    notifyListeners();
  }

  void moveBy(int delta, {bool extend = false}) =>
      moveTo(_cursor + delta, extend: extend);

  void moveNibble(int delta, {bool extend = false}) {
    if (_pane == HexPane.ascii || _bytes.isEmpty) {
      moveBy(delta, extend: extend);
      return;
    }
    var position = _cursor * 2 + _nibble + delta;
    if (position < 0) position = 0;
    moveTo(position ~/ 2, nibble: position % 2, extend: extend);
  }

  void select(int start, int end) {
    if (_bytes.isEmpty || end <= start) return;
    _anchor = start.clamp(0, _bytes.length - 1);
    _cursor = (end - 1).clamp(0, _bytes.length - 1);
    _nibble = 0;
    _mergeNibble = false;
    notifyListeners();
  }

  void selectAll() => select(0, _bytes.length);

  void clearSelection() {
    if (_anchor == null) return;
    _anchor = null;
    notifyListeners();
  }

  void inputNibble(int value) {
    _anchor = null;
    final offset = _cursor;
    if (offset >= _bytes.length ||
        (_mode == HexEditMode.insert && _nibble == 0)) {
      _apply(
        offset,
        offset,
        Uint8List.fromList([value << 4]),
        Uint32List.fromList([kHexNewByte]),
      );
      _nibble = 1;
      _mergeNibble = true;
      notifyListeners();
      return;
    }
    final current = _bytes[offset];
    final updated = _nibble == 0
        ? (current & 0x0f) | (value << 4)
        : (current & 0xf0) | value;
    _apply(
      offset,
      offset + 1,
      Uint8List.fromList([updated]),
      Uint32List.fromList([_origin[offset]]),
      mergeWithPrevious: _nibble == 1 && _mergeNibble,
    );
    if (_nibble == 0) {
      _nibble = 1;
      _mergeNibble = true;
    } else {
      _nibble = 0;
      _cursor = offset + 1;
      _mergeNibble = false;
    }
    notifyListeners();
  }

  void inputByte(int value) {
    _anchor = null;
    final offset = _cursor;
    final overwrite = _mode == HexEditMode.overwrite && offset < _bytes.length;
    _apply(
      offset,
      overwrite ? offset + 1 : offset,
      Uint8List.fromList([value & 0xff]),
      Uint32List.fromList([overwrite ? _origin[offset] : kHexNewByte]),
    );
    _cursor = offset + 1;
    _nibble = 0;
    _mergeNibble = false;
    notifyListeners();
  }

  void writeBytes(int offset, List<int> data, {required bool insert}) {
    if (data.isEmpty) return;
    final start = offset.clamp(0, _bytes.length);
    final end = insert ? start : min(start + data.length, _bytes.length);
    final origin = Uint32List(data.length);
    for (var i = 0; i < data.length; i++) {
      origin[i] = start + i < end ? _origin[start + i] : kHexNewByte;
    }
    _apply(start, end, Uint8List.fromList(data), origin);
    _anchor = null;
    _cursor = start + data.length;
    _nibble = 0;
    _mergeNibble = false;
    notifyListeners();
  }

  void replaceRange(int start, int end, List<int> data) {
    final from = start.clamp(0, _bytes.length);
    final to = end.clamp(from, _bytes.length);
    _apply(
      from,
      to,
      Uint8List.fromList(data),
      Uint32List(data.length)..fillRange(0, data.length, kHexNewByte),
    );
    _anchor = null;
    _cursor = from + data.length;
    _nibble = 0;
    _mergeNibble = false;
    notifyListeners();
  }

  void deleteRange(int start, int end) {
    final from = start.clamp(0, _bytes.length);
    final to = end.clamp(from, _bytes.length);
    if (to == from) return;
    _apply(from, to, Uint8List(0), Uint32List(0));
    _anchor = null;
    _cursor = from;
    _nibble = 0;
    _mergeNibble = false;
    notifyListeners();
  }

  void deleteSelection() {
    final range = selection;
    if (range == null) return;
    deleteRange(range.start, range.end);
  }

  void backspace() {
    final range = selection;
    if (range != null) {
      deleteRange(range.start, range.end);
      return;
    }
    if (_cursor == 0) return;
    deleteRange(_cursor - 1, _cursor);
  }

  void deleteForward() {
    final range = selection;
    if (range != null) {
      deleteRange(range.start, range.end);
      return;
    }
    if (_cursor >= _bytes.length) return;
    deleteRange(_cursor, _cursor + 1);
  }

  void fillRange(int start, int end, int value) {
    final from = start.clamp(0, _bytes.length);
    final to = end.clamp(from, _bytes.length);
    if (to == from) return;
    final data = Uint8List(to - from)..fillRange(0, to - from, value & 0xff);
    _apply(from, to, data, Uint32List.fromList(_origin.sublist(from, to)));
    _cursor = from;
    _nibble = 0;
    _mergeNibble = false;
    notifyListeners();
  }

  void insertZeros(int offset, int count, int value) {
    if (count <= 0) return;
    final data = Uint8List(count)..fillRange(0, count, value & 0xff);
    writeBytes(offset, data, insert: true);
  }

  void undo() {
    if (_undo.isEmpty) return;
    final edit = _undo.removeLast();
    _apply(
      edit.start,
      edit.start + edit.inserted.length,
      edit.removed,
      edit.removedOrigin,
      record: false,
    );
    _redo.add(edit);
    _cursor = edit.cursorBefore.clamp(0, _bytes.length);
    _nibble = edit.nibbleBefore;
    _anchor = edit.anchorBefore?.clamp(0, max(0, _bytes.length - 1));
    _mergeNibble = false;
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final edit = _redo.removeLast();
    _apply(
      edit.start,
      edit.start + edit.removed.length,
      edit.inserted,
      edit.insertedOrigin,
      record: false,
    );
    _undo.add(edit);
    _cursor = (edit.start + edit.inserted.length).clamp(0, _bytes.length);
    _nibble = 0;
    _anchor = null;
    _mergeNibble = false;
    notifyListeners();
  }

  void markSaved() {
    _saved = Uint8List.fromList(_bytes);
    _origin = _identityOrigin(_bytes.length);
    _version++;
    _undo.clear();
    _redo.clear();
    _modifiedCount = 0;
    _mergeNibble = false;
    notifyListeners();
  }

  void _apply(
    int start,
    int end,
    Uint8List insert,
    Uint32List insertOrigin, {
    bool record = true,
    bool mergeWithPrevious = false,
  }) {
    if (record) {
      final merged = mergeWithPrevious && _undo.isNotEmpty ? _undo.last : null;
      if (merged != null &&
          merged.start == start &&
          merged.inserted.length == end - start) {
        merged.inserted = insert;
        merged.insertedOrigin = insertOrigin;
      } else {
        _undo.add(
          _HexEdit(
            start: start,
            removed: Uint8List.fromList(_bytes.sublist(start, end)),
            removedOrigin: Uint32List.fromList(_origin.sublist(start, end)),
            inserted: insert,
            insertedOrigin: insertOrigin,
            cursorBefore: _cursor,
            nibbleBefore: _nibble,
            anchorBefore: _anchor,
          ),
        );
      }
      _redo.clear();
    }
    final tail = _bytes.length - end;
    final bytes = Uint8List(start + insert.length + tail);
    final origin = Uint32List(bytes.length);
    bytes.setRange(0, start, _bytes);
    origin.setRange(0, start, _origin);
    bytes.setRange(start, start + insert.length, insert);
    origin.setRange(start, start + insert.length, insertOrigin);
    bytes.setRange(start + insert.length, bytes.length, _bytes, end);
    origin.setRange(start + insert.length, bytes.length, _origin, end);
    _bytes = bytes;
    _origin = origin;
    _version++;
    _countModified();
  }

  void _countModified() {
    var count = 0;
    for (var i = 0; i < _bytes.length; i++) {
      final origin = _origin[i];
      if (origin == kHexNewByte || _saved[origin] != _bytes[i]) count++;
    }
    _modifiedCount = count;
  }

  static Uint32List _identityOrigin(int length) {
    final origin = Uint32List(length);
    for (var i = 0; i < length; i++) {
      origin[i] = i;
    }
    return origin;
  }
}
