import 'dart:collection';
import 'dart:io' as io;
import 'dart:ui' as ui;

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

  static const bool errorOn = level >= _error;
  static const bool warnOn = level >= _warn;
  static const bool infoOn = level >= _info;

  /// Whether anything is printed at all. The same condition as [errorOn], and
  /// stated that way rather than re-derived: error is the lowest printable
  /// level, so a build that prints anything prints errors.
  static const bool printing = errorOn;

  /// Guards the chatty per-frame logs, mirroring `Log.debugOn` in flipperlib.
  static const bool debugOn = level >= _debug;
  static const bool traceOn = level >= _trace;

  /// How many messages [history] keeps before dropping the oldest.
  ///
  /// Messages, not lines — see [history]. A few hundred failures is more than
  /// a session should produce, and even with stack traces attached that is on
  /// the order of a megabyte at worst.
  ///
  /// Not `MemoryOutput` from package:logger, which is already a dependency and
  /// does exactly this: it only sees what goes through a `Logger` instance,
  /// where this file is wired the other way round and captures that package's
  /// output instead. Its default filter also wraps the check in `assert`, so
  /// it drops everything in a release build — the bug being fixed here,
  /// shipped.
  static const int historyLimit = 500;

  static final ListQueue<String> _history = ListQueue<String>(historyLimit);
  static String? _lastKept;
  static int _repeats = 0;

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
  ///
  /// One entry per message rather than per line, so a stack trace stays a
  /// single event. Thirteen of the app's error sites pass `'$e\n$st'`, and a
  /// Dart stack trace runs to thirty frames or so — split by line, this would
  /// hold about sixteen failures.
  ///
  /// Not everything in the app can reach it. The DFU recovery runs in a
  /// spawned isolate and statics are isolate-local, so its own logging goes
  /// nowhere; what is recorded is the failure it reports back over its port.
  /// A reader should not take this for a complete account of a session.
  ///
  /// What arrives from flipperlib differs by build: a talking one keeps its
  /// warnings as well as its errors, a quiet one only the errors, because
  /// [attachFlipperlibSink] pins its level to error when nothing is printing.
  static List<String> get history => List.unmodifiable(_history);

  /// Keeps [stamped], unless [body] repeats what was kept last — in which case
  /// the entry already there gains a count instead of a neighbour.
  ///
  /// One timed-out multi-frame RPC produces an `[RPC] rx unmatched frame` per
  /// leftover frame, and an ordinary directory listing is hundreds of frames.
  /// Unchecked, that single failure would evict the whole buffer, including
  /// the timeout that explains it.
  static void _remember(String stamped, String body) {
    if (body == _lastKept && _history.isNotEmpty) {
      _repeats += 1;
      _history.removeLast();
      _history.addLast('$stamped  (${_repeats + 1}×)');
      return;
    }
    _lastKept = body;
    _repeats = 0;
    _history.addLast(stamped);
    if (_history.length > historyLimit) _history.removeFirst();
  }

  /// Drops everything [history] holds.
  ///
  /// Not test-only: the log screen offers it, because a log is copied into a
  /// bug report and then wants emptying before reproducing the next one.
  static void clearHistory() {
    _history.clear();
    _lastKept = null;
    _repeats = 0;
  }

  @visibleForTesting
  static void debugResetHandlers() => _handlersInstalled = false;

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    attachFlipperlibSink();
    installUncaughtHandlers();

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

  /// Routes flipperlib's own logging here.
  ///
  /// Attached even when nothing is printing, and kept apart from the platform
  /// calls in [initialize] so it can be reached without them: Log.error checks
  /// only that a sink exists — no level, no build type — so pinning the level
  /// to error gives [history] the transport faults and session failures a bug
  /// report actually needs, and none of the traffic below them.
  @visibleForTesting
  static void attachFlipperlibSink() {
    Log.level = printing ? _flipperLevel : FlipperLogLevel.error;
    Log.sink = _flipperlibSink;
  }

  /// Routes what nothing else catches into [history].
  ///
  /// The failures with the least surface of all: a framework exception during
  /// build, a rejected future nobody awaited. Every handler the app added for
  /// #21, #84, #85 and #80 covers a failure someone thought to catch; these
  /// are the ones nobody did, and until now they reached nothing at all.
  ///
  /// Both chain rather than replace. [FlutterError.onError] already presents
  /// the red console dump in a debug build and flutter_test installs its own
  /// to fail a test on an unexpected error — dropping either would be a poor
  /// trade for recording it. Returning what the previous handler said, or
  /// false, leaves the error unhandled, so nothing downstream is suppressed.
  ///
  /// The chained handler runs first, and the recording cannot throw past it.
  /// `FlutterError.reportError` is a bare `onError?.call(details)` with no
  /// guard of its own, and `exceptionAsString()` calls `toString()` on an
  /// arbitrary object — so recording first would let one bad `toString()` cost
  /// the red screen and the failed test both. The platform handler is worse:
  /// in the root zone a throw there escapes into the engine, and in a guarded
  /// zone it is re-dispatched, which a recorder that always fails would turn
  /// into a loop.
  @visibleForTesting
  static void installUncaughtHandlers() {
    // Installing twice wraps the wrappers, and every error would then be
    // recorded once per install — which _remember coalesces into "(2×)"
    // rather than duplicating, so it reads as the app having failed twice.
    if (_handlersInstalled) return;
    _handlersInstalled = true;

    final presented = FlutterError.onError;
    FlutterError.onError = (details) {
      presented?.call(details);
      // Silent is the framework's own word for "expected here, do not dump
      // it": dumpErrorToConsole honours it in release, and so does this.
      if (details.silent) return;
      try {
        final where = details.context == null
            ? ''
            : ' during ${details.context!.toDescription()}';
        final stack = details.stack == null ? '' : '\n${details.stack}';
        // console: false — the handler above has already printed this, in the
        // framework's own formatting, which is better than a flat copy of it.
        _emit(
          '[error] [flutter]$where ${details.exceptionAsString()}$stack',
          keep: true,
          console: false,
        );
      } catch (_) {
        // A toString() that throws must not also cost the dump above.
      }
    };

    final dispatched = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = (e, st) {
      final handled = dispatched?.call(e, st) ?? false;
      try {
        error('[uncaught] $e\n$st');
      } catch (_) {
        // Nothing upstream catches this: in the root zone the engine gets the
        // throw, and a guarded zone re-dispatches it without end.
      }
      return handled;
    };
  }

  static bool _handlersInstalled = false;

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

  // console: printing rather than a bare true. Every caller sits behind a
  // const guard or is installed only in a talking build, so the two agree
  // today; saying it this way stops an ungated caller ever making a quiet
  // build print.
  static void _write(String msg) => _emit(msg, keep: false, console: printing);

  /// Home directories, longest first, replaced with `~` wherever they appear.
  ///
  /// The log is something a user copies into a public issue now, and absolute
  /// paths are the one category that leaks every time it fires: the IR
  /// recovery names the tree it could not clear — at every launch — and any
  /// FileSystemException prints `path = '<absolute>'`. All of them begin with
  /// the account name.
  ///
  /// It is also the only category that can be removed mechanically. What a
  /// message says about the user's own files, folders and devices — a card
  /// called `Office badge.nfc`, a Flipper's name, a card's UID inside a
  /// dictionary filename — is not distinguishable from any other text, which
  /// is why the log screen says what the log can contain and shows it to the
  /// user before offering to copy it.
  static final List<String> _homes = _resolveHomes();

  static List<String> _resolveHomes() {
    if (kIsWeb) return const [];
    final found = <String>[];
    for (final key in const ['USERPROFILE', 'HOME']) {
      final value = io.Platform.environment[key];
      // Anything this short is not a home directory, and replacing it would
      // shred unrelated messages.
      if (value != null && value.length > 3) found.add(value);
    }
    // Longest first: on macOS HOME can sit inside another candidate, and a
    // shorter match would leave the tail of the longer one behind.
    found.sort((a, b) => b.length.compareTo(a.length));
    return found;
  }

  @visibleForTesting
  static String redact(String msg) {
    var out = msg;
    for (final home in _homes) {
      out = out.replaceAll(home, '~');
    }
    return out;
  }

  /// Stamps [msg], keeps it in [history] if [keep], prints it if [console].
  static void _emit(
    String message, {
    required bool keep,
    required bool console,
  }) {
    final msg = redact(message);
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    if (keep) _remember('[$ts] $msg', msg);
    if (!console) return;
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
