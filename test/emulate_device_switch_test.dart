import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/archive/models/key.dart';
import 'package:qunleashed/services/emulate/service.dart';

/// What happens to an open emulation when the Flipper under it changes.
///
/// This is the reason `EmulateService` holds a binding instead of asking for
/// the active device per call, and it was the last uncovered branch of it:
/// until dart-flipperlib#6 a fake client could not return a binding that named
/// a device, so the service could not be driven through a switch at all.
///
/// The rule: gone from the screen means gone. An emulation is the window the
/// user tapped, and a Flipper they have moved on from should not be left
/// holding a scene open with nothing driving it. A link that merely dropped is
/// not that — it comes back, and the scene with it.
///
/// Two things here have no case, and both are findings rather than gaps.
///
/// `stop` hands every caller the same future rather than starting a second
/// teardown. Its effect is on `start`, which awaits an in-flight stop before
/// opening the next run, and making that race land the same way twice is not
/// something a test can do honestly.
///
/// Three guards stand between a queued button and the device, and only the
/// innermost one can be reached from outside. A stop clears `_sceneLoaded`
/// and `_activeKey`, so a queued command reloads the scene first and finds no
/// key to reload - and that is what turns it back, before `_running` or
/// `_txHeld` in front of it are consulted. Removing either of those two fails
/// nothing.
///
/// They are defence in depth on a keyed transmitter, which is a reasonable
/// thing to keep and not a thing a test can pin. Said here rather than left
/// implied, because a case named for `_running` would be a case passing on a
/// mechanism other than the one it claims - which this repository has now
/// done seven times.
class FakeSwitchClient implements FlipperClient {
  final _frames = StreamController<Main>.broadcast();
  final _connection = StreamController<FlipperConnectionState>.broadcast();

  /// The device the run binds when it starts.
  FlipperDevice? bound = usb('A');

  final calls = <String>[];

  /// Raised by `appExit`, so a stop that cannot reach the device can be shown
  /// not to strand the service.
  Object? exitThrows;

  /// Held open so a press can be left in flight while something else happens.
  Completer<void>? holdPress;

  Future<void> close() async {
    await _frames.close();
    await _connection.close();
  }

  /// A connection event of [event]'s kind.
  void report(FlipperConnectionEvent event) => _connection.add(
    FlipperConnectionState(
      mode: FlipperMode.rpc,
      device: bound,
      connected: event != FlipperConnectionEvent.disconnected,
      event: event,
    ),
  );

  @override
  bool get isConnected => true;

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  Stream<Main> get notificationStream => _frames.stream;

  @override
  FlipperSessionBinding bindCurrentSession() => bound == null
      ? const FlipperSessionBinding.unbound()
      : FlipperSessionBinding.to(bound!);

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
    if (request.hasAppStartRequest()) {
      calls.add('appStart');
      scheduleMicrotask(
        () => _frames.add(
          Main(appStateResponse: AppStateResponse(state: AppState.APP_STARTED)),
        ),
      );
      return const [];
    }
    if (request.hasAppLoadFileRequest()) {
      calls.add('appLoadFile');
      return const [];
    }
    if (request.hasAppExitRequest()) {
      calls.add('appExit');
      // The scene closes either way: the Flipper is gone, so the ack is what
      // failed rather than the close.
      scheduleMicrotask(
        () => _frames.add(
          Main(appStateResponse: AppStateResponse(state: AppState.APP_CLOSED)),
        ),
      );
      if (exitThrows != null) throw exitThrows!;
      return const [];
    }
    if (request.hasAppButtonPressRequest()) {
      calls.add('press');
      if (holdPress != null) await holdPress!.future;
      return const [];
    }
    if (request.hasAppButtonReleaseRequest()) {
      calls.add('release');
      return const [];
    }
    calls.add('unexpected');
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Discovered implements DiscoveredDevice {
  const _Discovered(this.id);

  @override
  final String id;

  @override
  String get name => id;

  @override
  DeviceTransport get transport => DeviceTransport.usb;
}

FlipperDevice usb(String id) => FlipperDevice(
  id: id,
  name: id,
  link: FlipperLink.usb,
  source: _Discovered(id),
);

ArchiveKey key() => ArchiveKey(
  name: 'garage',
  category: ArchiveCategory.subghz,
  state: ArchiveKeyState.synced,
  extension: '.sub',
  remotePath: '/ext/subghz/garage.sub',
);

void main() {
  late FakeSwitchClient client;
  late EmulateService service;

  setUp(() async {
    client = FakeSwitchClient();
    service = EmulateService(client: client);
    await service.start(key());
    client.calls.clear();
  });
  tearDown(() => client.close());

  /// Polls until [ready], or gives up after two seconds.
  Future<void> waitFor(bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!ready() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('a run is open to begin with', () {
    expect(service.isRunning, isTrue);
    expect(service.activeKey?.name, 'garage');
  });

  group('another Flipper taking its place', () {
    test('closes the run', () async {
      client.report(FlipperConnectionEvent.deviceChanged);
      await waitFor(() => !service.isRunning);

      expect(client.calls, contains('appExit'));
      expect(service.isRunning, isFalse);
      expect(service.activeKey, isNull);
    });

    // Closing it is the binding's job, and the binding is the one the run
    // started against - so the exit reaches the Flipper that is holding the
    // scene rather than the one that just took over.
    test('closes it once, not once per event', () async {
      client.report(FlipperConnectionEvent.deviceChanged);
      await waitFor(() => !service.isRunning);
      client.report(FlipperConnectionEvent.deviceChanged);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(client.calls.where((c) => c == 'appExit'), hasLength(1));
    });
  });

  group('the link merely dropping', () {
    // It comes back, and the scene with it. Closing here would take the
    // emulation away from a user whose Flipper is still in their hand.
    for (final event in const [
      FlipperConnectionEvent.disconnected,
      FlipperConnectionEvent.connecting,
      FlipperConnectionEvent.connected,
    ]) {
      test('leaves the run open: ${event.name}', () async {
        client.report(event);
        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(service.isRunning, isTrue);
        expect(client.calls, isNot(contains('appExit')));
      });
    }
  });

  group('a button queued around a stop', () {
    // One press is on the wire, a second is queued behind it, and the switch
    // lands in between. The second never goes out, because by the time it is
    // its turn the run has no key and there is no scene to press into - a
    // press that went anyway would leave the transmitter keyed with no
    // release behind it.
    test('does not go out behind one that was already in flight', () async {
      client.holdPress = Completer<void>();
      final first = service.sendPress();
      await waitFor(() => client.calls.contains('press'));
      final second = service.sendPress();

      client.report(FlipperConnectionEvent.deviceChanged);
      await waitFor(() => !service.isRunning);
      client.holdPress!.complete();
      await Future.wait([first, second]);

      expect(
        client.calls.where((c) => c == 'press'),
        hasLength(1),
        reason: 'the one already on the wire, and no more',
      );
    });

    test('does not press once the run has closed', () async {
      client.report(FlipperConnectionEvent.deviceChanged);
      await waitFor(() => !service.isRunning);
      client.calls.clear();

      await service.sendPress();

      expect(client.calls, isNot(contains('press')));
    });

    test('presses while the run is open', () async {
      await service.sendPress();

      expect(client.calls, contains('press'));
    });
  });

  // A stop that cannot reach the device still has to end: the service is
  // asked to stop because the Flipper has gone, so the exit failing is the
  // expected case rather than the exceptional one.
  test('closes even when the exit itself fails', () async {
    client.exitThrows = StateError('link is gone');

    client.report(FlipperConnectionEvent.deviceChanged);
    await waitFor(() => service.activeKey == null);

    expect(service.isRunning, isFalse);
    expect(service.activeKey, isNull);
  });
}
