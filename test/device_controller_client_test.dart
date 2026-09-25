import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/models/connection_state.dart';

import 'firmware_fixture.dart';

/// That `DeviceController` uses the client it was handed - ADR 0002.
///
/// The controller used to build its own from `FlipperOneClient()`, so every
/// widget test in this suite ran one against real BLE streams for the length
/// of the run, while the `FakeFlipperClient` beside it drove only the widgets.
/// The two looked connected in `mountedDevice()`'s signature and were not.
///
/// Both cases below fail if the parameter stops being used: the controller
/// goes back to listening to a client nothing in the test can reach.
void main() {
  // resetFirmwareState touches controllers that read WidgetsBinding.instance,
  // and nothing here is a testWidgets case to initialise it.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetFirmwareState);

  test('listens to the client it was given', () async {
    final (device, client) = mountedDevice();
    var notified = 0;
    device.addListener(() => notified++);

    client.stir();
    await pumpEventQueue();

    expect(notified, 1, reason: 'a global client would say nothing here');
  });

  test('reads its connection state from the same one', () {
    final (device, client) = mountedDevice();

    expect(device.connectionState, DeviceConnectionState.disconnected);

    client.connecting = true;

    expect(device.connectionState, DeviceConnectionState.connecting);
  });
}
