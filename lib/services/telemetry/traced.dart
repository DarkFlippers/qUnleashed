import 'package:sentry_flutter/sentry_flutter.dart';

import 'scrub.dart';

/// A handle on the operation being timed, for the few facts worth attaching.
///
/// Deliberately small and deliberately not an `ISentrySpan`. Feature code
/// calls [traced] the way it calls `guarded`, and what it can say about an
/// operation is "here is a fact" and "that happened again" — not the SDK's
/// whole span API. Narrow enough that a call site cannot accidentally report
/// something ADR 0013 §6 forbids.
abstract interface class TraceScope {
  /// Attaches one fact to the operation.
  ///
  /// String values are scrubbed on the way in, because this is sent. Numbers
  /// and bools go as they are — a count or a flag cannot carry a filename.
  ///
  /// §6 governs what belongs here more than the type does: MIFARE recovery
  /// reports its duration and the attack kind, never a key or a UID.
  void note(String key, Object? value);

  /// Counts an occurrence, reported as `<key>` with the total.
  ///
  /// §2 asks for this by name: a file upload restarts after auto-reconnect,
  /// so "how long did the transfer take" is meaningless without "and how many
  /// times did it start over".
  void count(String key);

  /// Says the operation did not do what was asked, though nothing threw.
  ///
  /// Several of the operations §2 names return a failure instead of raising
  /// one - `FirmwareInstaller.install` is documented as never throwing, every
  /// fault arriving as an `UpdateError`. Without this, every failed install
  /// would be a successful transaction, which is worse than no transaction:
  /// the duration would be real and the verdict would be a lie.
  ///
  /// [why] is attached as `failure`, so the kinds can be told apart without
  /// opening each one. It is scrubbed, like any other string.
  void failed([String? why]);
}

/// The one implementation.
///
/// There is no second, no-op one, because there is nothing for it to do: an
/// unconfigured hub hands back a no-op span, so every `setData` below already
/// goes nowhere in a build with no DSN. A null scope would make every call
/// site ask a question whose answer never matters.
class _SpanScope implements TraceScope {
  _SpanScope(this._span);

  final ISentrySpan _span;
  final Map<String, int> _counts = {};

  @override
  void note(String key, Object? value) {
    _span.setData(key, value is String ? Scrub.outbound(value) : value);
  }

  @override
  void count(String key) {
    final total = (_counts[key] ?? 0) + 1;
    _counts[key] = total;
    _span.setData(key, total);
  }

  @override
  void failed([String? why]) {
    _failed = true;
    if (why != null) note('failure', why);
  }

  /// Read by [traced] after the body returns, so a `failed()` call is not
  /// undone by the `ok` it would otherwise set.
  bool get didFail => _failed;
  bool _failed = false;
}

/// Times [body] as one operation a user waited on, and reports it.
///
/// [ADR 0013 §2](../../../docs/adr/0013-observability-with-sentry.md) names
/// what belongs here: connect, firmware install, file transfer, app install,
/// DFU and MIFARE recovery. Not every async call — these are the ones where
/// "it was slow" is a bug report somebody files.
///
/// ## Its own transaction, not a child span
///
/// `SentryNavigatorObserver` finishes a screen's transaction a few seconds
/// after the route settles, so a two-minute firmware install started from that
/// screen would have no parent left to attach to and the span would be
/// dropped. A transaction of its own also matches what these are: a unit of
/// work the user started, not part of a screen load.
///
/// A child span *is* created when something else is already tracing — nested
/// `traced` calls, which is how "install" can contain "transfer".
///
/// ## It does not change what the caller sees
///
/// The result and any exception pass straight through, and the operation is
/// marked failed on the way. Nothing here catches: a `traced` that swallowed
/// would be a reporting feature that broke the thing it reports on.
///
/// Cheap with no DSN rather than free: `startTransaction` on an unconfigured
/// hub returns a no-op span, so every `setData` goes nowhere, but the scope
/// object and its counter map are still built. These are operations measured
/// in seconds — one allocation each is not the thing to optimise, and a second
/// code path to avoid it would be a second code path nothing exercises.
Future<T> traced<T>(
  String operation,
  Future<T> Function(TraceScope trace) body, {
  String? description,
}) async {
  final parent = Sentry.getSpan();
  final span = parent == null
      ? Sentry.startTransaction(operation, operation, bindToScope: true)
      : parent.startChild(operation, description: description);
  if (description != null && parent == null) {
    span.setData('description', Scrub.outbound(description));
  }

  final scope = _SpanScope(span);
  try {
    final value = await body(scope);
    // The body's own verdict wins over "it returned normally", which is what
    // `failed()` exists for.
    span.status = scope.didFail
        ? const SpanStatus.internalError()
        : const SpanStatus.ok();
    return value;
  } catch (e) {
    // `internalError` and the throwable, so the transaction is searchable
    // alongside the issue `guarded` or the uncaught handler will have raised
    // for the same failure.
    span.status = const SpanStatus.internalError();
    span.throwable = e;
    rethrow;
  } finally {
    // Awaited, so `await traced(...)` returning means the operation has been
    // recorded. Unawaited it was fire-and-forget, which is fine in a shipped
    // build and unobservable in a test - the first version of
    // `traced_test.dart` captured nothing because `Sentry.close()` ran before
    // the finish landed. A test that cannot see the thing it is about is not
    // the price of saving a microtask here: `finish` enqueues, it does not
    // wait for the network.
    //
    // `catchError` and not `guarded`: this file is imported by feature code,
    // and `guarded` logs through `LogService`, which reports *through*
    // telemetry - a cycle. The guarantee is the same one, that this never
    // rejects, because it sits in a `finally` and a throw here would replace
    // the caller's own exception.
    await span.finish().catchError((_) {});
  }
}
