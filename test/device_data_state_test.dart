// What `DeviceController._ensureDataLoading`'s guard is for.
//
// The guard is `_loadedForDeviceId == device.id && _dataState != none`, and
// #426 collapsed the two booleans behind that second clause into one
// three-valued state. Both halves of the old disjunct survive in `!= none`,
// and neither was pinned by anything: measured on the collapse, a guard
// narrowed to `== loading` and a guard narrowed to `== loaded` each left the
// whole suite green. This file covers the half that has consequences.
//
// The `loading` half does not, and that is worth recording rather than
// leaving as a gap somebody re-measures. Restarting a load that is already in
// flight cancels the info subscription, opens another, bumps the generation
// and re-enters the watch service - all redundant, none observable: `_info`
// is already `{}` at that point, the new subscription receives the patch the
// old one would have, and `connectedDevice` is null in this fixture so the
// watch service parks either way. It is a correct guard against wasted work,
// not against a wrong state, so `!= none` keeps it for free and no case here
// can fail when it goes.
import 'package:flutter_test/flutter_test.dart';

import 'archive_fakes.dart';
import 'fake_device.dart';
import 'firmware_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a second connection event for the same device keeps the data',
    () async {
      final (device, client) = mountedDevice();
      final flipper = flipperDevice('fake', archiveTestDevice);

      client.arriveWithDevice(device: flipper);
      await pumpEventQueue();

      expect(
        device.info['hardware_name'],
        archiveTestDevice,
        reason: 'premise',
      );
      expect(device.deviceLoading, isFalse, reason: 'premise');

      // The transitions the controller does not drive itself arrive as plain
      // connection events - a warm session promoted after a disconnect, an
      // activation swap, a link restored by the auto-reconnect - so the same
      // device can be announced again with its data already in. Without the
      // `loaded` half of the guard this re-enters `_startDataLoading`, which
      // empties `_info` and sets `loading`: the device screen loses every row
      // it was showing and the bottom bar drops back to "Syncing" with nothing
      // left to wait for, because the info that would clear it has already
      // been delivered.
      client.arriveWithDevice(device: flipper, info: const {});
      await pumpEventQueue();

      expect(device.info['hardware_name'], archiveTestDevice);
      expect(device.deviceLoading, isFalse);
    },
  );

  test('a reconnect to the same device loads again', () async {
    final (device, client) = mountedDevice();
    final flipper = flipperDevice('fake', archiveTestDevice);

    client.arriveWithDevice(device: flipper);
    await pumpEventQueue();
    expect(device.info['hardware_name'], archiveTestDevice, reason: 'premise');

    // The other side of the guard, and why it tests `_dataState` rather than
    // `_loadedForDeviceId` alone: a disconnect clears the state but leaves
    // the id set, so the same Flipper coming back has to restart the load.
    // A guard on the id by itself would answer "already loaded" to a session
    // whose data died with the link.
    client.stir();
    await pumpEventQueue();
    expect(device.isConnected, isFalse, reason: 'premise');

    client.arriveWithDevice(device: flipper, info: const {});
    await pumpEventQueue();

    expect(
      device.deviceLoading,
      isTrue,
      reason: 'the load restarted and no info has arrived yet',
    );
  });
}
