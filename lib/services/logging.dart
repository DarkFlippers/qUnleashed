import 'dart:ui' as ui;

import 'package:flipperlib/flipperlib.dart' show FlipperLogLevel, Log;
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart' as pretty_logging;
import 'package:logging/logging.dart' as logging;
import 'package:universal_ble/universal_ble.dart';

/// The three levels `LogService` forwards, and so the only ones a reader can
/// be told about.
///
/// Not every level: `info`, `debug` and `trace` pass no level to `_emit` at
/// all and const-fold out of a release build, so there is nothing to forward
/// and no value in a name for it. This is the vocabulary of what is *kept*,
/// which is why it is three and not six.
enum KeptLevel {
  /// Something failed and somebody should look at it.
  error,

  /// Degraded but not broken.
  warning,

  /// Caught, handled, and worth reading about afterwards rather than being
  /// alerted on. [LogService.caught] has the argument.
  caught,
}

/// A second reader for the lines [LogService] keeps.
///
/// Shaped like flipperlib's `Log.sink` on purpose - a level and a body - so
/// the two hooks this app installs read the same way.
///
/// The body is stamped-free and **raw**: this file redacts nothing, by
/// decision rather than oversight - the console is a developer's own machine
/// and wants the real path. Anything sending it off the device must put it
/// through `Scrub.outbound` first. That is the sink's job, and the only
/// scrubbing there is.
typedef KeptLogSink = void Function(KeptLevel level, String body);

/// A reader for flipperlib's running commentary, at the library's own levels.
///
/// Separate from [KeptLogSink] because the two carry different things.
/// [KeptLogSink] gets the three levels this app *keeps* - a record of a
/// failure. This gets everything the library says, including the `info` lines
/// nothing keeps, because the value of a breadcrumb is the sequence and not
/// the severity: "link lost -> reconnecting -> reconnected" in front of a
/// crash is worth more than any one of those lines on its own.
///
/// ADR 0013 §4 argues why flipperlib is the only source. The app's own `info`
/// is a `const` guard that folds out of a release build, so making it reachable
/// would mean a release build that prints everything to the platform log -
/// which is not a trade worth making for commentary.
typedef BreadcrumbSink = void Function(FlipperLogLevel severity, String body);

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
  /// [warnOn] gate printing only — see [keptSink] for why those two are still
  /// forwarded in a build that prints nothing.
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

  /// The last body forwarded, so a run of identical lines is sent once.
  ///
  /// All that is left of the 500-entry buffer this file used to keep. ADR 0013
  /// §1 makes Sentry the only channel, so there is nothing to hold a history
  /// *for* - but the fold has to survive, because one timed-out multi-frame
  /// RPC produces an `[RPC] rx unmatched frame` per leftover frame and an
  /// ordinary directory listing is hundreds of frames. Without this, that one
  /// failure would send hundreds of identical lines to a reader that has no
  /// coalescing of its own.
  static String? _lastKept;

  /// Forgets which line went out last, so [_isNewLine] starts fresh.
  ///
  /// The fold is the one piece of state in this file that outlives a test: a
  /// second test logging the body a first one already logged gets no sink call
  /// at all, and reads as a sink that was never installed. The buffer used to
  /// carry this reset along with everything else it cleared; with the buffer
  /// gone this is what is left of it, and `test/flutter_test_config.dart` runs
  /// it before every test in the suite rather than each file remembering to.
  @visibleForTesting
  static void debugForgetLastKept() => _lastKept = null;

  /// Whether [body] is worth forwarding, or repeats the line before it.
  ///
  /// The comparison is against the last *forwarded* body, not the last line
  /// emitted, so an interleaved `info` does not break a run. That is the same
  /// comparison the old buffer made when it folded a repeat into a `(N×)`
  /// count; what is gone is the count, which was a display detail of a screen
  /// that no longer exists.
  static bool _isNewLine(String body) {
    if (body == _lastKept) return false;
    _lastKept = body;
    return true;
  }

  /// Where kept lines go, and the only place they go.
  ///
  /// Null until something installs one. `lib/services/telemetry/` does, when
  /// reporting is on, and clears it again when it is turned off - the same
  /// one-way shape `guardedFailureSink` uses, and for the same reason: this
  /// file knows there may be a second reader and nothing about who it is.
  static KeptLogSink? keptSink;

  /// Where flipperlib's commentary goes, or nowhere.
  ///
  /// Installed by `lib/services/telemetry/` while reporting is on, like
  /// [keptSink] and `guardedFailureSink`, and cleared with them.
  ///
  /// Setting this is not enough on its own: the library's own `Log.level` has
  /// to admit `info` as well, which is [attachFlipperlibSink]'s business. Both
  /// gates, the same mistake the pin made once already.
  static BreadcrumbSink? breadcrumbSink;

  /// Whether [_announce] is already running.
  ///
  /// **For a sink that logs, not one that throws.** A throw is caught in
  /// [_announce] and reported straight to `debugPrint`, which cannot come back
  /// round. A sink that *logs* can: `Telemetry._reportKept` reports its own
  /// send failures through [LogService.error], which re-enters [_emit], which
  /// calls the sink, which logs again - and the only termination is dropping
  /// the re-entrant line, because the alternative is a stack overflow in the
  /// logger on a path that exists because something was already broken.
  static bool _announcing = false;

  /// Hands one kept line to [keptSink] without letting it cost the process.
  ///
  /// There is no local record behind this any more, so a sink that throws
  /// loses the line - which is why the failure is itself reported rather than
  /// swallowed, and why [_announcing] exists to stop that report becoming the
  /// next failure.
  static void _announce(KeptLevel level, String body) {
    final sink = keptSink;
    if (sink == null || _announcing) return;
    _announcing = true;
    try {
      sink(level, body);
    } catch (e) {
      // **Straight to `debugPrint`, not through [error].** Routing it through
      // this file's own levels puts it back into [_emit], which calls
      // [_announce] again - and [_announcing] is still true, so the report is
      // dropped on the floor. With the history gone there is nothing else
      // holding it, so a broken sink would be a reporting feature that
      // silently does nothing, which is the one outcome this catch exists to
      // prevent.
      //
      // Unconditional, unlike every other print in this file: `printing` is a
      // const that is false in a release build, and this is the one line whose
      // whole purpose is to survive there. `debugPrint` still reaches the
      // platform log - `adb logcat`, Console.app - which is the only surface
      // left once the sink itself is the thing that is broken.
      //
      // Not `describe`: the useful fact is which line the sink broke on, not
      // where inside the sink it happened.
      debugPrint('[LogService] the kept-log sink threw on "$body": $e');
    } finally {
      _announcing = false;
    }
  }

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    attachFlipperlibSink();
    installUncaughtHandlers();

    if (!printing) {
      await _quietBle(BleLogLevel.none);
      return;
    }

    logging.Logger.root.level = _packageLevel;
    logging.Logger.root.onRecord.listen((record) {
      final source = record.loggerName.isEmpty ? 'library' : record.loggerName;
      _write('[${record.level.name}][$source] ${record.message}');
      _writeError(record.error, record.stackTrace);
    });

    pretty_logging.Logger.defaultOutput = _LogServiceOutput.new;
    await _quietBle(_bleLevel);
  }

  /// Never throws, which is the whole of it.
  ///
  /// This is the log level of a Bluetooth library, and `_initCore` awaits
  /// [initialize] before there is a UI - on the app entry point and on the
  /// home-widget one - so a platform where the plugin is not registered must
  /// not be the reason nothing appears. [installUncaughtHandlers] has already
  /// run by the time this does, so the failure is kept.
  ///
  /// Unpinned: `UniversalBle.setLogLevel` is a static and [initialize]
  /// memoises, so there is nothing a host test can drive here without a seam
  /// costing more than the line it would protect.
  static Future<void> _quietBle(BleLogLevel level) async {
    try {
      await UniversalBle.setLogLevel(level);
    } catch (e, st) {
      warn('[LogService] BLE log level failed: ${describe(e, st)}');
    }
  }

  /// Routes flipperlib's own logging here.
  ///
  /// Attached even when nothing is printing, and kept apart from the platform
  /// calls in [initialize] so it can be reached without them, forwarding the
  /// transport faults and session failures a bug report actually needs and
  /// none of the traffic below them.
  ///
  /// Warning, not error, and that is a fix rather than a widening.
  /// [_flipperlibSink] has always kept warnings — its cut is [_keptFrom] — but
  /// `Log.level` was pinned a level above it, so the threshold was unreachable
  /// and every `Log.warn` in the submodule died at the library's own gate
  /// before the sink could apply its own. Lines written to be kept were not:
  /// a transport MTU read that failed, a reboot the firmware refused. The two
  /// gates now read the same constant and cannot disagree again.
  ///
  /// What it admits is the class those belong to — a link or a call that is
  /// degraded rather than broken. The BLE transport warns when a connection
  /// carries a payload small enough to make transfers slow, which answers "why
  /// did it take so long" and is in nothing else a shipped build keeps. Volume
  /// is bounded by what the submodule chooses to warn about, which is its own
  /// review's problem; `Log.error` outnumbers `Log.warn` there by more than an
  /// order of magnitude.
  ///
  /// **A third pin, `info`, when [breadcrumbSink] is installed.** ADR 0013 §3:
  /// raising it is a change to a recorded decision rather than a setting that
  /// already allowed it, which is why it is spelled out here. The library's
  /// `Log.level` is a mutable static checked at runtime - only `debug` and
  /// `trace` sit behind a `const` - so raising it in a release build genuinely
  /// produces lines, where the same move on the app's side produces nothing
  /// without recompiling.
  ///
  /// Nothing is *kept* that was not kept before: [_keptLevelFor] still cuts at
  /// [_keptFrom], so `info` reaches the breadcrumb hook and is dropped. What
  /// changes is only what the library bothers to say, and only while somebody
  /// is listening - [Telemetry.stop] calls this again and the pin returns.
  ///
  /// Call it again after changing [breadcrumbSink]; it is idempotent.
  ///
  /// No longer `@visibleForTesting`. It was, because [initialize] was the only
  /// caller and a test wanting the sink without the platform calls was the only
  /// other reason to reach it. `Telemetry` is a second real caller now: the pin
  /// is derived from whether [breadcrumbSink] is set, so turning reporting on
  /// or off has to re-derive it.
  static void attachFlipperlibSink() {
    Log.level = _flipperlibPin;
    Log.sink = _flipperlibSink;
  }

  /// The level the library is held at: the **first** of the reasons that
  /// applies, talking build first.
  ///
  /// A priority, not a minimum, and this said "the chattiest" - which the body
  /// contradicts two paragraphs down. With `QLOG_LEVEL=error` and a breadcrumb
  /// sink installed the pin is `error`, strictly less chatty than the `info`
  /// the breadcrumb reason wants. That is deliberate: QLOG asked for its
  /// levels explicitly.
  ///
  /// **Chattiest means the lowest index.** `FlipperLogLevel` runs
  /// `trace, debug, info, warning, error`, and `Log` admits a severity at or
  /// above the pin - so `info` admits more than `warning`, and comparing these
  /// the intuitive way round gets it backwards.
  ///
  /// A talking build wins outright, because QLOG asked for its levels
  /// explicitly and a breadcrumb reader going away must not take them with it.
  /// Otherwise breadcrumbs beat the bare keep threshold, because they are the
  /// only reason `info` is wanted at all.
  static FlipperLogLevel get _flipperlibPin {
    if (printing) return _flipperLevel;
    return breadcrumbSink == null ? _keptFrom : FlipperLogLevel.info;
  }

  /// Routes what nothing else catches into [keptSink].
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
    // recorded once per install — which [_isNewLine] folds away rather than
    // sending twice, so a reader would otherwise see the app fail twice.
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
          level: KeptLevel.error,
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
        _emit(
          '[error] [uncaught] $e\n$st',
          level: KeptLevel.error,
          console: false,
        );
      } catch (_) {
        // Nothing upstream catches this: in the root zone the engine gets the
        // throw, and a guarded zone re-dispatches it without end.
      }
      return handled;
    };
  }

  static FlutterExceptionHandler? _ourFlutterHandler;
  static ui.ErrorCallback? _ourPlatformHandler;

  /// `$error`, and the stack when there is one.
  ///
  /// A rejection carries a stack only when its error is an [Error].
  /// `Completer.completeError` with no trace falls through to
  /// `AsyncError.defaultStackTrace`, which returns `error.stackTrace` for an
  /// [Error] and [StackTrace.empty] for anything else — so a
  /// `PlatformException` arrives bare and a `TypeError` does not. Appending
  /// unconditionally ends the first kind with a blank line; dropping it
  /// unconditionally loses the trace the second kind is carrying, which is
  /// usually the only thing naming where it came from.
  ///
  /// Tested by content rather than against [StackTrace.empty]: a zone can
  /// supply its own empty trace, and `flutter test` in fact supplies a
  /// chained one, so the identity check passes in the app and fails in the
  /// harness. [guarded] makes the same check for the same reason.
  static String describe(Object error, StackTrace stack) {
    final trace = stack.toString();
    return trace.isEmpty ? '$error' : '$error\n$trace';
  }

  static void error(String msg) =>
      _emit('[error] $msg', level: KeptLevel.error, console: errorOn);

  static void warn(String msg) =>
      _emit('[warning] $msg', level: KeptLevel.warning, console: warnOn);

  /// A failure that was caught and handled, kept so somebody can read it later.
  ///
  /// The distinction from [warn] is the audience, not the severity. [warn] is a
  /// failure somebody should look at; this is one somebody may need to read
  /// about afterwards, and the `[caught]` prefix is what lets a reader - and,
  /// once ADR 0013 lands, a Sentry log at info rather than warning - tell the
  /// two apart without the second firing any alerting.
  ///
  /// Kept like [warn], printed like [info]: a [KeptLevel] with
  /// `console: infoOn`, which is why this is one line rather than a mechanism.
  /// The difference from warn's combination is deliberate — in a build made to
  /// talk at `QLOG_LEVEL=warn` a warning prints and these do not, because the
  /// console is not the surface they are for. The keeping is the point: [info]
  /// does not survive, since [infoOn] folds to false in an ordinary release
  /// build and takes the call site out of the binary with it.
  ///
  /// **The rule, and it is narrow on purpose.** Use this where an operation
  /// did not do what was asked. Commentary about something merely absent, a
  /// reading that repeats, a wait whose own timeout is the answer - those stay
  /// [info]. The narrowness is about the person reading: noise in front of
  /// them costs attention on every failure after it.
  ///
  /// It is the catch-all [info]'s doc used to say did not exist. ADR 0013 §5
  /// argues that reversal; `test/caught_budget_test.dart` is the ceiling that
  /// keeps it honest, because moving *commentary* here would lower
  /// `test/log_level_budget_test.dart` as legitimately as a real failure does.
  static void caught(String msg) =>
      _emit('[caught] $msg', level: KeptLevel.caught, console: infoOn);

  /// Running commentary, and the one level that does not survive.
  ///
  /// Never kept, in any build: [keptSink] is handed errors, warnings and
  /// [caught] only, so nothing sent here is forwarded. On top of that [infoOn]
  /// is a const that folds to false in an ordinary release build, so the call
  /// usually compiles away — and a build made to talk with `QLOG=true` reaches
  /// only a console, which a user of a shipped build cannot read.
  ///
  /// Which makes this the right level for saying what the app did, and the
  /// wrong one for the only report of a failure. A failure somebody should
  /// look at wants [warn] or [error]; one that was handled, where the only
  /// loss is that nobody can read about it afterwards, wants [caught].
  ///
  /// The rule the triage applies, so the next area need not re-derive it: an
  /// `info` inside a catch stays only when something else keeps a record of
  /// the same failure, or when the site repeats faster than a person can act
  /// - a loop, a walk, one entry per file of a batch - and would flood the
  /// channel. Once per tap is not that, however often the tapping.
  ///
  /// A site kept for that second reason wants a tally at the batch boundary
  /// rather than a level here, so the count survives without the churn.
  /// `IrLibLocalRepo`'s unpack report is the shape: one record per run that
  /// had any, carrying totals and the first error. Several areas have deferred sites
  /// on this basis and none has built the general version.
  ///
  /// "Keeps" rather than "reports", because most of these are RPC calls and
  /// flipperlib logs its own timeouts and transport write failures at error -
  /// see [attachFlipperlibSink], which routes those here in every build. Those
  /// app-side lines are a thinner second account.
  /// A platform channel, SharedPreferences, a dart:io socket and Geolocator
  /// have no such channel, and there the catch is the whole of the report.
  ///
  /// Timeouts and transport writes, though - not every RPC error. A status
  /// the firmware reports comes back through `storageList`, `storageRename`,
  /// `storageDelete` and their neighbours as an exception with nothing logged
  /// at all, so those are the app's to keep. `storageWriteChunked` is the
  /// exception to the exception: it logs its own failures at error - except a
  /// link drop, which it records at info and retries, so a send torn down
  /// mid-write is still the app's to keep.
  ///
  /// Or when the app's own state ends up disagreeing with the device's as a
  /// result. flipperlib records the write that failed; it cannot know that the
  /// key left behind claims to be on a Flipper it never reached, and that is
  /// the app's to say.
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
  /// budget so it cannot grow unnoticed meanwhile. One of these inside a
  /// catch with no comment saying why is a site nobody has ruled on rather
  /// than one ruled to be commentary; where the ruling was made, it is
  /// written next to the call.
  ///
  /// There is one catch-all, and it is not this: see [caught]. Commentary
  /// stays here.
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

  /// The level at or above which a flipperlib line is worth keeping for a bug
  /// report. Read by both gates it has to pass - the library's own `Log.level`
  /// and this sink - because setting them apart is what made warnings
  /// unreachable for as long as it did.
  static const FlipperLogLevel _keptFrom = FlipperLogLevel.warning;

  /// The library's own levels, mapped onto the three this app keeps.
  ///
  /// Null below [_keptFrom], which is what decides whether the line is kept at
  /// all. `error` and `warning` are the only two at or above it, so no level
  /// *other than* `warning` can reach the else arm - which is itself the
  /// ordinary path for every `Log.warn`, and was described here as
  /// "unreachable" when only the third case is. It is written as a
  /// level rather than an assert, because raising [_keptFrom]'s neighbour is
  /// the kind of change that should degrade to "kept as a warning" instead of
  /// throwing inside the logger.
  static KeptLevel? _keptLevelFor(FlipperLogLevel severity) {
    if (severity.index < _keptFrom.index) return null;
    return severity == FlipperLogLevel.error
        ? KeptLevel.error
        : KeptLevel.warning;
  }

  /// Whether [_dropCrumb] is already running.
  ///
  /// Symmetry with [_announcing] rather than a live hazard: a breadcrumb sink
  /// that throws is reported with [error], and that reaches [_announce] - the
  /// *kept* sink - because `_emit` never calls this one. Only
  /// [_flipperlibSink] does, driven by the library's own `Log`. So the causal
  /// chain [_announcing] guards against does not exist here, and this said it
  /// did.
  ///
  /// Kept anyway, and separate from [_announcing] on purpose. Sharing one flag
  /// would be a behaviour change: a failing breadcrumb sink's report currently
  /// does reach Sentry Logs through the kept sink, and one flag would suppress
  /// it.
  static bool _crumbing = false;

  /// Hands one library line to [breadcrumbSink] without letting it cost the
  /// line.
  ///
  /// Not redacted here: the sink scrubs what it sends, as it does for every
  /// other channel. This used to redact first, because `_emit` redacted what
  /// it kept and a breadcrumb skipped that path - there is nothing to skip any
  /// more.
  static void _dropCrumb(FlipperLogLevel severity, String message) {
    final sink = breadcrumbSink;
    if (sink == null || _crumbing) return;
    _crumbing = true;
    try {
      sink(severity, message);
    } catch (e) {
      error('[Telemetry] the breadcrumb sink threw on "$message": $e');
    } finally {
      _crumbing = false;
    }
  }

  /// §4: the hook goes **before** [_emit], not inside it.
  ///
  /// Inside, it would have to sit above `_emit`'s `if (level == null &&
  /// !console) return` - which is #187, where five call sites out of six are
  /// dropped -
  /// and would reinstate the timestamp that return exists to avoid, for the
  /// app's own traffic as well as the library's.
  ///
  /// Every severity becomes a breadcrumb, not only `info`. §4 names `info`
  /// because that is the level the change *unlocks*; the point of a breadcrumb
  /// is the sequence, and a timeline with the warnings cut out of it is a
  /// worse timeline. Warnings and errors reach Sentry as Logs too, which is a
  /// separate stream - having them in the event itself is what makes the event
  /// readable without cross-referencing.
  static void _flipperlibSink(FlipperLogLevel severity, String message) {
    _dropCrumb(severity, message);
    _emit(
      '[${severity.name}] $message',
      level: _keptLevelFor(severity),
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
  static void _write(String msg) => _emit(msg, console: printing);

  /// How long a cached zone offset is trusted before it is read again.
  static Duration _zoneOffsetTtl = const Duration(minutes: 1);

  /// The offset local time is ahead of UTC, and the instant that reading of
  /// it stops being trusted.
  static Duration _zoneOffset = Duration.zero;
  static int _zoneOffsetExpiryMs = 0;

  /// How many times the offset has been read off the platform. The cache
  /// cannot be seen in the stamp - a correct cache and no cache at all print
  /// the same thing - so this is the only way a test can tell them apart.
  @visibleForTesting
  static int debugZoneLookups = 0;

  /// Forgets the cached offset, and optionally shortens how long the next one
  /// is trusted, so a test need not wait a minute to watch it expire.
  @visibleForTesting
  static void debugResetZoneOffset({
    Duration ttl = const Duration(minutes: 1),
  }) {
    _zoneOffsetTtl = ttl;
    _zoneOffsetExpiryMs = 0;
    debugZoneLookups = 0;
  }

  /// The stamp [_emit] would put on a line logged at [now].
  ///
  /// The ordinary entry points stamp whatever the clock reads, so an hour, a
  /// minute or a second below ten is only covered at the times of day that
  /// happen to have one - which is how a test comes to pass all afternoon and
  /// fail at nine in the morning.
  @visibleForTesting
  static String debugStamp(DateTime now) => _stamp(now);

  /// A line with neither consumer, which is what [_write] is in a build that
  /// prints nothing.
  ///
  /// A test build always prints, so that state cannot be reached through the
  /// ordinary entry points - and it is the one the skip in [_emit] exists
  /// for, because package:logging and universal_ble keep feeding it.
  @visibleForTesting
  static void debugEmitUnheard(String msg) => _emit(msg, console: false);

  static String _two(int value) => value < 10 ? '0$value' : '$value';

  /// `hh:mm:ss` of [now] on the wall clock, without asking the platform what
  /// the clock reads.
  ///
  /// Reading an hour, a minute or a second off a *local* DateTime forces a
  /// timezone lookup, and that lookup is most of what logging costs: measured
  /// here at 6676 ns against 260 ns for this, per line, and worse under AOT
  /// (#116). Shifting a UTC instant by a remembered offset gives the same
  /// digits for a fifth of a percent of the price.
  ///
  /// What the cache can be wrong about is a DST change, for as long as
  /// [_zoneOffsetTtl]: stamps inside that window carry the old offset and so
  /// read an hour out, and the line after it jumps. Twice a year, in one
  /// minute of a log that shows `hh:mm:ss` and is read against itself.
  static String _stamp(DateTime now) {
    final ms = now.millisecondsSinceEpoch;
    if (ms >= _zoneOffsetExpiryMs) {
      _zoneOffset = now.timeZoneOffset;
      _zoneOffsetExpiryMs = ms + _zoneOffsetTtl.inMilliseconds;
      debugZoneLookups++;
    }
    final wall = now.toUtc().add(_zoneOffset);
    return '${_two(wall.hour)}:${_two(wall.minute)}:${_two(wall.second)}';
  }

  /// Writes one line to the two destinations that exist, plus [keptSink].
  ///
  /// [level] replaced a `required bool keep`. The two carried the same fact -
  /// a line is kept if and only if it has one of [KeptLevel]'s three levels -
  /// and the level is what [keptSink] needs, so a second parameter beside the
  /// bool would have been a redundancy inviting `keep: true, level: null`.
  /// Null means not kept, which is `info`, `debug`, `trace` and everything
  /// [_write] forwards.
  static void _emit(String msg, {KeptLevel? level, required bool console}) {
    // Nobody is listening, so there is nothing to stamp. This is the whole of
    // _write's cost in a build that prints nothing: package:logging and
    // universal_ble keep handing lines to a sink that drops them, and every
    // one of them used to buy a timestamp first.
    if (level == null && !console) return;
    // Only the first of a run is forwarded. One RPC timeout produces hundreds
    // of identical lines, and the reader at the other end has no coalescing of
    // its own.
    //
    // Not redacted here. Everything that leaves goes through the sink, which
    // scrubs it; the console is the developer's own machine and wants the real
    // path.
    if (level != null && _isNewLine(msg)) _announce(level, msg);
    if (!console) return;
    final ts = _stamp(DateTime.now());
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
