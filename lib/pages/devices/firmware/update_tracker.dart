import 'package:flutter/foundation.dart';

import 'update_state.dart';

/// Which Flipper each firmware update belongs to, and how far it has got.
///
/// An update outlives the screen that started it. The flash is bound to the
/// session it began on and carries on there whatever the user does next, so the
/// one thing a device switch may not do is lose track of it: holding the
/// progress in the button's own state meant that switching away threw it out,
/// and coming back showed a Flipper with no update running, offering to start
/// one - over a firmware that was already half written.
///
/// Keyed by the device and by the firmware entry that started the update, so
/// what shows the progress is the button that would have started it.
class FirmwareUpdateTracker extends ChangeNotifier {
  FirmwareUpdateTracker._();

  static final FirmwareUpdateTracker instance = FirmwareUpdateTracker._();

  final Map<String, ({String entry, UpdateState state})> _byDevice = {};

  UpdateState? stateFor(String? deviceId, String entry) {
    if (deviceId == null) return null;
    final held = _byDevice[deviceId];
    return held != null && held.entry == entry ? held.state : null;
  }

  void publish(String? deviceId, String entry, UpdateState state) {
    if (deviceId == null) return;
    _byDevice[deviceId] = (entry: entry, state: state);
    notifyListeners();
  }

  void clear(String? deviceId) {
    if (deviceId == null) return;
    if (_byDevice.remove(deviceId) != null) notifyListeners();
  }
}
