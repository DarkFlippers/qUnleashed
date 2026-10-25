import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/widgets.dart';

import 'controllers/device.dart';

class DeviceScope extends InheritedNotifier<DeviceController> {
  const DeviceScope({super.key, required super.notifier, required super.child});

  /// The controller, with a dependency on it: the reader rebuilds whenever the
  /// device's state changes.
  ///
  /// For the sites that read live state - `isConnected`, `info`, `dfuPresent`,
  /// `connectionState` - and for the action calls that still go through the
  /// controller, which want no dependency but have no other way to reach it:
  /// `synchronize()`, `playAlert()`, `buildExportDump()`, `setRecovering()`.
  /// `test/device_scope_listen_test.dart` counts both kinds together, and its
  /// budget says which each one is.
  ///
  /// Everything that wants only [clientOf] should say so, because this
  /// notifies far more often than those readers think:
  /// `services/connection/device_info_watch.dart` polls on a five-second
  /// interval and `DeviceController` merges any non-empty patch and notifies
  /// without comparing it, so a connected idle Flipper rebuilds every
  /// dependent up to twelve times a minute. **And the subscription does not
  /// lapse.** Nothing clears `Element._dependencies` on a rebuild - only
  /// `activate`, `_ensureDeactivated` and `unmount` touch it - so one of these
  /// in a gesture callback subscribes that element for its whole life, not
  /// until its next build.
  static DeviceController of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DeviceScope>()!.notifier!;
  }

  /// The client, without a dependency.
  ///
  /// There is exactly one for the run, at both ends: `DeviceController._client`
  /// is `final`, and the controller itself is `late final` in the state that
  /// builds the only `DeviceScope` in `lib/` (`app/app.dart`). So the
  /// device-info poll has nothing to tell a reader of this, and neither has
  /// anything else - [of] would hand the same object back and force a rebuild
  /// to do it.
  ///
  /// It returns the **client** rather than the controller to narrow what a
  /// non-listening read can reach. `info`, `dfuPresent`, `connectionState` and
  /// `deviceLoading` live on the controller, and a non-listening read of any
  /// of them in a `build` would be a silent staleness bug - the value would be
  /// whatever it was when something else last rebuilt the reader.
  ///
  /// It does not close the door, and the comment used to claim it did:
  /// `FlipperClient` has its own `isConnected` and `deviceInfoCache`, so
  /// `clientOf(context).isConnected` compiles and is exactly that bug. What
  /// the type buys is that the obvious stale reads are out of reach and the
  /// remaining two are on an object whose own streams are the right answer -
  /// `connectionStream` and `deviceInfoUpdates`, which is what `QPageAppBar`
  /// already does. `test/device_scope_listen_test.dart` is the ratchet that
  /// keeps the client-only reads here.
  ///
  /// `getInheritedWidgetOfExactType` reads the current widget without
  /// registering a dependency, so a swapped scope is still read correctly on
  /// the reader's next build - it just does not cause one. Flutter's doc on it
  /// also blesses a value read in a gesture callback or a timer, used once and
  /// not cached; several of these call sites hand the client into a pushed
  /// route that keeps it, which that wording does not cover. The argument that
  /// covers them is the first one above: there is only ever one client.
  static FlipperClient clientOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<DeviceScope>()!
        .notifier!
        .client;
  }
}
