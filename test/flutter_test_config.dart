// Suite-wide setup, which `flutter_test` wraps every `main()` in.
//
// There is one kind of thing in here and it is not a style preference.
// `LogService`
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
import 'package:qunleashed/components/icon.dart';
import 'package:qunleashed/components/notification.dart';
import 'package:qunleashed/services/connection/known_devices.dart';
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
  // `_RasterIconCache._recorded` is the fourth: it bounds a failed rasterize to
  // one record per asset and size, and nothing in the app ever clears it, by
  // design. So the first test to fail an icon silences every later test for
  // that asset - and the silence looks exactly like a `_record` that is not
  // wired up. #441.
  setUp(debugForgetRecordedIconFailures);
  // `KnownDevicesStore` is the fifth: `load()` memoises on `_loading` and
  // nothing cleared it, so a process got exactly one real load. Whichever case
  // ran first spent it - in practice on an empty store in a `setUp` - and
  // every later case saw a store that would not read its fixture.
  //
  // It is also the one of the five that is not permanent. The four above
  // rewind library statics with no owner, where a reset wired here is the
  // only shape available; this one rewinds a singleton's own fields, so it is
  // the right answer only until ADR 0002 reaches `KnownDevicesStore` and
  // `LinkService` takes the store as a parameter. Read as a precedent for
  // "a singleton leaked into a case, add a sixth `setUp`", it argues for
  // entrenching the thing 0002 wants gone.
  //
  // What is particular about it otherwise is where the bill arrived. The four
  // above are paid for in red, or in silence that reads as broken wiring.
  // This one was paid in test *shape*: a claim
  // about the load path needed a file to itself to get a fresh memo, so two
  // files held one case each, and six more cleared the store by hand across
  // seven sites. #452
  setUp(KnownDevicesStore.instance.debugReset);
  await testMain();
}
