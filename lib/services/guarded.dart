import 'logging.dart';

/// Runs [task] and records a failure rather than letting it reach the zone.
///
/// For a future nobody is waiting on. There is no caller to hand the failure
/// back to and no UI path it can take, so the log is the only place it can
/// land. A rejection with *no* handler at all is still recorded, through the
/// uncaught handlers #89 installed — but only as `[uncaught]`, with nothing
/// saying which operation it was. Catching buys the label; what catching and
/// then logging at `info` bought was nothing at all.
///
/// The returned future completes when [task] settles and **never rejects**.
/// The queues that call this depend on that: they chain the next operation
/// with `previous.then(...)`, and `then` on a rejected future skips its
/// callback and propagates — so one failed link would strand every operation
/// behind it for the life of the chain. They pass the whole
/// `previous.then(op)` expression rather than just `op`, so the chain heals
/// itself even if that guarantee is ever broken.
///
/// ## Why [LogService.error]
///
/// The level is fixed rather than a parameter, because a per-site level choice
/// is the drift this exists to close — and what these sites had been doing
/// was not choosing at all, which left them on a level that is not kept. The
/// paragraph above is why that was worse than never catching.
///
/// It does leave a seam: the same dropped input is `warn` where `_sendInput`
/// catches it and `error` where it reaches here. The tie-breaker is that
/// nobody is coming to look at this one.
///
/// ## Why `try`/`await`, and not `Future.sync(task).catchError(...)`
///
/// It was that pair, and the pair broke the promise above for a caller whose
/// task returns something non-nullable.
///
/// [task] is declared `Future<void> Function()`, and `void` is a top type, so
/// a `Future<GpsReadiness> Function()` satisfies it and the analyzer is
/// content. At runtime `Future.sync` hands back the caller's own future
/// untouched whenever `result is Future<T>` — which `Future<GpsReadiness>`
/// passes against `Future<void>`. So `catchError` ran against a future whose
/// real type argument was `GpsReadiness`, while the handler here returns
/// nothing. On the first task that actually threw, the handler ran, wrote its
/// line, and *then* `catchError` raised `ArgumentError: ... must return a
/// value of the future's type` — rejecting the future the queues are promised
/// cannot reject. QUNLEASHED-A; every event so far was on Windows, and each
/// shares a trace with a QUNLEASHED-B `GeolocatorGpsProvider.ensureReady`
/// throw.
///
/// It is non-*nullability* that trips it, not non-`void`: the handler returns
/// `null`, which satisfies `FutureOr<int?>` but not `FutureOr<int>`. Both
/// halves are in `guarded_test.dart`'s matrix, which is where the rule is
/// kept rather than in a census here that nothing would fail to update.
///
/// `try`/`await` rather than `catchError` is the fix: there is no
/// type-argument check left to get wrong. The generic is for honesty at
/// direct call sites and does *not* close the class on its own — a wrapper
/// that re-declares `Future<void> Function()` erases it again one frame up,
/// which is exactly what `bootstrap._start` did on the path that produced
/// QUNLEASHED-A.
///
/// It keeps what [Future.sync] was here for: the callee need not be `async`,
/// and `task()` is called inside the `try`, so a synchronous throw lands in
/// the same place as a rejection. `FlipperClient.writeCliBytes` is the live
/// example of that shape — `_CliPageState._fireAndShow` has the detail.
///
/// [onFailure] runs after the message is recorded, for a site that can also
/// tell the user. It is passed the error only: anything that wants the stack
/// wants the log. It comes back out if it ever drops to one caller.
///
/// Two neighbouring shapes are deliberately *not* this. `IrLibLocalRepo` uses
/// `catchError(..., test: ...)` so a fault outside the one it expects is not
/// quietly turned into a no-op, and [guarded] has no such narrowing.
/// `MediaRemoteBridge._syncNativeState` hands the real rejection to an awaiting
/// caller and neuters only the copy it stores, which [guarded] would swallow.
Future<void> guarded<T>(
  String what,
  Future<T> Function() task, {
  void Function(Object error)? onFailure,
}) async {
  try {
    await task();
  } catch (error, stack) {
    _record(what, 'failed', error, stack);
    if (onFailure == null) return;
    try {
      onFailure(error);
    } catch (e, st) {
      _record(what, 'failure handler threw', e, st);
    }
  }
}

/// A second reader for what [guarded] catches, installed by whoever has one.
///
/// [what] is the label the call site passed, [verb] says whether it was the
/// task or its failure handler that threw, and the error and stack are the
/// originals rather than the formatted line - a crash reporter wants the
/// exception object to group on, not a string.
typedef GuardedFailureSink = void Function(
  String what,
  String verb,
  Object error,
  StackTrace stack,
);

/// Where [guarded]'s failures go besides the log, or nowhere.
///
/// Null until something installs one. `lib/services/telemetry/` does, when
/// reporting is on, and clears it again when it is turned off - which is the
/// direction ADR 0013 §2 asks for: this file knows there may be a second
/// reader, and nothing about who it is. The alternative was importing the SDK
/// here, which §2 and `test/sentry_import_guard_test.dart` both forbid.
///
/// A plain mutable static rather than a list of listeners. There is one
/// consumer and no use for a second; a list would be a registry nobody
/// deregisters from.
GuardedFailureSink? guardedFailureSink;

/// Writes one failure down without letting it cost the never-rejects contract.
///
/// `'$error'` calls `toString()` on an arbitrary object, and one that throws is
/// real enough that logging.dart guards it in two places. Unguarded here it
/// would escape the `catchError` callback and reject the future the queues are
/// promised cannot reject — losing the whole chain rather than one log line,
/// and losing the message too. The fallback interpolates only [what] and
/// [verb], which are already Strings.
///
/// The stack is appended only when there is one. Most of flipperlib rejects
/// through a bare `completeError(error)`, which yields `StackTrace.empty`, so
/// appending unconditionally would end those entries with a blank line and
/// nothing after it.
///
/// [guardedFailureSink] runs after the log and in a `try` of its own, for the
/// same contract: a sink that throws must cost neither the log line above it
/// nor the future the queues are promised cannot reject. It runs second so
/// that the local record is written even if the remote one is what breaks —
/// the log is the surface somebody can actually open.
void _record(String what, String verb, Object error, StackTrace stack) {
  try {
    final trace = stack.toString();
    LogService.error(
      trace.isEmpty ? '$what $verb: $error' : '$what $verb: $error\n$trace',
    );
  } catch (_) {
    // `runtimeType`, not the object: interpolating the object is what threw.
    // The type names the culprit, which "an error" does not.
    //
    // And a second try, because this block also covers a `LogService.error`
    // that throws - in which case calling it again would throw again, escape
    // the `catchError` callback and reject the future four queues are promised
    // cannot reject. That is the exact loss the doc above says this guard
    // exists to prevent.
    try {
      LogService.error(
        '$what $verb: a ${error.runtimeType} whose toString() threw',
      );
    } catch (_) {
      // The logger itself is gone. Nothing can be written, and the contract
      // that this never rejects outranks the line.
    }
  }
  final sink = guardedFailureSink;
  if (sink == null) return;
  try {
    sink(what, verb, error, stack);
  } catch (e) {
    // Not `describe`: that reads the stack of the sink's own failure, and the
    // one thing worth saying here is which sink broke on which operation.
    // `$what` only: it is already a String, so this cannot be the thing that
    // throws. The error is named by type for the reason the fallback above
    // gives.
    LogService.warn(
      '[Telemetry] the guarded sink threw on "$what": ${e.runtimeType}',
    );
  }
}
