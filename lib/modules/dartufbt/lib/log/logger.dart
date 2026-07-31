import 'log_event.dart';
import 'log_format.dart';
import 'log_level.dart';
import 'progress.dart';

typedef UfbtLogSink = void Function(UfbtLogEvent event);

class UfbtLogger {
  UfbtLogger({
    UfbtLogSink? sink,
    this.level = UfbtLogLevel.info,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (sink != null) _sinks.add(sink);
  }

  final List<UfbtLogSink> _sinks = [];
  final DateTime Function() _clock;
  UfbtLogLevel level;
  int _progressSeq = 0;

  bool get verbose => level.severity <= UfbtLogLevel.debug.severity;

  set verbose(bool value) =>
      level = value ? UfbtLogLevel.debug : UfbtLogLevel.info;

  bool isEnabledFor(UfbtLogLevel level) =>
      level.severity >= this.level.severity;

  void addSink(UfbtLogSink sink) => _sinks.add(sink);

  void removeSink(UfbtLogSink sink) => _sinks.remove(sink);

  void clearSinks() => _sinks.clear();

  void emit(UfbtLogEvent event) {
    for (final sink in List<UfbtLogSink>.of(_sinks)) {
      sink(event);
    }
  }

  void log(UfbtLogLevel level, String message) {
    if (!isEnabledFor(level)) return;
    final time = _clock();
    emit(
      UfbtMessageEvent(
        time: time,
        level: level,
        message: message,
        formatted: UfbtLogFormat.message(time, level, message),
      ),
    );
  }

  void debug(String message) => log(UfbtLogLevel.debug, message);

  void info(String message) => log(UfbtLogLevel.info, message);

  void warning(String message) => log(UfbtLogLevel.warning, message);

  void error(String message) => log(UfbtLogLevel.error, message);

  void critical(String message) => log(UfbtLogLevel.critical, message);

  void build(String tag, String value, {List<String> details = const []}) {
    emit(
      UfbtBuildEvent(
        time: _clock(),
        tag: tag,
        value: value,
        details: details,
        formatted: UfbtLogFormat.build(tag, value, details),
      ),
    );
  }

  void raw(String text, {bool newline = true}) {
    emit(UfbtRawEvent(time: _clock(), text: text, newline: newline));
  }

  UfbtProgressTask progress(
    String title, {
    int? total,
    String? id,
    UfbtProgressThrottle? throttle,
  }) {
    final task = UfbtProgressTask._(
      this,
      UfbtProgress(
        id: id ?? 'progress-${++_progressSeq}',
        title: title,
        state: UfbtProgressState.started,
        current: 0,
        total: total,
      ),
      throttle ?? UfbtProgressThrottle(),
    );
    emit(UfbtProgressEvent(time: _clock(), progress: task.progress));
    return task;
  }

  void _emitProgress(UfbtProgress progress) {
    emit(UfbtProgressEvent(time: _clock(), progress: progress));
  }
}

class UfbtProgressTask {
  UfbtProgressTask._(this._logger, this._progress, this._throttle);

  final UfbtLogger _logger;
  final UfbtProgressThrottle _throttle;
  UfbtProgress _progress;

  UfbtProgress get progress => _progress;

  void update({int? current, int? total, String? message}) {
    if (_progress.isDone) return;
    _progress = _progress.copyWith(
      state: UfbtProgressState.running,
      current: current,
      total: total,
      message: message,
    );
    if (!_throttle.shouldEmit(_progress.fraction)) return;
    _logger._emitProgress(_progress);
  }

  void advance([int delta = 1]) => update(current: _progress.current + delta);

  void finish({String? message}) {
    if (_progress.isDone) return;
    _progress = _progress.copyWith(
      state: UfbtProgressState.finished,
      current: _progress.total ?? _progress.current,
      message: message,
    );
    _logger._emitProgress(_progress);
  }

  void fail({String? message}) {
    if (_progress.isDone) return;
    _progress = _progress.copyWith(
      state: UfbtProgressState.failed,
      message: message,
    );
    _logger._emitProgress(_progress);
  }
}
