// Swapping `debugPrint` for the duration of one call.
//
// Three copies of [quietly] and one of [printed] had accumulated across the
// test suite, byte-identical apart from whether the lines were kept. The
// repo's convention for shared test code is a plain unsuffixed file in
// `test/` - `ratchet.dart`, `fake_app_client.dart`, `seed_fakes.dart` - so
// this is that.
//
// Both restore the previous value **inline** rather than through
// `addTearDown`, and that is not a style choice: `flutter_test` rejects a
// teardown that changes a debug variable, because it checks them for
// modification between tests. A `try`/`finally` is what is left.
import 'package:flutter/foundation.dart';

/// Silences the console while [body] runs, so the test output stays readable.
///
/// Most of the logging tests record at `error`, which prints a full stack in a
/// talking build; without this a green run is thousands of lines of noise.
void quietly(void Function() body) {
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {};
  try {
    body();
  } finally {
    debugPrint = previous;
  }
}

/// What `debugPrint` received while [body] ran.
///
/// The capturing half of [quietly]: the console is still silenced, and the
/// lines come back instead. Null messages are dropped - `debugPrint` accepts
/// one and no caller means anything by it.
List<String> printed(void Function() body) {
  final lines = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  try {
    body();
  } finally {
    debugPrint = previous;
  }
  return lines;
}

/// [printed], for a [body] that has to be awaited.
///
/// Not [printed] with an `async` body passed to it: that returns the moment
/// the first `await` inside suspends, `debugPrint` is restored, and the lines
/// the rest of the call prints go to the real console and come back as an
/// empty list - a test that then asserts `isEmpty` passes for the wrong
/// reason.
Future<List<String>> printedAsync(Future<void> Function() body) async {
  final lines = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  try {
    await body();
  } finally {
    debugPrint = previous;
  }
  return lines;
}

/// [quietly], for a [body] that has to be awaited.
///
/// [printedAsync] without the list, for a case that reads what was *kept*
/// rather than what was printed and only wants the console silenced. Passing
/// an `async` body to [quietly] restores `debugPrint` at the first suspension
/// and lets the rest of the call print for real.
Future<void> quietlyAsync(Future<void> Function() body) async {
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {};
  try {
    await body();
  } finally {
    debugPrint = previous;
  }
}
