import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/paint/virtual_display_session.dart';

import 'kept_lines.dart';

/// The virtual display Pixel Draw puts up on the Flipper.
///
/// Two pages share one session — the manager and the editor — so it is
/// ref-counted, and a display is state left *switched on inside a Flipper*:
/// getting this wrong leaves a device lit with a picture nobody is driving.
///
/// None of it could be tested until dart-flipperlib#7. The session reads
/// `client.deviceToken`, which is not nullable and whose type had only a
/// private constructor, so a fake client could not answer the getter at all —
/// which blocked the ref-counting and the restart as much as the switch.
///
/// One thing here has no case. `enter` only calls `_ensureStarted` for the
/// first holder, but calling it for every holder changes nothing a fake can
/// see: `_ensureStarted` turns itself back when the display is already up.
/// What the count actually guards is the `DeviceInfoWatchService` freeze
/// beside it - a singleton with its own paired state, which this fake does not
/// reach. Said here rather than left to a case named for the count, which
/// would be a case passing on a mechanism other than the one it claims.
class _Discovered implements DiscoveredDevice {
  const _Discovered(this.id);

  @override
  final String id;

  @override
  String get name => id;

  @override
  DeviceTransport get transport => DeviceTransport.usb;
}

final _device = FlipperDevice(
  id: 'A',
  name: 'A',
  link: FlipperLink.usb,
  source: const _Discovered('A'),
);

class FakeDisplayClient implements FlipperClient {
  final _connection = StreamController<FlipperConnectionState>.broadcast();

  bool connected = true;

  /// What `deviceToken` hands back.
  ///
  /// The session takes one token when it puts the display up and holds it, so
  /// a token that is stale from the start is exactly what a switch looks like
  /// from in there - the flag cannot be flipped afterwards, because the token
  /// it is holding was already made.
  bool tokenIsCurrent = true;

  /// Every virtual-display call, in order.
  final calls = <String>[];

  /// Raised by the next start, once. The firmware answers this when a display
  /// from a previous run is still up.
  bool startSaysAlreadyUp = false;

  /// Raised by every start, so the reclaim can be made to fail as well.
  bool startAlwaysFails = false;

  Future<void> close() => _connection.close();

  /// A link event. `connected` false is a drop; true with [tokenIsCurrent]
  /// already false is another Flipper taking over.
  void report({required bool connected}) {
    this.connected = connected;
    _connection.add(
      FlipperConnectionState(
        mode: connected ? FlipperMode.rpc : FlipperMode.disconnected,
        device: null,
        connected: connected,
      ),
    );
  }

  @override
  bool get isConnected => connected;

  @override
  DeviceToken get deviceToken => DeviceToken.fixed(current: tokenIsCurrent);

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  /// A binding that names the device, so the stop the session sends through
  /// it is not skipped as one to a link that has gone.
  @override
  FlipperSessionBinding bindCurrentSession() => connected
      ? FlipperSessionBinding.to(_device)
      : const FlipperSessionBinding.unbound();

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
    if (request.hasGuiStartVirtualDisplayRequest()) {
      calls.add('start');
      if (startSaysAlreadyUp) {
        startSaysAlreadyUp = false;
        throw FlipperRpcVirtualDisplayAlreadyStartedException(Main());
      }
      if (startAlwaysFails) throw StateError('the link went away');
      return const [];
    }
    if (request.hasGuiStopVirtualDisplayRequest()) {
      calls.add('stop');
      return const [];
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(recordKeptLines);

  late FakeDisplayClient client;
  late VirtualDisplaySession display;

  late int logBase;

  setUp(() {
    client = FakeDisplayClient();
    display = VirtualDisplaySession.forTest(client);
    clearKeptLines();
    logBase = keptLines.length;
  });
  tearDown(() => client.close());

  /// Polls until [ready], or gives up after two seconds.
  Future<void> waitFor(bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!ready() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  bool said(String fragment) =>
      keptLines.skip(logBase).any((l) => l.contains(fragment));

  group('two pages sharing one display', () {
    test('puts it up for the first holder', () async {
      display.enter();
      await waitFor(() => display.isActive);

      expect(client.calls, ['start']);
    });

    // The manager and the editor are both open when the user taps through
    // from one to the other. A second start would restart a display that is
    // already showing what they drew.
    //
    // What turns the second one back is `_ensureStarted`'s own `_active`
    // check, not the holder count - see the note at the top about what the
    // count is really for.
    test('does not restart it for the second', () async {
      display.enter();
      await waitFor(() => display.isActive);
      display.enter();
      await settle();

      expect(client.calls, ['start']);
    });

    test('leaves it up while anyone still holds it', () async {
      display.enter();
      display.enter();
      await waitFor(() => display.isActive);

      display.leave();
      await settle();

      expect(client.calls, isNot(contains('stop')));
      expect(display.isActive, isTrue);
    });

    test('takes it down when the last one goes', () async {
      display.enter();
      display.enter();
      await waitFor(() => display.isActive);

      display.leave();
      display.leave();
      await waitFor(() => !display.isActive);

      expect(client.calls, ['start', 'stop']);
    });

    // A leave with nobody holding would otherwise drive the count below zero,
    // and the next enter would not be the first one any more.
    test('a leave nobody matched does not owe an enter', () async {
      display.leave();
      await settle();

      display.enter();
      await waitFor(() => display.isActive);

      expect(client.calls, contains('start'));
    });

    // Found by the case above, and left as it is: a stray leave sends a stop
    // for a display that was never up. It is one RPC to a Flipper that is not
    // showing anything, which is harmless, and guarding it would mean another
    // flag to keep in step with the count.
    test('a leave nobody matched still sends a stop', () async {
      display.leave();
      await settle();

      expect(client.calls, ['stop']);
    });
  });

  // The firmware refuses a second start while one is up, which is what a
  // display left on by a previous run looks like. Taking it down and putting
  // it back is the only way to own it.
  test('reclaims a display left on from before', () async {
    client.startSaysAlreadyUp = true;

    display.enter();
    await waitFor(() => display.isActive);

    expect(client.calls, ['start', 'stop', 'start']);
  });

  group('a display that will not come up', () {
    // The screen is open and the Flipper stays blank. There is no failed
    // state to put this in, so the log is the only place it can go.
    test('says why the start failed', () async {
      client.startAlwaysFails = true;

      display.enter();
      await waitFor(() => client.calls.isNotEmpty);
      await settle();

      expect(said('could not start the display'), isTrue);
      expect(display.isActive, isFalse);
    });

    // The reclaim is the recovery from a display left on by a previous run.
    // Failing it leaves the old picture up and the new one never arrives.
    test('says why the reclaim failed', () async {
      client
        ..startSaysAlreadyUp = true
        ..startAlwaysFails = true;

      display.enter();
      await waitFor(() => client.calls.length >= 3);
      await settle();

      expect(said('could not reclaim the display'), isTrue);
    });

    test('says nothing when it comes up', () async {
      display.enter();
      await waitFor(() => display.isActive);

      expect(said('[VirtualDisplay]'), isFalse);
    });
  });

  test('does not put one up with nothing connected', () async {
    client.connected = false;

    display.enter();
    await settle();

    expect(client.calls, isEmpty);
    expect(display.isActive, isFalse);
  });

  group('the Flipper changing under it', () {
    // The display follows the user. It is switched off on the one that still
    // has it - by the held session, which is the only thing that still knows
    // which that was - and put up on the new one. Carrying on would drive the
    // new Flipper's display while leaving the old one lit with a picture
    // nobody updates.
    test('moves the display to the new one', () async {
      client.tokenIsCurrent = false;
      display.enter();
      await waitFor(() => display.isActive);
      client.calls.clear();

      client.report(connected: true);
      await waitFor(() => client.calls.length >= 2);

      expect(client.calls, ['stop', 'start']);
      expect(display.isActive, isTrue);
    });

    test('does not put it back when nobody is holding it', () async {
      client.tokenIsCurrent = false;
      display.enter();
      await waitFor(() => display.isActive);
      display.leave();
      await waitFor(() => !display.isActive);
      client.calls.clear();

      client.report(connected: true);
      await settle();

      expect(client.calls, isNot(contains('start')));
    });

    // The same Flipper coming back is not this. Restarting the display it is
    // already showing would blank the user's canvas for a frame.
    test('leaves it alone when it is the same Flipper', () async {
      display.enter();
      await waitFor(() => display.isActive);
      client.calls.clear();

      client.report(connected: true);
      await settle();

      expect(client.calls, isEmpty);
    });

    // The link dropping is not a switch either, and there is nothing to send
    // a stop over - but the display is no longer up, so the next event has to
    // find it inactive or it will never be restarted.
    test('marks it down when the link goes', () async {
      display.enter();
      await waitFor(() => display.isActive);

      client.report(connected: false);
      await settle();

      expect(display.isActive, isFalse);
    });

    test('puts it back when the link returns', () async {
      display.enter();
      await waitFor(() => display.isActive);
      client.report(connected: false);
      await settle();
      client.calls.clear();

      client.report(connected: true);
      await waitFor(() => display.isActive);

      expect(client.calls, ['start']);
    });
  });

  group('freeing the link for a transfer', () {
    test('takes the display down without dropping the holders', () async {
      display.enter();
      await waitFor(() => display.isActive);

      await display.suspend();

      expect(client.calls, ['start', 'stop']);
      expect(display.isActive, isFalse);
    });

    test('puts it back for whoever still holds it', () async {
      display.enter();
      await waitFor(() => display.isActive);
      await display.suspend();

      display.resume();
      await waitFor(() => display.isActive);

      expect(client.calls, ['start', 'stop', 'start']);
    });

    // Suspended means pinned off: a holder arriving mid-transfer must not put
    // the display back up while the link is being used for something else.
    test('stays down while a new holder arrives', () async {
      await display.suspend();
      client.calls.clear();

      display.enter();
      await settle();

      expect(client.calls, isEmpty);
      expect(display.isActive, isFalse);
    });

    test('puts nothing back when everyone has gone', () async {
      display.enter();
      await waitFor(() => display.isActive);
      await display.suspend();
      display.leave();
      client.calls.clear();

      display.resume();
      await settle();

      expect(client.calls, isEmpty);
    });
  });
}
