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
  /// single event. Many of the app's error sites pass `'$e\n$st'`, and a
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
    //
    // Checked against the slot rather than a flag we set: a test that puts the
    // previous handler back has uninstalled us, and the next install should
    // take. A flag would still say installed.
    if (identical(FlutterError.onError, _ourFlutterHandler) &&
        identical(
          ui.PlatformDispatcher.instance.onError,
          _ourPlatformHandler,
        )) {
      return;
    }

    final presented = FlutterError.onError;
    FlutterError.onError = _ourFlutterHandler = (details) {
      presented?.call(details);
      // Every silent: true site in the framework is image loading, and the
      // map tile providers put their API key in the URL — so a tile that will
      // not load carries the user's paid key in its exception. Nothing else
      // keeps that out of a log this screen offers to copy: the two error
      // callbacks that suppress those reports today are one cleanup away from
      // being deleted as pointless.
      //
      // Not framework parity, whatever it looks like: dumpErrorToConsole
      // ignores silent in debug and honours it only in release, where this
      // honours it always.
      if (details.silent) return;
      try {
        final where = details.context == null
            ? ''
            : ' during ${details.context!.toDescription()}';
        final stack = details.stack == null ? '' : '\n${details.stack}';
        // console: false — the handler above prints it in the framework's own
        // formatting, which is better than a flat copy. (From the second error
        // onwards that dump shrinks to one summary line, so the detail here is
        // the only full record; it is still not worth printing twice.)
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
    ui.PlatformDispatcher.instance.onError = _ourPlatformHandler = (e, st) {
      final handled = dispatched?.call(e, st) ?? false;
      try {
        // console: false, as above. Returning unhandled means the zone or the
        // engine reports this itself, so printing here says it twice.
        _emit('[error] [uncaught] $e\n$st', keep: true, console: false);
      } catch (_) {
        // Nothing upstream catches this: in the root zone the engine gets the
        // throw, and a guarded zone re-dispatches it without end.
      }
      return handled;
    };
  }

  static FlutterExceptionHandler? _ourFlutterHandler;
  static ui.ErrorCallback? _ourPlatformHandler;

  static void error(String msg) =>
      _emit('[error] $msg', keep: true, console: errorOn);

  static void warn(String msg) =>
      _emit('[warning] $msg', keep: true, console: warnOn);

  /// Running commentary, and the one level that does not survive.
  ///
  /// Never kept, in any build: [history] holds errors and warnings only, so
  /// nothing sent here can reach the log screen. On top of that [infoOn] is a
  /// const that folds to false in an ordinary release build, so the call
  /// usually compiles away — and a build made to talk with `QLOG=true` reaches
  /// only a console that, per [history], a user of a shipped build cannot read.
  ///
  /// Which makes this the right level for saying what the app did, and the
  /// wrong one for the only report of a failure. That wants [warn] or [error].
  ///
  /// The rule the triage applies, so the next area need not re-derive it: an
  /// `info` inside a catch stays only when something else keeps a record of
  /// the same failure, or when the site repeats without a user action and
  /// would churn [history].
  ///
  /// "Keeps" rather than "reports", because most of these are RPC calls and
  /// flipperlib logs its own timeouts and transport write failures at error -
  /// see [attachFlipperlibSink], which pins its level to error even in a build
  /// that prints nothing. Those app-side lines are a thinner second account.
  /// A platform channel, SharedPreferences, a dart:io socket and Geolocator
  /// have no such channel, and there the catch is the whole of the report.
  ///
  /// A value handed back to the caller only counts if it is *distinct*:
  /// `EmulateService` returns a typed `EmulateError` the archive page renders,
  /// where a hard-coded `SEND_FAILED`, a `null` the caller reads as absence,
  /// and a message naming one cause for every fault do not - the last being
  /// worse than silence, because the reader stops looking.
  ///
  /// It is not yet used that way. Most of the calls to this sit inside a catch
  /// block, and whether each is commentary or the last word on a failure turns
  /// on what its caller does next — a judgement per site, not a sweep. #103
  /// holds that triage, and test/log_level_budget_test.dart holds a per-area
  /// budget so it cannot grow unnoticed meanwhile. Until the triage is done, one of these inside a
  /// catch is a site nobody has ruled on rather than one ruled to be
  /// commentary.
  ///
  /// There is no catch-all to reach for instead. Pick a level at each site.
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
  static List<RegExp> _homes = _resolveHomes(_environmentHomes());

  static List<String> _environmentHomes() => [
    for (final key in const ['USERPROFILE', 'HOME'])
      ?io.Platform.environment[key],
  ];

  /// Builds the patterns for [homes], in both the spellings a message can
  /// carry them in.
  ///
  /// A path reaches the log two ways and they do not look alike. A
  /// FileSystemException prints the native form — `C:\Users\Myte\...` — while
  /// a stack frame prints a URI, `file:///C:/Users/Myte/...`, with the
  /// separators flipped and the drive behind a scheme. Matching only the
  /// environment value catches the first and misses the second, which is
  /// exactly backwards: the entries carrying stacks are the ones most likely
  /// to be pasted into an issue.
  ///
  /// Each is anchored so that the next character cannot continue a name.
  /// Without that, a HOME of `/root` — ordinary in a container — would rewrite
  /// `/rootfs` to `~fs` and corrupt messages that had no path in them at all.
  static List<RegExp> _resolveHomes(List<String> homes) {
    final spellings = <String>{};
    for (final home in homes) {
      // Too short to be a home directory, and long enough to appear inside
      // unrelated text.
      if (home.length <= 3) continue;
      spellings.add(home);
      // The separator flipped, which is how a stack frame spells it. A URI
      // form — `file:///C:/Users/Myte/...` — contains this string, so the one
      // spelling covers both it and a bare forward-slash path. On POSIX it is
      // the same string as above and the set drops it.
      spellings.add(home.replaceAll(r'\', '/'));
    }
    return [
      for (final spelling in spellings)
        RegExp('${RegExp.escape(spelling)}(?![A-Za-z0-9_.-])'),
    ];
  }

  /// Points redaction at [homes] for the duration of a test.
  ///
  /// The real list comes from the environment, which a test cannot vary — and
  /// the cases worth pinning are all about unusual environments: a Windows
  /// home reached through a URI, one that is a prefix of an unrelated word,
  /// two that are the same string.
  @visibleForTesting
  static void debugUseHomes(List<String>? homes) =>
      _homes = _resolveHomes(homes ?? _environmentHomes());

  /// How many patterns redaction scans for. Behaviour cannot show a duplicate
  /// — replacing the same thing twice is the same answer — so the cost is the
  /// only way to see one, and on Windows under Git Bash both environment keys
  /// hold the same string.
  @visibleForTesting
  static int get debugHomePatternCount => _homes.length;

  static String _redact(String msg) {
    var out = msg;
    for (final home in _homes) {
      out = out.replaceAll(home, '~');
    }
    return out;
  }

  /// Stamps [msg], keeps it in [history] if [keep], prints it if [console].
  ///
  /// Only what is kept is redacted. The history is the only thing the log
  /// screen offers to copy, and everything else — five times as many trace,
  /// debug and info sites as ones that keep — would be paying a scan per home
  /// directory per message for nothing. It also leaves a developer's own console
  /// printing the path they are debugging rather than `~`. The trade is that
  /// a path still reaches logcat, which is not the surface with a copy button
  /// on it.
  static void _emit(String msg, {required bool keep, required bool console}) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    if (keep) {
      final kept = _redact(msg);
      _remember('[$ts] $kept', kept);
    }
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
