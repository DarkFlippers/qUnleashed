enum UfbtProgressState { started, running, finished, failed }

class UfbtProgressThrottle {
  UfbtProgressThrottle({
    this.minDelta = 0.002,
    Duration minInterval = const Duration(milliseconds: 150),
  }) : _minIntervalMs = minInterval.inMilliseconds;

  final double minDelta;
  final int _minIntervalMs;

  double _last = -1.0;
  final Stopwatch _sw = Stopwatch()..start();

  bool shouldEmit(double? fraction) {
    if (fraction == null) return _tick();
    if (fraction >= 1.0 && _last < 1.0) {
      _mark(fraction);
      return true;
    }
    if ((fraction - _last).abs() >= minDelta &&
        _sw.elapsedMilliseconds >= _minIntervalMs) {
      _mark(fraction);
      return true;
    }
    return false;
  }

  bool _tick() {
    if (_sw.elapsedMilliseconds >= _minIntervalMs) {
      _sw
        ..reset()
        ..start();
      return true;
    }
    return false;
  }

  void _mark(double fraction) {
    _last = fraction;
    _sw
      ..reset()
      ..start();
  }
}

class UfbtProgress {
  const UfbtProgress({
    required this.id,
    required this.title,
    required this.state,
    required this.current,
    this.total,
    this.message,
  });

  final String id;
  final String title;
  final UfbtProgressState state;
  final int current;
  final int? total;
  final String? message;

  bool get indeterminate => total == null || total! <= 0;

  bool get isDone =>
      state == UfbtProgressState.finished || state == UfbtProgressState.failed;

  double? get fraction {
    if (indeterminate) return null;
    final value = current / total!;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  double? get percent {
    final value = fraction;
    return value == null ? null : value * 100;
  }

  UfbtProgress copyWith({
    UfbtProgressState? state,
    int? current,
    int? total,
    String? message,
  }) {
    return UfbtProgress(
      id: id,
      title: title,
      state: state ?? this.state,
      current: current ?? this.current,
      total: total ?? this.total,
      message: message ?? this.message,
    );
  }
}
