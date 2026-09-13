import 'package:flipperlib/flipperlib.dart';

/// Asks the device whether the desktop is locked, and gets an answer back.
///
/// `desktopIsLocked()` returns `Future<List<Main>>` and the list is always
/// empty: IsLockedRequest answers with an empty frame and puts the state in
/// `command_status` — OK for locked, ERROR for unlocked — so the generic
/// "anything but OK is a failure" handling turns the ordinary case into a
/// rejection. The firmware source is quoted on #94.
///
/// An extension in the library's own `Flipper*Api on FlipperClient` idiom,
/// beside FlipperGpsApi and FlipperNetworkApi, rather than a private method on
/// the one page that needed it: the trap is as wide as the API, so the cooked
/// call should be too — the next person reaching for `client.desktop…` meets
/// this instead of rediscovering the defect. It belongs on the library's own
/// FlipperDesktopApi; it is here because dart-flipperlib is upstream of this
/// project rather than a repository it can merge into. Worth carrying up with
/// the next bump.
extension FlipperDesktopLockApi on FlipperClient {
  Future<bool> desktopIsLockedNow() async {
    try {
      // rightNow, as the open's other two requests are. Nothing undoes a poll,
      // so unlike the subscribe this is latency rather than correctness — and
      // little of that, but one priority across the operation is easier to
      // reason about than two.
      final frames = await desktopIsLocked(
        priority: FlipperRequestPriority.rightNow,
      );
      // Preferred when it is there. It never is against the firmware read for
      // #94, but OK alone means locked, so a variant that did answer properly
      // would otherwise be read as locked whatever it actually said.
      for (final frame in frames) {
        if (frame.hasDesktopStatus()) return frame.desktopStatus.locked;
      }
      return true;
    } on FlipperRpcException catch (e) {
      // Only the bare ERROR means unlocked. A status the firmware does not
      // implement, or a session in a bad state, still throws — a real failure
      // must not be reported as an unlocked device. Matching on the status
      // rather than the exception type is deliberate: FlipperRpcGeneralException
      // is also the bucket every unmapped status falls into.
      if (e.status != CommandStatus.ERROR) rethrow;
      return false;
    }
  }
}
