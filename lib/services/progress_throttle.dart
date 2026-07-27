class ProgressThrottle {
  ProgressThrottle({
    this.minDelta = 0.01,
    Duration minInterval = const Duration(milliseconds: 150),
  }) : _minIntervalMs = minInterval.inMilliseconds;

  final double minDelta;
  final int _minIntervalMs;

  double _last = -1.0;
  final Stopwatch _sw = Stopwatch()..start();

  bool shouldEmit(double progress) {
    if (progress >= 1.0 && _last < 1.0) {
      _mark(progress);
      return true;
    }
    if ((progress - _last).abs() >= minDelta &&
        _sw.elapsedMilliseconds >= _minIntervalMs) {
      _mark(progress);
      return true;
    }
    return false;
  }

  bool tick() {
    if (_sw.elapsedMilliseconds >= _minIntervalMs) {
      _sw
        ..reset()
        ..start();
      return true;
    }
    return false;
  }

  void reset() {
    _last = -1.0;
    _sw
      ..reset()
      ..start();
  }

  void _mark(double progress) {
    _last = progress;
    _sw
      ..reset()
      ..start();
  }
}
