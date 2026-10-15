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
/// `_persist` is deliberately not on `persistSetting` - that function fixes
/// the level at warn, and this is `error`, because `notifyListeners` has
/// already run and the picker shows a Flipper that will be gone at the next
/// launch. What it shares is the half #313 was about: `setString` answering
/// `false` without throwing.
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

  Iterable<String> errors(String fragment) => [
    for (var i = 0; i < keptLines.length; i++)
      if (keptLevels[i] == KeptLevel.error && keptLines[i].contains(fragment))
        keptLines[i],
  ];

  test('a store that refuses the write says so, at error', () async {
    useRefusingPrefs();

    await known.remember(_ble('B1'));

    expect(errors('the store refused the write'), isNotEmpty);
  });

  // The level is the whole reason this site did not move onto persistSetting,
  // so it is asserted rather than assumed: `warn` would be dropped by a log
  // kept at QLOG_LEVEL=error, which is where this one has to survive.
  test('the refusal is not reported at warn', () async {
    useRefusingPrefs();

    await known.remember(_ble('B1'));

    expect(
      keptLevels.where((l) => l == KeptLevel.warning),
      isEmpty,
      reason: 'persistSetting would have logged at warn; this must not',
    );
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
