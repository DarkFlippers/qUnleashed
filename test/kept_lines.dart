// What `LogService` forwarded while a test ran.
//
// Replaces `LogService.history`, which is gone: ADR 0013 §1 makes Sentry the
// only channel, so the in-memory buffer that used to be the app's own record
// no longer exists. `keptSink` is the seam production uses, so a test that
// observes it is watching the thing that ships rather than a buffer kept alive
// for its benefit.
//
// What a line looks like here differs from the old history in two ways, and
// both are the point:
//
//  * **No timestamp.** The stamp was for a human reading a screen; Sentry
//    stamps its own. It is still applied to the console, which is where
//    `log_timestamp_test.dart` now looks for it.
//  * **No `(N×)` suffix.** The fold is still there — `LogService` forwards only
//    the first of a run, so the *number* of lines here matches what the old
//    history held — but the count was a display detail of the buffer.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/logging.dart';

/// The bodies `LogService` forwarded, oldest first.
List<String> keptLines = <String>[];

/// The levels it forwarded them at, in step with [keptLines].
List<KeptLevel> keptLevels = <KeptLevel>[];

/// Starts recording, and stops at the end of the test.
///
/// Call from `setUp`. Installs the sink and clears both lists, so a test never
/// inherits another's; the teardown takes the sink off, because it is a static
/// and would otherwise outlive the list it appends to.
void recordKeptLines() {
  keptLines = <String>[];
  keptLevels = <KeptLevel>[];
  LogService.keptSink = (level, body) {
    keptLevels.add(level);
    keptLines.add(body);
  };
  addTearDown(() {
    LogService.keptSink = null;
    keptLines = <String>[];
    keptLevels = <KeptLevel>[];
  });
}

/// Forgets what has been recorded so far, without taking the sink off.
///
/// For a test that logs during its own arrangement and wants to assert only on
/// what the act produced.
void clearKeptLines() {
  keptLines.clear();
  keptLevels.clear();
}
