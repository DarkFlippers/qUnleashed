import 'package:flipperlib/flipperlib.dart' show FlipperLogLevel, Log;
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart' as pretty_logging;
import 'package:logging/logging.dart' as logging;
import 'package:universal_ble/universal_ble.dart';

class LogService {
  /// Whether anything is logged at all. Follows the build type unless
  /// `--dart-define=QLOG=true|false` says otherwise, so a debug run can stay
  /// quiet and a release build can be made to talk.
  static const bool enabled = bool.fromEnvironment(
    'QLOG',
    defaultValue: kDebugMode,
  );

  /// How much is logged: `off`, `error`, `warn`, `info`, `debug` or `trace`,
  /// set with `--dart-define=QLOG_LEVEL=info`. Applies to the app's own
  /// messages as well as to flipperlib, package:logging and universal_ble.
  static const String levelName = String.fromEnvironment(
    'QLOG_LEVEL',
    defaultValue: 'trace',
  );

  static const int _off = 0;
  static const int _error = 1;
  static const int _warn = 2;
  static const int _info = 3;
  static const int _debug = 4;
  static const int _trace = 5;

  /// Resolved once at compile time, so every guard below is a const condition:
  /// the branches that cannot log are shaken out of the build entirely.
  static const int level = !enabled || levelName == 'off'
      ? _off
      : levelName == 'error'
      ? _error
      : levelName == 'warn' || levelName == 'warning'
      ? _warn
      : levelName == 'info'
      ? _info
      : levelName == 'debug'
      ? _debug
      : _trace;

  static const bool errorOn = level >= _error;
  static const bool warnOn = level >= _warn;
  static const bool infoOn = level >= _info;

  /// Guards the chatty per-frame logs, mirroring `Log.debugOn` in flipperlib.
  static const bool debugOn = level >= _debug;
  static const bool traceOn = level >= _trace;

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (level == _off) {
      await UniversalBle.setLogLevel(BleLogLevel.none);
      return;
    }

    Log.level = _flipperLevel;
    Log.sink = _flipperlibSink;

    logging.Logger.root.level = _packageLevel;
    logging.Logger.root.onRecord.listen((record) {
      final source = record.loggerName.isEmpty ? 'library' : record.loggerName;
      _write('[${record.level.name}][$source] ${record.message}');
      _writeError(record.error, record.stackTrace);
    });

    pretty_logging.Logger.defaultOutput = _LogServiceOutput.new;
    await UniversalBle.setLogLevel(_bleLevel);
  }

  static void error(String msg) {
    if (!errorOn) return;
    _write('[error] $msg');
  }

  static void warn(String msg) {
    if (!warnOn) return;
    _write('[warning] $msg');
  }

  static void info(String msg) {
    if (!infoOn) return;
    _write(msg);
  }

  static void debug(String msg) {
    if (!debugOn) return;
    _write(msg);
  }

  static void trace(String msg) {
    if (!traceOn) return;
    _write(msg);
  }

  /// Default channel for app messages, kept as the informational level.
  static void log(String msg) => info(msg);

  static FlipperLogLevel get _flipperLevel => switch (level) {
    _error => FlipperLogLevel.error,
    _warn => FlipperLogLevel.warning,
    _info => FlipperLogLevel.info,
    _debug => FlipperLogLevel.debug,
    _ => FlipperLogLevel.trace,
  };

  static BleLogLevel get _bleLevel => switch (level) {
    _error => BleLogLevel.error,
    _warn || _info || _debug => BleLogLevel.warning,
    _trace => BleLogLevel.verbose,
    _ => BleLogLevel.none,
  };

  static logging.Level get _packageLevel => switch (level) {
    _error => logging.Level.SEVERE,
    _warn => logging.Level.WARNING,
    _info => logging.Level.INFO,
    _ => logging.Level.ALL,
  };

  static void _flipperlibSink(FlipperLogLevel level, String message) {
    _write('[${level.name}] $message');
  }

  static void _writeError(Object? error, StackTrace? stackTrace) {
    if (error != null) _write('error: $error');
    if (stackTrace != null) _write(stackTrace.toString());
  }

  static void _write(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    for (final line in msg.split('\n')) {
      debugPrint('[$ts] $line');
    }
  }
}

class _LogServiceOutput extends pretty_logging.LogOutput {
  @override
  void output(pretty_logging.OutputEvent event) {
    final origin = event.origin;
    LogService._write(
      '[${origin.level.name.toUpperCase()}][library] '
      '${origin.message}',
    );
    LogService._writeError(origin.error, origin.stackTrace);
  }
}
