import 'dart:async';
import 'dart:io';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flipperlib/flipperlib.dart' as fl show File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/config.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/pages/devices/device_scope.dart';
import 'package:qunleashed/pages/devices/firmware/directory.dart';
import 'package:qunleashed/pages/devices/firmware/repository.dart';
import 'package:qunleashed/pages/devices/firmware/update_settings.dart';
import 'package:qunleashed/services/notifications/push_service.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'archive_fakes.dart';
import 'fake_device.dart';
import 'kept_lines.dart';

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
  List<dynamic> files = const <dynamic>[],
}) => {'version': version, 'changelog': changelog, 'files': files};

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
  // Installs the recorder as well as emptying it. **Call this from `setUp`,
  // not `setUpAll`**: `recordKeptLines` registers an `addTearDown`, which
  // needs a test's own zone and throws outside one - and the error points
  // at `kept_lines.dart` rather than at the caller, so it is worth
  // knowing here. Most of what this function resets is a process-wide
  // singleton, which makes `setUpAll` the natural thing to reach for.
  //
  // Every caller is a `setUp`,
  // and `keptAbout` below is the only way the firmware tests see a log line -
  // so a file that resets state but never installs the sink reads every
  // `expect(keptAbout(...), hasLength(1))` as a silence that is not there.
  recordKeptLines();
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
    keptLines.where((l) => l.contains(fragment)).toList();

/// The connection half of a client, and - since #413 - a Flipper that can
/// actually be connected, with storage behind it.
///
/// Everything else throws through [noSuchMethod], so a caller that starts
/// reaching for something new fails here rather than quietly reading a null.
///
/// ## What "connected" needs, and why it took a change
///
/// [arrive] has always put a connection event on the stream, but it carries
/// `device: null`, so `DeviceController._onConnectionState` leaves `_device`
/// null - and `isConnected` is `_device != null && !_deviceDisconnected`.
/// `connected` was therefore the one state no whole-app test could observe.
/// The others were all reachable: `connecting` off the [connecting] field,
/// `dfu` and `recovering` off the controller's own setters, and both readings
/// of `disconnected`. [arriveWithDevice] carries a device, and that is the
/// whole of the difference.
///
/// Two things follow from it that a caller has to know:
///
///  * **`deviceLoading` is true until device info arrives.** A connection
///    event runs `_ensureDataLoading`, which sets the flag and subscribes to
///    [deviceInfoUpdates]. On the stay-connected path nothing clears it but a
///    non-empty event - a disconnect and a session reset clear it too, and
///    both are reachable from here through [stir], but neither leaves the
///    controller connected. The bottom bar reads "Syncing" the whole time,
///    which is not the state most cases are after - so [arriveWithDevice]
///    takes an `info` map and publishes it; a caller who wants the loading
///    state passes `info: const {}`.
///  * **`connectedDevice` stays null on purpose.** It is what
///    `DeviceInfoWatchService._runCollection` reads on its first line, and a
///    null parks the whole collection cycle there - no RPC burst, no battery
///    timer, nothing for the binding's pending-timer check to find. The
///    device the controller holds comes off the event instead.
///
///    Two things cannot be reached because of it, and the second is the one
///    worth knowing: the watch service itself, and `DeviceController`'s
///    **constructor** path - `_device = _client.connectedDevice` with the
///    `_ensureDataLoading()` that follows it, which is the warm session a
///    home-screen widget leaves behind. A client that is already connected
///    when the controller is built cannot be made here at all.
class FakeFlipperClient with FlipperRpcFake implements FlipperClient {
  final _connection = StreamController<FlipperConnectionState>.broadcast();
  final _sessions = StreamController<List<FlipperSessionInfo>>.broadcast();
  final _info = StreamController<Map<String, String>>.broadcast();

  bool _connected = false;

  /// Directory path -> the entries a list of it returns.
  ///
  /// Empty is a Flipper with nothing on its SD card, which is what an archive
  /// sync over this fake walks unless a case seeds it.
  final Map<String, List<fl.File>> tree = {};

  /// Remote path -> the bytes a read of it returns.
  final Map<String, String> bodies = {};

  /// Every request this has been asked for, by its `whichContent()`.
  final List<String> requests = [];

  /// What [getName] answers: null until a device arrives with a hardware
  /// name, and settable by a case that wants one sooner.
  ///
  /// The least of the three places `ArchiveController._deviceName` comes
  /// from. `initialize()` reads `getName()` before any device has arrived,
  /// falls back to `.last_device` on disk, and then takes the `hardware_name`
  /// off the next info patch - which is the route that names a sync here.
  String? name;

  /// The device coming back: the flag flips and the stream says so.
  ///
  /// Shaped to what the recovery wait reads rather than to what the real
  /// client emits: it consults `isConnected` and ignores the event's
  /// contents, so the device this carries is left null.
  ///
  /// **Also the stand-in for the five-second device-info poll.**
  /// `DeviceController` turns this into the same `notifyListeners` that
  /// `services/connection/device_info_watch.dart` produces, and the poll
  /// itself cannot be driven from here - the watch service is parked, for the
  /// reason this class's doc gives. Every test that asserts something does
  /// or does not rebuild on the poll fires this instead, and the scope does
  /// not care which of the two it was.
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

  /// A Flipper arriving **with a device**, which is what makes the controller
  /// read as connected.
  ///
  /// [info] is published straight after, because a connection event on its own
  /// leaves `deviceLoading` true - see the note on this class. The default
  /// carries a hardware name, since that is what the device screen's title and
  /// the archive's folder are both read from.
  void arriveWithDevice({
    FlipperDevice? device,
    Map<String, String> info = const {
      'hardware_name': archiveTestDevice,
      'firmware_version': '1.3.4',
    },
  }) {
    _connected = true;
    if (info.containsKey('hardware_name')) name = info['hardware_name'];
    _connection.add(
      FlipperConnectionState(
        mode: FlipperMode.rpc,
        device: device ?? flipperDevice('fake', archiveTestDevice),
        connected: true,
      ),
    );
    // **After the connection event has been delivered, not with it.**
    // `DeviceController` subscribes to `deviceInfoUpdates` from inside its
    // connection handler - `_ensureDataLoading` is what opens it - and a
    // broadcast stream delivers an event only to the listeners it had when
    // the event was added. Published in line, the patch lands before that
    // subscription exists and is dropped on the floor, which leaves
    // `deviceLoading` true for ever and the bottom bar reading "syncing" in
    // a case that is about anything else. One microtask is the whole of the
    // ordering: the `add` above queues the delivery, and this queues behind
    // it.
    if (info.isNotEmpty) scheduleMicrotask(() => publish(info));
  }

  /// A device-info patch, as the watch service's collection cycle would
  /// publish one.
  ///
  /// `DeviceController` drops an empty map, so this is also the only way to
  /// move `deviceLoading` to false.
  ///
  /// Accumulated as well as broadcast, because the real session does both
  /// (`session.dart`'s `_deviceInfoWatchSnapshot`), and the archive's storage
  /// cards seed from the snapshot on subscribe rather than waiting for a
  /// patch - so [deviceInfoWatchSnapshot] existing is not optional. The first
  /// run of `shell_device_label_test.dart` threw
  /// `has no instance getter 'deviceInfoWatchSnapshot'` out of a card
  /// rebuild. Nothing yet distinguishes accumulating from answering
  /// `const {}`.
  final Map<String, String> _watchSnapshot = {};

  void publish(Map<String, String> info) {
    _watchSnapshot.addAll(info);
    _info.add(info);
  }

  @override
  Map<String, String> get deviceInfoWatchSnapshot =>
      Map.unmodifiable(_watchSnapshot);

  @override
  Stream<Map<String, String>> get deviceInfoUpdates => _info.stream;

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
  Future<void> close() async {
    await _sessions.close();
    await _connection.close();
    await _info.close();
  }

  @override
  String? getName() => name;

  @override
  Future<String> awaitName() async => name ?? '';

  /// Device paths whose read throws instead of answering.
  ///
  /// The seam for a sync that finishes with files missing rather than one
  /// that dies: `_readRemoteBytes` catches per file, so the walk completes,
  /// counts the failure and leaves `lastError` set - which is the difference
  /// between `ArchiveSyncStatus.idle` and `synced` at the end of a sync, and
  /// since #420 the difference between two strings on the bottom bar.
  ///
  /// A `bodies` entry that is simply absent is **not** this: it reads as an
  /// empty file and saves successfully.
  ///
  /// A `StateError` carrying the firmware's own status name, which is what
  /// `archive_failure_reason_test.dart` refuses with: the sync keys its
  /// per-cause tally on `'$error'`, so the shape of the throw is what a
  /// reader of that summary sees.
  final Set<String> readFailures = <String>{};

  /// Storage answers out of [tree], [bodies] and [readFailures].
  ///
  /// Only the two requests an archive sync makes - a directory listing and a
  /// file read. Anything else is recorded in [requests] and answered with
  /// nothing, which is how a sync over an empty tree walks to completion
  /// rather than throwing.
  @override
  List<Main> framesFor(Main request) {
    requests.add(request.whichContent().toString());
    if (request.hasStorageListRequest()) {
      return [listingOf(tree, request.storageListRequest.path)];
    }
    if (request.hasStorageReadRequest()) {
      final path = request.storageReadRequest.path;
      if (readFailures.contains(path)) {
        throw StateError('ERROR_STORAGE_DENIED');
      }
      return [contentsOf(bodies[path] ?? '')];
    }
    return const [];
  }

  /// Whether anything is still listening.
  ///
  /// `Future.timeout` times out the future and cannot reach the work behind
  /// it, so a wait built on `firstWhere().timeout()` left a listener on this
  /// broadcast stream after every deadline - and the stream lives as long as
  /// the client.
  bool get hasListener => _connection.hasListener;

  /// What `connectionState` asks before it answers "disconnected".
  ///
  /// A plain field so a test can say the client is mid-connect without an
  /// event; the real one flips this around a connect attempt.
  bool connecting = false;

  @override
  bool get isConnecting => connecting;

  @override
  bool get isConnected => _connected;

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  /// One Flipper for the fake's whole life, so the update tracker has a device
  /// to hold the flash against.
  @override
  String? get scopedDeviceId => 'fake';

  /// Nothing connected at construction, which is load-bearing twice over:
  /// `DeviceController` reads it once in its constructor, and
  /// `DeviceInfoWatchService` reads it on the first line of its collection
  /// cycle. See this class's doc for what that buys and what it costs.
  @override
  FlipperDevice? get connectedDevice => null;

  /// Never anything on it. `DeviceController` subscribes in its constructor
  /// and only notifies on an event, so an empty stream is the whole contract.
  @override
  Stream<List<FlipperSessionInfo>> get sessionsStream => _sessions.stream;

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
  final client = FakeFlipperClient();
  final device = DeviceController(client: client);
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
  // Through `builder` rather than around `home`, because that is where the
  // app puts it - above the Navigator, so a pushed route is inside it too
  // (ADR 0011). Wrapping `home` instead would leave every case that opens a
  // route testing a tree the app does not have.
  builder: (context, navigator) =>
      DeviceScope(notifier: device, child: navigator!),
  home: child,
);

/// A widget that depends on [DeviceScope] the listening way and counts its
/// builds.
///
/// The control in a **pair assertion**: "nothing rebuilt" also passes when the
/// notification never arrived, so a case that claims a widget ignores the
/// device-info poll has to show the poll reached the scope's dependents at
/// all. This rebuilds whenever the scope notifies, whatever the subject under
/// test depends on - which is exactly why it has to be a separate widget. A
/// subject that both reads the scope and witnesses the notification is the
/// thing being tested, so it cannot also be the control.
///
/// It lives here rather than in either test because both wanted it byte for
/// byte: `app_detail_rebuild_scope_test.dart` (where it started, as
/// `_ScopeProbe`) and `device_scope_client_of_test.dart`. Both already import
/// this file for [mountedDevice], [wrapWithDevice] and [closeDevice], so
/// sharing it costs no new import anywhere.
class DeviceScopeProbe extends StatelessWidget {
  const DeviceScopeProbe({super.key, required this.onBuild});

  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    DeviceScope.of(context);
    onBuild();
    return const SizedBox.shrink();
  }
}
