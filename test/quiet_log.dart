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
