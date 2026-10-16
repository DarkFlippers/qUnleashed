// Driving a real Sentry hub with the transport replaced, and reading what it
// produced.
//
// Two copies of this had grown, in `traced_test.dart` and
// `transfer_restart_count_test.dart`, differing in one line - and
// `contexts.trace` was picked out of `toJson()` in three places with three
// spellings. The repo's convention for shared test code is a plain unsuffixed
// file in `test/`.
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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
/// `captureException` runs a longer chain still. One `Duration.zero` hop was
/// enough on a warm developer machine and not on CI, where nine cases read an
/// empty list and the suite was green locally - so this drains the event loop
/// until nothing new has arrived for [_quietTurns] consecutive turns, instead
/// of guessing a number.
///
/// A case that expects nothing settles immediately, at zero, which is correct:
/// the loop is watching for *stability*, not for arrival.
Future<void> settleAndClose(CapturedSignals seen) async {
  var quiet = 0;
  var last = -1;
  for (var turn = 0; turn < _maxTurns; turn++) {
    if (turn >= _minTurns && quiet >= _quietTurns) break;
    // A zero-duration timer and not `await null`: this has to yield the whole
    // event loop, not just drain microtasks, because the SDK's own chain
    // crosses timers.
    await Future<void>.delayed(Duration.zero);
    quiet = seen.count == last ? quiet + 1 : 0;
    last = seen.count;
  }
  await Sentry.close();
}

/// Turns with nothing new before the SDK is taken to be done.
const int _quietTurns = 5;

/// Turns to drain before the quiet count may end the loop at all.
///
/// The floor matters more than the quiet count: stability at *zero* is what a
/// case expecting nothing looks like and also what a case whose first signal
/// has not arrived yet looks like, and only the floor tells them apart. Twenty
/// zero-duration timers cost less than a millisecond.
const int _minTurns = 20;

/// The ceiling, so a hung pipeline fails as a missing signal rather than as a
/// test that never returns.
const int _maxTurns = 200;
