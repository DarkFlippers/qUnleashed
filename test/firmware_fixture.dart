import 'dart:async';
import 'dart:io';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/config.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/pages/devices/device_scope.dart';
import 'package:qunleashed/pages/devices/firmware/directory.dart';
import 'package:qunleashed/pages/devices/firmware/repository.dart';
import 'package:qunleashed/pages/devices/firmware/update_settings.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/notifications/push_service.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a firmware test needs to keep itself off the network and out of the
/// previous test's state.
///
/// Extracted when a second firmware test file wanted the same setup.
/// `firmware_selection_test.dart` still carries its own partial copy and has
/// not been moved over - it seeds directories rather than stubbing the feed,
/// and reconciling the two is its own change.

/// The firmwares the app ships with.
final FirmwareEntry unleashed = QAppConfig.firmware.firmwares.firstWhere(
  (f) => f.shortName == 'unlshd',
);
final FirmwareEntry official = QAppConfig.firmware.firmwares.firstWhere(
  (f) => f.shortName == 'ofw',
);

/// How many directory requests the feed has been asked for.
int fetchCalls = 0;

/// A directory document carrying [channels] verbatim, so a case can be as
/// malformed as it needs to be.
Map<String, dynamic> feed(List<dynamic> channels) => {'channels': channels};

/// One channel of a directory document.
Map<String, dynamic> channelJson(
  String id,
  List<dynamic> versions, {
  String? title,
  String description = '',
}) => {
  'id': id,
  'title': title ?? id,
  'description': description,
  'versions': versions,
};

/// One version of a channel.
Map<String, dynamic> versionJson(
  String version, {
  String changelog = 'notes',
  int timestamp = 0,
  List<dynamic> files = const <dynamic>[],
}) => {
  'version': version,
  'changelog': changelog,
  'timestamp': timestamp,
  'files': files,
};

/// A directory feed of the shape the parsers expect.
Map<String, dynamic> feedJson() => feed([
  channelJson('release', [versionJson('1.0.0')], title: 'Release'),
]);

/// The same feed after `version` stopped being a string upstream.
///
/// `version` is one of the two fields `FirmwareDirectoryReader` will not do
/// without, so the one version here is dropped - which empties the one
/// channel, which empties the document. That last step is what makes this a
/// failure rather than a partial read: a feed with a second, good version
/// would keep it and carry on. Raised by the decode itself rather than by a
/// stand-in thrown from the seam.
Map<String, dynamic> feedOfTheWrongShape() => feed([
  channelJson('release', [
    {...versionJson('1.0.0'), 'version': 1},
  ], title: 'Release'),
]);

/// Answers every firmware's directory request with [fetch].
void feedEvery(Future<dynamic> Function(Uri uri) fetch) {
  for (final entry in QAppConfig.firmware.firmwares) {
    parserForEntry(entry).fetchJson = (uri) {
      fetchCalls++;
      return fetch(uri);
    };
  }
}

void feedWorks() => feedEvery((_) async => feedJson());

/// Drops the cached directories, so a fetch that runs reaches the feed.
///
/// Without it a sync is invisible: `ensure` short-circuits on `isFresh`, so
/// one and twelve of them count the same in [fetchCalls].
void forgetDirectories() {
  for (final entry in QAppConfig.firmware.firmwares) {
    parserForEntry(entry).clearCache();
  }
}

void feedFails([Object error = const SocketException('down')]) =>
    feedEvery((_) async => throw error);

/// Drops the process-wide state a firmware test touches, then points the feed
/// at a working directory.
///
/// The theme controller is in here because `FirmwareCard` drives it: a test
/// that moves the active firmware leaves the next one starting on a different
/// carousel page, with the arrow it wanted to press disabled. The theme mode
/// leaks the same way, and `setThemeMode` early-returns on an unchanged mode,
/// so a later test expecting a notify would get none and pass vacuously.
///
/// `flutter_test` answers an unreplaced request with a 400, so without the
/// last line an unseeded firmware records a failure and logs a line per run.
void resetFirmwareState() {
  LogService.clearHistory();
  SharedPreferences.setMockInitialValues(const {});
  UpdateSettingsStore.instance.reset();
  FirmwareRepository.instance.reset();
  QAppThemeController.instance.setActiveFirmware(QAppConfig.defaultFirmware);
  // Unawaited because this is a `void` reset and only the synchronous half -
  // the mode and its notify - is what it is for. The tail writes `theme.mode`
  // into the store installed at the top of this function, during this test,
  // and the next reset wipes it again. Most runs write nothing at all:
  // `setThemeMode` returns early on an unchanged mode.
  unawaited(QAppThemeController.instance.setThemeMode(QThemeMode.firmware));
  PushService.instance.taps.value = null;
  fetchCalls = 0;
  forgetDirectories();
  feedWorks();
}

/// The kept log lines mentioning [fragment].
List<String> keptAbout(String fragment) =>
    LogService.history.where((l) => l.contains(fragment)).toList();

/// Only the connection half of a client.
///
/// Everything else throws through [noSuchMethod], so a caller that starts
/// reaching for something new fails here rather than quietly reading a null.
class FakeFlipperClient implements FlipperClient {
  final _connection = StreamController<FlipperConnectionState>.broadcast();

  bool _connected = false;

  /// The device coming back: the flag flips and the stream says so.
  ///
  /// Shaped to what the recovery wait reads rather than to what the real
  /// client emits: it consults `isConnected` and ignores the event's
  /// contents, so the device this carries is left null.
  void arrive() {
    _connected = true;
    _connection.add(
      const FlipperConnectionState(
        mode: FlipperMode.rpc,
        device: null,
        connected: true,
      ),
    );
  }

  /// Connected, with nothing said on the stream.
  void arriveQuietly() => _connected = true;

  /// The link dropping, with nothing said on the stream.
  void depart() => _connected = false;

  /// A connection event that is not a connection. The stream carries these
  /// too, and a wait that took the first event for the device coming back
  /// would report a recovery that never happened.
  void stir() => _connection.add(
    const FlipperConnectionState(
      mode: FlipperMode.disconnected,
      device: null,
      connected: false,
    ),
  );

  /// A fault on the stream itself. A broadcast stream is not ended by one.
  void fail() => _connection.addError(const SocketException('link fault'));

  /// The link torn down - a disposed client, a closed session.
  Future<void> close() => _connection.close();

  /// Whether anything is still listening.
  ///
  /// `Future.timeout` times out the future and cannot reach the work behind
  /// it, so a wait built on `firstWhere().timeout()` left a listener on this
  /// broadcast stream after every deadline - and the stream lives as long as
  /// the client.
  bool get hasListener => _connection.hasListener;

  @override
  bool get isConnected => _connected;

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  /// One Flipper for the fake's whole life, so the update tracker has a device
  /// to hold the flash against.
  @override
  String? get scopedDeviceId => 'fake';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Controllers already disposed, so a teardown does not repeat it.
///
/// Never cleared, and it does not need to be: `DeviceController` has identity
/// equality and every test builds its own, so a stale entry can never match a
/// new one. It holds a reference to each disposed controller for the
/// isolate's life, which at this test count is nothing.
final Set<DeviceController> _closed = {};

/// A device controller and a client for a widget test.
///
/// The controller is real: it constructs fine under `flutter test`, and the
/// firmware widgets all need a `DeviceScope` carrying one.
///
/// End a widget test with [closeDevice].
///
/// The controller starts a DFU detector whose libusb backend polls on a
/// one-second timer where the library is present - Linux CI, not a Windows
/// dev box. The binding checks for live timers before tearDown runs, so
/// disposing from a teardown is too late: the test then fails on the pending
/// timer rather than on its assertions, which is how the recovery tests first
/// failed on CI while passing locally.
///
/// Calling it is always safe. Not every test here does - the changelog cases
/// in firmware_failure_test.dart leave it to the teardown and pass - so the
/// exact condition for arming the timer is narrower than this, and nobody has
/// pinned down what it is.
(DeviceController, FakeFlipperClient) mountedDevice() {
  final device = DeviceController();
  final client = FakeFlipperClient();
  addTearDown(() async {
    if (_closed.add(device)) device.dispose();
    await client.close();
  });
  return (device, client);
}

/// Tears the tree down and stops the controller's timers, inside the body.
Future<void> closeDevice(WidgetTester tester, DeviceController device) async {
  await tester.pumpWidget(const SizedBox());
  if (_closed.add(device)) device.dispose();
  // Disposing arms teardown timers of its own - the Windows hotplug watcher
  // sets a one-second one - so let those expire in the body as well.
  await tester.pump(const Duration(seconds: 2));
}

/// A tree a firmware widget can be built in.
Widget wrapWithDevice(Widget child, DeviceController device) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: DeviceScope(notifier: device, child: child),
);
