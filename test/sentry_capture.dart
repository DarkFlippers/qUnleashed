// Driving a real Sentry hub with the transport replaced, optionally with the
// production sinks wired over it, and reading what it produced.
//
// Two copies of the transaction half had grown, in `traced_test.dart` and
// `transfer_restart_count_test.dart`, differing in one line - and
// `contexts.trace` was picked out of `toJson()` in three places with three
// spellings. [wiredHub] arrived the same way: `connect_failure_report_test.
// dart` had it and `guarded_replay_test.dart` was about to copy it. The repo's
// convention for shared test code is a plain unsuffixed file in `test/`.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/connection/connect_report.dart';
import 'package:qunleashed/services/guarded.dart';
import 'package:qunleashed/services/telemetry/settings.dart';
import 'package:qunleashed/services/telemetry/telemetry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'quiet_log.dart';
import 'telemetry_sinks.dart';

/// The project a test reports to, which no test reads back.
const String _testDsn = 'https://key@o0.ingest.sentry.io/0';

/// A transport that accepts everything and sends nothing.
class NowhereTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async => SentryId.empty();
}

/// Brings a hub up with every transaction captured instead of sent.
///
/// The returned list fills as transactions finish. `Sentry.close()` is
/// registered as a teardown **and** should be awaited in the test body before
/// asserting: `beforeSendTransaction` runs when a span finishes, and a test
/// that asserts before the close may be reading an empty list. The teardown is
/// the net for a test that fails before its own close, so the next one does not
/// inherit a live hub.
Future<List<SentryTransaction>> captureTransactions() async {
  final sent = <SentryTransaction>[];
  await Sentry.init((options) {
    options.dsn = _testDsn;
    options.tracesSampleRate = 1.0;
    options.transport = NowhereTransport();
    options.beforeSendTransaction = (transaction, hint) {
      sent.add(transaction);
      return transaction;
    };
  });
  addTearDown(Sentry.close);
  return sent;
}

/// One captured transaction, read the way the server reads it.
///
/// Through `toJson()` and not the object graph: `SentryTransaction` keeps its
/// name, status and data behind `tracer`, which is `@internal` - and
/// `flutter analyze` treats reaching for it as a warning, which CI treats as
/// fatal. The payload is also literally what Sentry receives, so an assertion
/// on it cannot pass while the wire format says something else.
extension CapturedTransaction on SentryTransaction {
  Map<String, dynamic> get _json => toJson();

  Map<String, dynamic> get _trace =>
      (_json['contexts'] as Map<String, dynamic>)['trace']
          as Map<String, dynamic>;

  /// The operation name, which is what a transaction is listed under.
  String? get name => _json['transaction'] as String?;

  /// `ok`, `internal_error`, `unknown` and the rest, as the wire spells them.
  String? get status => _trace['status'] as String?;

  /// Everything `TraceScope.note` and `count` attached.
  Map<String, dynamic> get data =>
      (_trace['data'] as Map<String, dynamic>?) ?? const {};

  /// The spans underneath, as the wire carries them.
  ///
  /// `SentrySpan` exposes `description` and `data` only through `context` and
  /// an internal field, so the JSON is the readable form here for the same
  /// reason it is above.
  List<Map<String, dynamic>> get childSpans => [
    for (final span in (_json['spans'] as List<dynamic>? ?? const []))
      span as Map<String, dynamic>,
  ];

  /// The operations of the spans underneath, for the nesting assertions.
  List<String> get childOperations => [
    for (final span in (_json['spans'] as List<dynamic>? ?? const []))
      (span as Map<String, dynamic>)['op'] as String,
  ];
}

/// Everything the other three channels handed over while a test ran.
///
/// Metrics, issues and breadcrumbs, which sentry 9 routes to three different
/// hooks - so a test that cares which channel a thing went down has to watch
/// all three at once or it cannot tell "counted" from "raised".
class CapturedSignals {
  final List<SentryMetric> metrics = [];
  final List<SentryEvent> events = [];
  final List<Breadcrumb> crumbs = [];

  /// The one counter, for the ordinary case of expecting exactly one.
  SentryMetric get metric => metrics.single;

  /// [metric]'s attributes as the wire carries them.
  ///
  /// A subset is what to assert against: the SDK adds `os.name`,
  /// `sentry.sdk.version` and `sentry.environment` on the way past, so an
  /// equality would break on an SDK bump that gave us more of them for free.
  Map<String, Object?> get attributes =>
      metric.attributes.map((key, value) => MapEntry(key, value.value));

  /// How much has arrived, over all three channels.
  ///
  /// What [settleAndClose] watches for a stop, and the only reason it is here:
  /// a test asserts on one channel, but "has the SDK finished" is a question
  /// about all of them.
  int get count => metrics.length + events.length + crumbs.length;
}

/// Brings a hub up with metrics, issues and breadcrumbs kept instead of sent.
///
/// The counterpart of [captureTransactions], and separate from it because the
/// hooks are: `beforeSendMetric` runs inside the metric capture pipeline,
/// *before* the in-memory buffer, so a test reads a counter without waiting on
/// a flush.
Future<CapturedSignals> captureSignals() async {
  final seen = CapturedSignals();
  await Sentry.init((options) {
    options.dsn = _testDsn;
    options.transport = NowhereTransport();
    options.beforeSendMetric = (metric) {
      seen.metrics.add(metric);
      return metric;
    };
    options.beforeSend = (event, hint) {
      seen.events.add(event);
      return event;
    };
    options.beforeBreadcrumb = (crumb, hint) {
      if (crumb != null) seen.crumbs.add(crumb);
      return crumb;
    };
  });
  addTearDown(Sentry.close);
  return seen;
}

/// Brings a hub up with the production sinks installed over it.
///
/// `Telemetry.start` wires five sinks - `_wireSinks` is the list - and going
/// through it rather than assigning one by hand is what keeps a test honest:
/// that list is the one that ships. The two asserted below are the ones every
/// caller so far drives; `resetTelemetrySinks` puts all five back, and this
/// registers it, so a file that forgets cannot leave a sink pointing at a
/// closed hub for the next one to trip over.
///
/// **One of the five is `LogService.keptSink`**, so a `recordKeptLines()` has
/// to come *after* this call or telemetry's own sink replaces the recorder.
///
/// The SDK's own init is a no-op: the hub is already up, and
/// `SentryFlutter.init` would replace it with one nothing can read. Quiet
/// because `start()` reports the missing `path_provider` plugin at `caught`,
/// which is a stack per case in a talking build.
Future<CapturedSignals> wiredHub() async {
  final seen = await captureSignals();
  final telemetry = Telemetry(
    settings: DiagnosticsSettings(),
    dsn: 'https://key@o1.ingest.de.sentry.io/2',
    init: (configure) async {},
    shutdown: () async {},
  );
  await quietlyAsync(telemetry.start);
  // The precondition every case rests on, asserted rather than assumed.
  // `start()` never throws by design and the line above swallows its console,
  // so a start that began returning early - a flipped default, a plan that
  // rejected the fake DSN - would leave every case green and empty, which is
  // this repo's "passed for a different reason" shape.
  expect(guardedFailureSink, isNotNull);
  expect(connectFailureSink, isNotNull);
  addTearDown(resetTelemetrySinks);
  return seen;
}

/// Lets the SDK finish what the app handed it, then closes the hub.
///
/// The SDK is handed its work **unawaited**: `Sentry.metrics.count` returns
/// void and unawaits its own capture, and `Telemetry._guard` hands
/// `captureException` a future and returns - which is what keeps reporting off
/// a path where a user is waiting. So a case that asserted straight away would
/// be reading a pipeline still in flight, and the close is what then drains
/// the buffers.
///
/// **How many turns that takes is not ours to know**, which is the whole shape
/// of this function. The metric pipeline awaits a lifecycle dispatch and then
/// builds the default attributes before it reaches `beforeSendMetric`, and
/// `captureException` runs a longer chain still.
///
/// [until] is what the caller is waiting for - normally that the channel it
/// asserts on is no longer empty. **Waiting for stability instead of for
/// arrival is what made this flaky**, and the comment that replaced said so
/// without drawing the conclusion: "stability at *zero* is what a case
/// expecting nothing looks like and also what a case whose first signal has
/// not arrived yet looks like, and only the floor tells them apart. Twenty
/// zero-duration timers cost less than a millisecond." A floor measured in
/// sub-millisecond event-loop hops does not tell them apart on a loaded
/// runner: the hub closed with the pipeline still in flight, the list was
/// empty, and `metrics.single` threw `Bad state: No element`. `main` failed
/// that way on roughly a third of its runs - 39026749284 and 39054542998 -
/// with a different case each time, which is the signature.
///
/// So the wait is against a real clock and for the thing itself, and a case
/// that never gets it fails here, naming what did arrive, rather than ten
/// lines later as an empty-list `Bad state`.
///
/// Omitting [until] means "nothing should arrive", which cannot be waited for
/// - that case gets the quiet window alone, and [_quietTicks] of real idleness
/// is what makes the absence worth asserting. It is also why the quiet window
/// still runs after [until] is satisfied: a case that asserts one channel is
/// empty has to give a late signal on that channel the chance to disprove it.
Future<void> settleAndClose(
  CapturedSignals seen, {
  bool Function()? until,
}) async {
  final deadline = DateTime.now().add(_deadline);
  if (until != null) {
    while (!until() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_tick);
    }
    if (!until()) {
      await Sentry.close();
      fail(
        'Waited $_deadline and what this case asserts on never arrived: '
        '${seen.metrics.length} metric(s), ${seen.events.length} event(s), '
        '${seen.crumbs.length} breadcrumb(s). If nothing is meant to arrive, '
        'call settleAndClose without `until`.',
      );
    }
  }
  var quiet = 0;
  var last = seen.count;
  while (quiet < _quietTicks && DateTime.now().isBefore(deadline)) {
    // A real delay and not `Duration.zero`: this has to yield the whole event
    // loop *and* let wall-clock time pass, because the SDK's own chain crosses
    // timers and the point is to outlast it rather than to out-hop it.
    await Future<void>.delayed(_tick);
    quiet = seen.count == last ? quiet + 1 : 0;
    last = seen.count;
  }
  await Sentry.close();
}

/// One step of either wait.
const Duration _tick = Duration(milliseconds: 2);

/// Ticks with nothing new before the SDK is taken to be done - 20 ms of real
/// idleness, against the sub-millisecond total the turn-counting version spent.
const int _quietTicks = 10;

/// The ceiling, so a hung pipeline fails as a named missing signal rather than
/// as a test that never returns. Generous because it is only ever reached on
/// the way to a failure.
const Duration _deadline = Duration(seconds: 5);
