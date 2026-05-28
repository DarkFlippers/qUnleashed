import 'package:flutter/foundation.dart';

import 'gif_encoder.dart';
import 'models/models.dart';

enum GifRecordingState { idle, recording, paused, encoding }

class _Frame {
  const _Frame(this.indices, this.timestampMs);
  final Uint8List indices; // 128×64 pixel indices
  final int timestampMs;
}

class _EncodeParams {
  const _EncodeParams({
    required this.frames,
    required this.delays,
    required this.bg,
    required this.fg,
  });
  final List<Uint8List> frames;
  final List<int> delays;
  final int bg; // ARGB
  final int fg; // ARGB
}

Uint8List _encodeInIsolate(_EncodeParams p) => FlipperGifEncoder.encode(
  width: kFlipperGifWidth,
  height: kFlipperGifHeight,
  frames: p.frames,
  delaysMs: p.delays,
  color0: p.bg,
  color1: p.fg,
);

const int kFlipperGifWidth = 128;
const int kFlipperGifHeight = 64;

class GifRecorder {
  static const int maxDurationMs = 60000;
  static const int maxFrameRate = 30;
  static const int minFrameIntervalMs =
      (1000 + maxFrameRate - 1) ~/ maxFrameRate;
  static const int minFrameDelayMs = minFrameIntervalMs;
  static const int maxFrameDelayMs = 5000;
  static const int lastFrameDelayMs = 250;

  GifRecordingState _state = GifRecordingState.idle;
  final List<_Frame> _frames = [];

  // Wall-clock tracking — paused intervals are excluded.
  DateTime? _resumeTime; // set when recording (re)starts
  int _accumulatedMs = 0; // total recorded ms across resumed segments

  int _storedBg = 0;
  int _storedFg = 0;

  GifRecordingState get state => _state;
  int get frameCount => _frames.length;

  /// Elapsed recording time in ms (excludes paused intervals).
  int get elapsedMs {
    if (_state == GifRecordingState.recording && _resumeTime != null) {
      return _accumulatedMs +
          DateTime.now().difference(_resumeTime!).inMilliseconds;
    }
    return _accumulatedMs;
  }

  void start(int bgColor, int fgColor) {
    assert(_state == GifRecordingState.idle);
    _state = GifRecordingState.recording;
    _frames.clear();
    _accumulatedMs = 0;
    _storedBg = bgColor;
    _storedFg = fgColor;
    _resumeTime = DateTime.now();
  }

  void pause() {
    if (_state != GifRecordingState.recording) return;
    if (_resumeTime != null) {
      _accumulatedMs += DateTime.now().difference(_resumeTime!).inMilliseconds;
    }
    _resumeTime = null;
    _state = GifRecordingState.paused;
  }

  void resume() {
    if (_state != GifRecordingState.paused) return;
    _resumeTime = DateTime.now();
    _state = GifRecordingState.recording;
  }

  /// Feed a decoded frame into the recorder.
  ///
  /// Returns `true` when the 60-second limit has been reached — the caller
  /// should then call [encode] (or [cancel]).
  bool addFrame(DecodedFrame frame) {
    if (_state != GifRecordingState.recording) return false;
    final timestampMs = elapsedMs;
    if (timestampMs >= maxDurationMs) return true;

    // Record event-based screen updates, but never store faster than 30 fps.
    // Incoming Flipper frames are often ~10 fps; this only drops bursts.
    if (_frames.isNotEmpty &&
        timestampMs - _frames.last.timestampMs < minFrameIntervalMs) {
      return false;
    }

    _frames.add(_Frame(Uint8List.fromList(frame.pixelIndices), timestampMs));
    return timestampMs >= maxDurationMs;
  }

  /// Encodes captured frames into a GIF in a background isolate.
  ///
  /// Transitions state to [GifRecordingState.encoding] synchronously.
  /// Returns `null` when no frames were captured.
  Future<Uint8List?> encode() async {
    if (_frames.isEmpty) return null;

    // Snapshot elapsed time before transitioning state
    if (_resumeTime != null) {
      _accumulatedMs += DateTime.now().difference(_resumeTime!).inMilliseconds;
      _resumeTime = null;
    }
    _state = GifRecordingState.encoding;

    return compute(
      _encodeInIsolate,
      _EncodeParams(
        frames: _frames.map((f) => f.indices).toList(),
        delays: _frameDelays(),
        bg: _storedBg,
        fg: _storedFg,
      ),
    );
  }

  /// Discard recording and return to idle.
  void cancel() => _reset();

  /// Called after encode() completes to return to idle.
  void reset() => _reset();

  void _reset() {
    _state = GifRecordingState.idle;
    _frames.clear();
    _accumulatedMs = 0;
    _resumeTime = null;
  }

  List<int> _frameDelays() {
    return [
      for (var i = 0; i < _frames.length; i++)
        i + 1 < _frames.length
            ? (_frames[i + 1].timestampMs - _frames[i].timestampMs).clamp(
                minFrameDelayMs,
                maxFrameDelayMs,
              )
            : lastFrameDelayMs,
    ];
  }
}
