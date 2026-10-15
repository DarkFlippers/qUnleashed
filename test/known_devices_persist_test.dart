import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/connection/known_devices.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kept_lines.dart';
import 'refusing_prefs.dart';

/// The remembered-device list that will not save, which is the one failure in
/// the #313 sweep that loses something durable.
///
/// `_persist` is deliberately not on `persistSetting`; the ruling, and the
/// level it turns on, are written beside the code in `known_devices.dart`.
class _Discovered implements DiscoveredDevice {
  const _Discovered(this.id, this.transport);

  @override
  final String id;

  @override
  String get name => id;

  @override
  final DeviceTransport transport;
}

FlipperDevice _ble(String id) => FlipperDevice(
  id: id,
  name: id,
  link: FlipperLink.ble,
  source: _Discovered(id, DeviceTransport.ble),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  final known = KnownDevicesStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    // The store is a singleton and outlives any one case.
    await known.load();
    for (final device in [...known.devices]) {
      await known.forget(device);
    }
    clearKeptLines();
  });

  // The level is the whole reason this site did not move onto persistSetting,
  // so it is asserted rather than assumed: `warn` - which is what that
  // function logs - is dropped by a log kept at QLOG_LEVEL=error, and this
  // one has to survive there.
  test('a store that refuses the write says so, at error', () async {
    useRefusingPrefs();

    await known.remember(_ble('B1'));

    expect(
      keptLines.where((l) => l.contains('the store refused the write')),
      isNotEmpty,
    );
    expect(keptLevels, everyElement(KeptLevel.error));
  });

  // #120's rule reaches here too: the list on screen keeps the device, and
  // the user finds out at the next launch, when it is gone.
  test('the device stays in the list for this session', () async {
    useRefusingPrefs();

    await known.remember(_ble('B1'));

    expect(known.devices.map((d) => d.id), contains('B1'));
  });

  test('a write that worked says nothing', () async {
    await known.remember(_ble('B1'));

    expect(keptLines, isEmpty);
    expect(known.devices.map((d) => d.id), contains('B1'));
  });
}
