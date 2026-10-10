// Suite-wide setup, which `flutter_test` wraps every `main()` in.
//
// There is one thing in here and it is not a style preference. `LogService`
// folds a line that repeats *consecutively* into the one before, and that
// memory is a static with no owner: the first test to log `[CLI] write failed`
// leaves the second one silently folded away, so a sink that is installed and
// working records nothing and the test reads as if the wiring were broken.
// This cost half a day of chasing the wrong file.
//
// It used to be cleared as a side effect of emptying the in-app log buffer,
// which every logging test did in `setUp`. ADR 0013 §1 removed the buffer, and
// resetting the fold by hand in forty files is the version of this that goes
// stale the first time somebody adds the forty-first.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/logging.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(LogService.debugForgetLastKept);
  await testMain();
}
