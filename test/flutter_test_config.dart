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
import 'package:qunleashed/components/notification.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/storage/permissions.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(LogService.debugForgetLastKept);
  // `storage/permissions.dart` holds the resolved permission, the
  // once-per-process prompt and the outcome sink as library statics with
  // no owner - the same shape as the log fold above, and the same failure:
  // a test that reaches them leaks a memoised answer, or a stale sink, into
  // every test after it. #351.
  setUp(debugResetStoragePermissionState);
  // `QNotification._current` is the third of these: the notification on
  // screen, held as a library static, so a case that shows one leaves a live
  // handle behind and the next `show()` closes an entry belonging to a
  // torn-down tree. Harmless only because `OverlayEntry.remove` returns early
  // on an unmounted overlay - the framework's guarantee, not the component's.
  //
  // Every test that shows a notification reaches it, including the ones that
  // only do so through production code, which is why the reset is here and
  // not a list of file names kept by hand. QUNLEASHED-S.
  setUp(QNotification.debugReset);
  await testMain();
}
