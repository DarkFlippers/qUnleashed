import 'logging.dart';

/// Runs [task] and records a failure rather than letting it reach the zone.
///
/// For a future nobody is waiting on. There is no caller to hand the failure
/// back to and no UI path it can take, so the log is the only place it can
/// land. A rejection with *no* handler at all does reach [LogService.history],
/// through the uncaught handlers #89 installed — but only as `[uncaught]`,
/// with nothing saying which operation it was. Catching buys the label; what
/// catching and then logging at `info` bought was nothing at all.
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
/// ## Why [Future.sync]
///
/// The callee need not be `async`, and then it throws before there is a future
/// to attach a handler to. `FlipperClient.writeCliBytes` is the live example —
/// `_CliPageState._fireAndShow` has the detail. [Future.sync] puts the synchronous
/// throw and the rejection in the same place.
///
/// [onFailure] runs after the message is recorded, for a site that can also
/// tell the user. It is passed the error only: anything that wants the stack
/// wants the log. One caller today, and it should come back out if it never
/// gains a second.
///
/// Two neighbouring shapes are deliberately *not* this. `IrLibLocalRepo` uses
/// `catchError(..., test: ...)` so a fault outside the one it expects is not
/// quietly turned into a no-op, and [guarded] has no such narrowing.
/// `MediaRemoteBridge._syncNativeState` hands the real rejection to an awaiting
/// caller and neuters only the copy it stores, which [guarded] would swallow.
Future<void> guarded(
  String what,
  Future<void> Function() task, {
  void Function(Object error)? onFailure,
}) => Future.sync(task).catchError((Object error, StackTrace stack) {
  _record(what, 'failed', error, stack);
  if (onFailure == null) return;
  try {
    onFailure(error);
  } catch (e, st) {
    _record(what, 'failure handler threw', e, st);
  }
});

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
void _record(String what, String verb, Object error, StackTrace stack) {
  try {
    final trace = stack.toString();
    LogService.error(
      trace.isEmpty ? '$what $verb: $error' : '$what $verb: $error\n$trace',
    );
  } catch (_) {
    LogService.error('$what $verb: an error whose toString() threw');
  }
}
