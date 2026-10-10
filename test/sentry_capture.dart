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
    options.dsn = 'https://key@o0.ingest.sentry.io/0';
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

  /// The operations of the spans underneath, for the nesting assertions.
  List<String> get childOperations => [
    for (final span in (_json['spans'] as List<dynamic>? ?? const []))
      (span as Map<String, dynamic>)['op'] as String,
  ];
}
