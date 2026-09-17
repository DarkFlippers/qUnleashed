import 'logging.dart';

/// Runs [task] and records a failure rather than letting it reach the zone.
///
/// For a future nobody is waiting on. That is the whole of it: there is no
/// caller to return the failure to and no UI path it can take, so the log is
/// the only place it can land, and a failure that does not land there did not
/// happen as far as anyone can tell.
///
/// The returned future completes when [task] settles and **never rejects**.
/// The queues that call this depend on that: they chain the next operation
/// with `previous.then(...)`, and `then` on a rejected future skips its
/// callback and propagates — so one failed link would strand every operation
/// behind it for the life of the chain.
///
/// ## Why [LogService.error] and not [LogService.log]
///
/// `log` is `info`, and `info` is not kept: it never enters
/// [LogService.history], so it cannot reach the log screen, and since
/// `enabled` follows the build type the branch is shaken out of a release
/// build altogether. A fire-and-forget failure logged there reports nowhere at
/// all in the builds people run. `error` is `keep: true`, so it survives both.
///
/// The level is fixed rather than a parameter, and that is most of the point:
/// what this exists to prevent is a per-site level choice. A site where
/// `error` overstates it is a site where somebody is waiting.
///
/// ## Why [Future.sync]
///
/// The callee need not be `async`. `FlipperClient.writeCliBytes` is the live
/// example: a session that is already gone throws *before* there is a future
/// to attach a handler to, while a session whose transport has been torn down
/// rejects instead — and both read "No active transport", so the difference is
/// easy to miss. [Future.sync] puts the synchronous throw and the rejection in
/// the same place.
///
/// The stack goes in with the message. For a future nobody awaited it is the
/// only thing that says where the failure came from, and [LogService.history]
/// keeps one entry per message rather than per line, so it stays one event.
///
/// [onFailure] runs after the message is recorded, for a site that can also
/// tell the user. It is passed the error only: anything wanting the stack
/// wants the log. A throw from it is recorded and does not reject the returned
/// future — the caller of a fire-and-forget has nowhere to catch that either.
Future<void> guarded(
  String what,
  Future<void> Function() task, {
  void Function(Object error)? onFailure,
}) => Future.sync(task).catchError((Object error, StackTrace stack) {
  LogService.error('$what failed: $error\n$stack');
  if (onFailure == null) return;
  try {
    onFailure(error);
  } catch (e, st) {
    LogService.error('$what failure handler threw: $e\n$st');
  }
});
