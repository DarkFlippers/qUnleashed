import 'dart:async';

import 'package:fixnum/fixnum.dart' show Int64;
import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/services/connection/device_info_watch.dart';
import 'package:qunleashed/services/connection/device_settings.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the background info collector writes down when the device will not
/// answer, and what it deliberately does not.
///
/// Everything this service asks for renders as a field on the device screen,
/// and a field that never arrives renders as a blank - which says nothing
/// about why it is blank. The one-shot reads are the last word on their field
/// for the whole session; the five-second battery poll is not, and a line per
/// tick would push the rest of the log screen out. #103, ADR 0008.
///
/// The burst is driven once per outcome rather than once per case: it carries
/// two unconditional 300 ms waits and a two-second one, and the assertions
/// below are all reads of the same log.
class _Discovered implements UsbDiscoveredDevice {
  const _Discovered();

  @override
  String get id => 'test-flipper';

  @override
  String get name => 'TestFlipper';

  @override
  DeviceTransport get transport => DeviceTransport.usb;
}

const _device = FlipperDevice(
  id: 'test-flipper',
  name: 'TestFlipper',
  link: FlipperLink.usb,
  source: _Discovered(),
);

class _SilentFlipper implements FlipperClient {
  _SilentFlipper({this.answers = false});

  /// Whether the device answers at all. False is a link that is up but a
  /// Flipper that will not talk - every request times out or errors.
  final bool answers;

  bool connected = true;

  final List<Map<String, String>> patches = [];

  /// Every completed storage operation on the device. The collector refreshes
  /// the SD card figure off this rather than polling for it.
  final mutations = StreamController<void>.broadcast();

  @override
  bool get isConnected => connected;

  @override
  bool get isRpcReady => connected;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  @override
  bool get storageBusy => false;

  @override
  bool get cliHeld => false;

  /// Collection binds to whatever is connected when it starts, and stops the
  /// moment that stops being the active device - so it has to be one.
  @override
  FlipperDevice? get connectedDevice => _device;

  @override
  Stream<void> get storageMutations => mutations.stream;

  @override
  bool get deviceInfoFetched => false;

  @override
  Map<String, String> get deviceInfoCache => const {};

  @override
  void publishDeviceInfoPatch(Map<String, String> patch) => patches.add(patch);

  @override
  Future<Map<String, String>> awaitDeviceInfo() async {
    if (!answers) throw StateError('no reply');
    return const {'hardware_name': 'TestFlipper'};
  }

  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  /// Everything below awaitDeviceInfo is an extension method over these two,
  /// so it resolves statically and arrives here rather than being overridable
  /// itself.
  List<Main> _framesFor(Main request) {
    if (!answers) throw StateError('no reply');
    if (request.hasStorageInfoRequest()) {
      return [
        Main(
          storageInfoResponse: InfoResponse(
            totalSpace: Int64(100),
            freeSpace: Int64(50),
          ),
        ),
      ];
    }
    if (request.hasPropertyGetRequest()) {
      return [
        Main(
          propertyGetResponse: GetResponse(
            key: 'pwrinfo.battery.current',
            value: '0.1',
          ),
        ),
      ];
    }
    if (request.hasSystemProtobufVersionRequest()) {
      return [
        Main(systemProtobufVersionResponse: ProtobufVersionResponse(major: 0)),
      ];
    }
    if (request.hasSystemGetDatetimeRequest()) {
      return [Main(systemGetDatetimeResponse: GetDateTimeResponse())];
    }
    if (request.hasSystemPowerInfoRequest()) {
      return [
        Main(
          systemPowerInfoResponse: PowerInfoResponse(
            key: 'charge_level',
            value: '77',
          ),
        ),
      ];
    }
    return const [];
  }

  @override
  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
    bool retainFrames = true,
    bool interleavable = false,
    bool pipelined = true,
  }) async {
    final frames = _framesFor(request);
    for (final frame in frames) {
      onFrame?.call(frame);
    }
    return frames;
  }

  @override
  Future<FlipperRpcBatch<T>> callRpc<T extends GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
  }) async {
    final frames = _framesFor(request);
    final items = <T>[];
    for (final frame in frames) {
      onFrame?.call(frame);
      final picked = pick(frame);
      if (picked != null) items.add(picked);
    }
    return FlipperRpcBatch<T>(
      commandId: 0,
      request: request,
      frames: frames,
      items: items,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The lines the burst left behind, keyed by the outcome it ran with.
  final logs = <bool, List<String>>{};

  /// Runs the phase-1 burst to the end and hands back what it said.
  ///
  /// The burst is stopped rather than left running: phase 2 polls on a
  /// five-second timer, and nothing below is about the poll.
  Future<List<String>> burst({required bool answers}) async {
    final cached = logs[answers];
    if (cached != null) return cached;
    // The clock is only pushed to the device when the user has asked for it,
    // and that setting is the last thing the burst reads.
    SharedPreferences.setMockInitialValues({'device.sync_time_on_start': true});
    DeviceSettings.instance.reset();
    LogService.clearHistory();
    final base = LogService.history.length;
    final client = _SilentFlipper(answers: answers);
    DeviceInfoWatchService.instance.start(client);
    // The burst carries two 300 ms waits and a two-second one, all
    // unconditional, plus the requests between them.
    await Future<void>.delayed(const Duration(milliseconds: 3500));
    // A completed storage operation, which is the only thing that asks for
    // the SD card figure again. It debounces for a second first.
    client.mutations.add(null);
    await Future<void>.delayed(const Duration(seconds: 2));
    DeviceInfoWatchService.instance.stop();
    await client.mutations.close();
    return logs[answers] = LogService.history.skip(base).toList();
  }

  tearDownAll(() {
    DeviceInfoWatchService.instance.stop();
    DeviceSettings.instance.reset();
  });

  Future<Iterable<String>> silent(String fragment) async =>
      (await burst(answers: true)).where((l) => l.contains(fragment));

  Future<Iterable<String>> said(String fragment) async =>
      (await burst(answers: false)).where((l) => l.contains(fragment));

  group('a field that will not arrive again this session', () {
    // The snapshot behind every identifying field on the device screen. One
    // request, twenty-second timeout, no retry.
    test('is the device info snapshot', () async {
      expect(await said('no device info'), hasLength(1));
      expect(await silent('no device info'), isEmpty);
    });

    test('is the protobuf version', () async {
      expect(await said('no protobuf version'), hasLength(1));
      expect(await silent('no protobuf version'), isEmpty);
    });

    test('is the device clock', () async {
      expect(await said('could not read the device clock'), hasLength(1));
      expect(await silent('could not read the device clock'), isEmpty);
    });

    // Settings -> Storage and the card figure on the device screen both read
    // this, and the refresh behind it only runs after a storage operation.
    test('is the SD card info', () async {
      expect(await said('no SD card info'), hasLength(1));
      expect(await silent('no SD card info'), isEmpty);
    });

    // The same function runs again after every storage operation, and that
    // one leaves the last good figure on screen rather than a blank. One
    // line covers the read that filled it in; the refreshes do not each get
    // one, however many the user's file manager sets off.
    test('is the first read of it, not every refresh', () async {
      expect(await said('SD card'), hasLength(1));
    });

    // Which of the two it is cannot be read off the line, only off where it
    // sits: setting the clock is the last thing the burst does, and every
    // refresh runs after that.
    test('is the one from before any refresh could have run', () async {
      final lines = await burst(answers: false);
      expect(
        lines.indexWhere((l) => l.contains('SD card')),
        lessThan(
          lines.indexWhere((l) => l.contains('could not set the device clock')),
        ),
      );
    });

    // The user's own setting, which still reads as enabled afterwards.
    test('is the clock the app was asked to set', () async {
      expect(await said('could not set the device clock'), hasLength(1));
      expect(await silent('could not set the device clock'), isEmpty);
    });
  });

  group('what is deliberately left where a release build cannot see it', () {
    // The poll in phase 2 asks again every five seconds, so the first reading
    // is not the last word on the figure - and a line per tick over a link
    // that has gone would push the rest of the log screen out.
    //
    // Asserted as an absence because that is all an `info` is: it is
    // `keep: false`, so nothing sent there reaches [LogService.history] in
    // any build. Which is the whole of #103, and why the count lives in a
    // ratchet rather than here.
    test('is every battery reading', () async {
      expect(await said('battery'), isEmpty);
    });
  });

  // The other direction, and the one a slice gets wrong: promoting a site
  // that repeats is as much a regression as leaving one that does not.
  test('nothing else in the burst is kept', () async {
    expect(await said('[watchInfo]'), hasLength(5));
  });

  test('a Flipper that answers is not reported at all', () async {
    expect(await silent('[watchInfo]'), isEmpty);
  });
}
