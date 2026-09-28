import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/paint/constants.dart';
import 'package:qunleashed/pages/tools/paint/editor/controller.dart';
import 'package:qunleashed/pages/tools/paint/virtual_display_session.dart';

/// The Pixel Draw canvas: what a stroke does and what undo gives back.
///
/// 606 lines of pixel logic with one external dependency — the virtual display
/// the canvas streams to — and no tests. Undo is the one a user notices
/// immediately: a stack that captures the wrong moment loses the stroke they
/// wanted back, or gives back one they did not.
///
/// Everything below works on the pixels directly. The display is a fake
/// because the shared session reaches for the app's client and would put a
/// real display on a real Flipper.
class FakeDisplayClient implements FlipperClient {
  final _connection = StreamController<FlipperConnectionState>.broadcast();

  Future<void> close() => _connection.close();

  @override
  bool get isConnected => false;

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeDisplayClient displayClient;
  late PaintController paint;

  setUp(() {
    displayClient = FakeDisplayClient();
    paint = PaintController(
      display: VirtualDisplaySession.forTest(displayClient),
    );
    addTearDown(() async {
      paint.dispose();
      await displayClient.close();
    });
  });

  int at(int x, int y) => paint.currentPixels[y * kCanvasWidth + x];

  /// One pencil stroke on a single pixel, as the page drives it.
  void tap(int x, int y, {int pointer = 1}) {
    paint
      ..onPointerDown(x, y, pointer)
      ..onPointerUp(x, y, pointer);
  }

  group('a stroke', () {
    test('marks the pixel it was drawn on', () {
      tap(3, 4);

      expect(at(3, 4), 1);
    });

    test('leaves its neighbours alone', () {
      tap(3, 4);

      expect(at(2, 4), 0);
      expect(at(4, 4), 0);
      expect(at(3, 3), 0);
    });

    // A second finger mid-stroke is a palm, not a second line. Taking it would
    // draw a stray mark wherever the hand rested.
    test('ignores a second pointer while one is down', () {
      paint.onPointerDown(3, 4, 1);
      paint.onPointerDown(60, 30, 2);

      expect(at(60, 30), 0);
    });

    test('is one undo entry, not one per pixel moved through', () {
      paint
        ..onPointerDown(3, 4, 1)
        ..onPointerMove(5, 4, 1)
        ..onPointerMove(7, 4, 1)
        ..onPointerUp(7, 4, 1);
      expect(at(7, 4), 1, reason: 'the stroke reached there');

      paint.undo();

      expect(at(3, 4), 0);
      expect(at(7, 4), 0);
      expect(paint.canUndo, isFalse);
    });
  });

  group('the eraser', () {
    test('clears what the pencil drew', () {
      tap(3, 4);

      paint.tool = DrawTool.eraser;
      tap(3, 4, pointer: 2);

      expect(at(3, 4), 0);
    });
  });

  group('undo', () {
    test('has nothing to give back on an untouched canvas', () {
      expect(paint.canUndo, isFalse);
      expect(paint.canRedo, isFalse);
    });

    test('gives back one stroke at a time', () {
      tap(1, 1);
      tap(2, 2, pointer: 2);

      paint.undo();
      expect(at(2, 2), 0);
      expect(at(1, 1), 1, reason: 'only the last stroke came back');

      paint.undo();
      expect(at(1, 1), 0);
    });

    test('is undone by redo', () {
      tap(1, 1);
      paint.undo();

      paint.redo();

      expect(at(1, 1), 1);
    });

    // Redo is what was undone, not a branch. Drawing after an undo abandons
    // the future, and offering it back would put a stroke the user replaced
    // on top of the one they replaced it with.
    test('loses its redo once something new is drawn', () {
      tap(1, 1);
      paint.undo();
      expect(paint.canRedo, isTrue, reason: 'the starting point');

      tap(5, 5, pointer: 2);

      expect(paint.canRedo, isFalse);
    });

    // The stack is capped, so the oldest strokes fall off rather than growing
    // a copy of the canvas per stroke forever.
    test('remembers a bounded number of strokes', () {
      for (var i = 0; i < kMaxUndo + 5; i++) {
        tap(i, 1, pointer: i + 1);
      }

      for (var i = 0; i < kMaxUndo; i++) {
        paint.undo();
      }

      expect(paint.canUndo, isFalse);
      expect(at(0, 1), 1, reason: 'the oldest strokes fell off the stack');
    });

    // The stack holds copies. Sharing the buffers would mean the next stroke
    // edited the history along with the canvas.
    test('is not edited by what happens after it', () {
      tap(1, 1);
      tap(2, 2, pointer: 2);
      tap(3, 3, pointer: 3);

      paint.undo();
      paint.undo();

      expect(at(1, 1), 1);
      expect(at(2, 2), 0);
      expect(at(3, 3), 0);
    });
  });

  group('the fill', () {
    setUp(() => paint.tool = DrawTool.fill);

    test('covers the whole empty canvas from one tap', () {
      tap(0, 0);

      expect(at(0, 0), 1);
      expect(at(kCanvasWidth - 1, kCanvasHeight - 1), 1);
    });

    // It spreads through sides, not corners: a diagonal line is a wall, which
    // is what makes a drawn outline hold the paint in.
    test('does not leak through a diagonal', () {
      paint.tool = DrawTool.pencil;
      for (var i = 0; i < kCanvasHeight; i++) {
        tap(i, i, pointer: i + 1);
      }

      paint.tool = DrawTool.fill;
      tap(0, kCanvasHeight - 1, pointer: 500);

      expect(
        at(kCanvasWidth - 1, 0),
        0,
        reason: 'the far side of the diagonal was not reached',
      );
      expect(at(0, kCanvasHeight - 1), 1);
    });

    // The early return for a region already that colour is an optimisation,
    // not a behaviour: without it the walk visits the same region and writes
    // the same value, so the canvas is identical either way. Removing it
    // fails nothing, and there is no case claiming otherwise.
    test('leaves a region that is already that colour as it was', () {
      tap(0, 0);
      final filled = Uint8List.fromList(paint.currentPixels);

      tap(5, 5, pointer: 2);

      expect(paint.currentPixels, filled);
    });

    test('is one undo entry', () {
      tap(0, 0);

      paint.undo();

      expect(at(0, 0), 0);
      expect(at(kCanvasWidth - 1, kCanvasHeight - 1), 0);
    });
  });
}
