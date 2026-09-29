import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/services/connection/known_devices.dart';
import 'package:qunleashed/services/home_widget/cold_link.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The only way a home-screen widget reaches a Flipper, and what it says when
/// it cannot.
///
/// This runs in the headless isolate, where there is no UI to put a failure
/// in: the widget draws its "no device" face, which is the same face it draws
/// when no device is remembered at all. The false it returns does not say
/// which of the two happened, and at info the log did not either. #103,
/// ADR 0008.
class _ColdFlipper implements FlipperClient {
  _ColdFlipper({this.dialThrows});

  /// Raised instead of connecting, when set. A bond that is gone, a radio
  /// that is off, a Flipper that is not there.
  final Object? dialThrows;

  bool connected = false;

  @override
  bool get isConnected => connected;

  @override
  bool get isConnecting => false;

  @override
  Future<FlipperDevice> connectBleAddress(
    String address, {
    String? name,
    Duration? timeout,
  }) async {
    if (dialThrows != null) throw dialThrows!;
    connected = true;
    return FlipperDevice(
      id: address,
      name: name ?? address,
      link: FlipperLink.ble,
      source: _Discovered(address),
    );
  }

  /// `ping` is an extension over this, so it resolves statically and arrives
  /// here rather than being overridable itself.
  @override
  Future<FlipperRpcBatch<T>> callRpc<T extends GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
  }) async => FlipperRpcBatch<T>(
    commandId: 0,
    request: request,
    frames: const [],
    items: const [],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Discovered implements BleDiscoveredDevice {
  const _Discovered(this.id);

  @override
  final String id;

  @override
  String get name => id;

  @override
  DeviceTransport get transport => DeviceTransport.ble;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FlipperDevice _ble(String id) => FlipperDevice(
  id: id,
  name: id,
  link: FlipperLink.ble,
  source: _Discovered(id),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int logBase;

  /// Remembers one BLE device, which is what a cold start dials.
  Future<void> remember(String id) async {
    SharedPreferences.setMockInitialValues(const {});
    final known = KnownDevicesStore.instance;
    await known.load();
    for (final device in [...known.devices]) {
      await known.forget(device);
    }
    await known.remember(_ble(id));
  }

  setUp(() {
    LogService.clearHistory();
    logBase = LogService.history.length;
  });

  Iterable<String> lines(String fragment) =>
      LogService.history.skip(logBase).where((l) => l.contains(fragment));

  group('a widget that could not reach its Flipper', () {
    test('says so, where the false it returns does not', () async {
      await remember('B1');
      LogService.clearHistory();

      final up = await ColdLink.instance.ensureConnected(
        _ColdFlipper(dialThrows: StateError('bond gone')),
      );

      expect(up, isFalse);
      expect(lines('connect failed'), hasLength(1));
    });

    test('says what the radio said', () async {
      await remember('B1');
      LogService.clearHistory();

      await ColdLink.instance.ensureConnected(
        _ColdFlipper(dialThrows: StateError('bond gone')),
      );

      expect(lines('bond gone'), hasLength(1));
    });
  });

  group('nothing to say', () {
    test('when the Flipper answers', () async {
      await remember('B1');
      LogService.clearHistory();

      expect(await ColdLink.instance.ensureConnected(_ColdFlipper()), isTrue);
      expect(lines('[ColdLink]'), isEmpty);
    });

    // The other half of the "no device" face, and not a failure: there is
    // nothing to dial, so nothing was tried.
    test('when no device is remembered', () async {
      SharedPreferences.setMockInitialValues(const {});
      final known = KnownDevicesStore.instance;
      await known.load();
      for (final device in [...known.devices]) {
        await known.forget(device);
      }
      LogService.clearHistory();

      final up = await ColdLink.instance.ensureConnected(
        _ColdFlipper(dialThrows: StateError('bond gone')),
      );

      expect(up, isFalse);
      expect(lines('connect failed'), isEmpty);
    });

    test('when the link is already up', () async {
      await remember('B1');
      LogService.clearHistory();

      final client = _ColdFlipper(dialThrows: StateError('bond gone'))
        ..connected = true;

      expect(await ColdLink.instance.ensureConnected(client), isTrue);
      expect(lines('[ColdLink]'), isEmpty);
    });
  });
}
