import 'dart:collection';

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

  /// Resolved once at compile time, so the guards below are const conditions:
  /// the chatty branches are shaken out of the build entirely. [errorOn] and
  /// [warnOn] gate printing only — see [history] for why those two are still
  /// recorded in a build that prints nothing.
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

  /// Whether anything is being printed at all.
  static const bool printing = level != _off;

  static const bool errorOn = level >= _error;
  static const bool warnOn = level >= _warn;
  static const bool infoOn = level >= _info;

  /// Guards the chatty per-frame logs, mirroring `Log.debugOn` in flipperlib.
  static const bool debugOn = level >= _debug;
  static const bool traceOn = level >= _trace;

  /// How many lines [history] keeps before dropping the oldest.
  ///
  /// A few hundred is enough to hold what led up to a failure and small enough
  /// not to matter: at roughly a hundred characters a line this is tens of
  /// kilobytes.
  static const int historyLimit = 500;

  static final ListQueue<String> _history = ListQueue<String>();

  /// Errors and warnings, oldest first, whether or not anything printed them.
  ///
  /// The const guards above compile the chatty levels out of a release build,
  /// which is right — they run per frame. Letting errors go the same way meant
  /// every catch handler in the app reported nowhere in exactly the builds
  /// people run, and there is no second channel: no crash reporting, and the
  /// console `debugPrint` reaches is not one a user of a shipped build can
  /// read. So these two are kept here regardless, bounded, and printed only
  /// when the build is talking.
  ///
  /// Errors and warnings only. Anything below them fires often enough to churn
  /// the buffer, which would cost the failure its context — the one thing this
  /// exists to hold on to.
  static List<String> get history => List.unmodifiable(_history);

  @visibleForTesting
  static void clearHistory() => _history.clear();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Attached even when nothing is printing. Log.error checks only that a
    // sink exists — no level, no build type — so pinning the level to error
    // gives [history] the transport faults and session failures a bug report
    // actually needs, and none of the traffic below them.
    Log.level = printing ? _flipperLevel : FlipperLogLevel.error;
    Log.sink = _flipperlibSink;

    if (!printing) {
      await UniversalBle.setLogLevel(BleLogLevel.none);
      return;
    }

    logging.Logger.root.level = _packageLevel;
    logging.Logger.root.onRecord.listen((record) {
      final source = record.loggerName.isEmpty ? 'library' : record.loggerName;
      _write('[${record.level.name}][$source] ${record.message}');
      _writeError(record.error, record.stackTrace);
    });

    pretty_logging.Logger.defaultOutput = _LogServiceOutput.new;
    await UniversalBle.setLogLevel(_bleLevel);
  }

  static void error(String msg) =>
      _emit('[error] $msg', keep: true, console: errorOn);

  static void warn(String msg) =>
      _emit('[warning] $msg', keep: true, console: warnOn);

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

  static void _flipperlibSink(FlipperLogLevel severity, String message) {
    _emit(
      '[${severity.name}] $message',
      keep: severity.index >= FlipperLogLevel.warning.index,
      console: printing,
    );
  }

  static void _writeError(Object? error, StackTrace? stackTrace) {
    if (error != null) _write('error: $error');
    if (stackTrace != null) _write(stackTrace.toString());
  }

  static void _write(String msg) => _emit(msg, keep: false, console: true);

  /// Stamps [msg], keeps it in [history] if [keep], prints it if [console].
  static void _emit(String msg, {required bool keep, required bool console}) {
    if (!keep && !console) return;
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    for (final line in msg.split('\n')) {
      final stamped = '[$ts] $line';
      if (keep) {
        _history.addLast(stamped);
        while (_history.length > historyLimit) {
          _history.removeFirst();
        }
      }
      if (console) debugPrint(stamped);
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
