import 'dart:async';
import 'dart:typed_data';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/remote/cli/page.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:xterm/xterm.dart';

class _FakeDiscovered implements DiscoveredDevice {
  _FakeDiscovered(this.transport);
  @override
  String get id => 'fake';
  @override
  String get name => 'Flipper';
  @override
  final DeviceTransport transport;
}

FlipperDevice _device(FlipperLink link) => FlipperDevice(
  id: 'fake',
  name: 'Flipper',
  link: link,
  source: _FakeDiscovered(
    link == FlipperLink.ble ? DeviceTransport.ble : DeviceTransport.usb,
  ),
);

/// How the CLI write fails. Both are real and they behave differently:
/// resolving a session that is gone throws before any future exists, while the
/// session's own write is async and rejects. They are one field rather than
/// two booleans so "both at once", which cannot happen, cannot be written.
enum _WriteFailure {
  none,
  throwsSynchronously,
  rejects,

  /// An error whose text carries an escape sequence, as a driver or OS
  /// message can. Here a clear-screen, so a notice that passed it through
  /// would visibly wipe the scrollback.
  escapeInMessage,
}

class _FakeClient implements FlipperClient {
  _FakeClient({this.link = FlipperLink.ble}) {
    _current = _device(link);
  }

  final FlipperLink link;
  final text = StreamController<String>.broadcast();
  final connection = StreamController<FlipperConnectionState>.broadcast();

  _WriteFailure writeFailure = _WriteFailure.none;
  bool enterRpcModeRejects = false;

  /// Holds a write open, so a test can see what happens while one is still in
  /// flight. Desktop USB waits on a completer with no timeout of its own, so
  /// "never finishes" is a real state, not a contrived one.
  Completer<void>? heldWrite;

  int writeCalls = 0;
  int enterRpcModeCalls = 0;

  /// What dispose did, in order. cliExclusive has to be cleared before the
  /// RPC switch — switchToRpcMode refuses outright while it is set — and a
  /// fake that only counted calls could not tell.
  final List<String> events = [];

  /// Lets a test count what the terminal drew, where `contains` cannot tell
  /// one notice from fifteen.
  static int occurrences(String haystack, String needle) =>
      needle.allMatches(haystack).length;

  @override
  Stream<String> get textStream => text.stream;

  @override
  Stream<FlipperConnectionState> get connectionStream => connection.stream;

  /// One instance for the life of a session, as the real client does -
  /// FlipperSession.device is final and connectedDevice returns it, so
  /// identity is what tells one session from the next.
  FlipperDevice _current = _device(FlipperLink.usb);

  @override
  FlipperDevice? get connectedDevice => _current;

  /// Stands in for a reconnect: connect() builds a fresh session carrying a
  /// fresh device.
  void startNewSession() => _current = _device(link);

  @override
  set cliExclusive(bool value) => events.add('cliExclusive=$value');

  @override
  Future<void> writeCliBytes(Uint8List bytes) {
    writeCalls += 1;
    events.add('write');
    final held = heldWrite;
    if (held != null) return held.future;
    switch (writeFailure) {
      case _WriteFailure.throwsSynchronously:
        throw StateError('No active transport');
      case _WriteFailure.rejects:
        return Future<void>.error(StateError('transport is gone'));
      case _WriteFailure.escapeInMessage:
        return Future<void>.error(
          StateError('write failed [2J[H and then some'),
        );
      case _WriteFailure.none:
        return Future<void>.value();
    }
  }

  @override
  Future<void> enterRpcMode() {
    enterRpcModeCalls += 1;
    events.add('enterRpcMode');
    return enterRpcModeRejects
        ? Future<void>.error(StateError('rpc switch failed'))
        : Future<void>.value();
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<FlipperDevice> connect(FlipperDevice device, {bool autoRpc = true}) =>
      Future<FlipperDevice>.value(device);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Everything the terminal has drawn.
///
/// Read off the rendered TerminalView rather than through a seam in the page:
/// the notices are the user-facing half of this fix, and the buffer is what
/// the user is actually looking at.
String _terminalText(WidgetTester tester) {
  final buffer = _terminalOf(tester).buffer;
  return [
    for (var i = 0; i < buffer.lines.length; i++) buffer.lines[i].toString(),
  ].join('\n');
}

Terminal _terminalOf(WidgetTester tester) =>
    tester.widget<TerminalView>(find.byType(TerminalView)).terminal;

/// Whether the page still believes it has a session. `_ready` is private, and
/// this is what it actually controls that a user can see.
bool _acceptsInput(WidgetTester tester) =>
    tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byIcon(Icons.stop_circle_outlined),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed !=
    null;

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: child,
);

/// Collects what LogService writes, so a test can assert the handler ran
/// rather than only that nothing blew up. Restored inline rather than through
/// addTearDown, which flutter_test rejects as changing a debug variable.
Future<List<String>> recordingLogs(Future<void> Function() body) async {
  final lines = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  try {
    await body();
  } finally {
    debugPrint = previous;
  }
  return lines;
}

void main() {
  /// Opens the page, lets the device say [lastOutput], then disposes it.
  ///
  /// An unhandled rejection during dispose fails the test outright, which is
  /// most of what these assert. That is a side channel though, so the two
  /// teardown cases also read the log back: an assertion that says what it
  /// wants cannot quietly become vacuous.
  Future<void> openThenDispose(
    WidgetTester tester,
    _FakeClient client, {
    String lastOutput = 'doing something long',
  }) async {
    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump();

    client.text.add(lastOutput);
    await tester.pump();

    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('a ctrl-c refused before it is sent does not escape teardown', (
    tester,
  ) async {
    final client = _FakeClient()
      ..writeFailure = _WriteFailure.throwsSynchronously;
    addTearDown(client.text.close);

    final logs = await recordingLogs(() => openThenDispose(tester, client));

    expect(client.writeCalls, 1);
    expect(
      logs.where((l) => l.contains('ctrl-c on dispose failed')),
      isNotEmpty,
      reason: 'the handler ran, rather than the failure merely not surfacing',
    );
  });

  // The case the old handler could not see. dispose() is not async, so its
  // catch only ever covered the synchronous prologue — and this is the failure
  // teardown actually produces, because the transport is usually torn down
  // before the page is.
  testWidgets('a ctrl-c the transport rejects does not escape teardown', (
    tester,
  ) async {
    final client = _FakeClient()..writeFailure = _WriteFailure.rejects;
    addTearDown(client.text.close);

    final logs = await recordingLogs(() => openThenDispose(tester, client));

    expect(client.writeCalls, 1);
    expect(
      logs.where((l) => l.contains('ctrl-c on dispose failed')),
      isNotEmpty,
    );
  });

  testWidgets('no ctrl-c is sent when the prompt is already back', (
    tester,
  ) async {
    final client = _FakeClient()..writeFailure = _WriteFailure.rejects;
    addTearDown(client.text.close);

    await openThenDispose(tester, client, lastOutput: 'done >: ');

    expect(client.writeCalls, 0);
  });

  // The other half of the fix, which the tests above cannot reach: dispose
  // only returns to RPC mode for a non-BLE device.
  testWidgets('a failed return to RPC mode does not escape teardown', (
    tester,
  ) async {
    final client = _FakeClient(link: FlipperLink.usb)
      ..enterRpcModeRejects = true;
    addTearDown(client.text.close);

    await tester.pumpWidget(_wrap(CliPage(client: client)));
    // Long enough for _enterCliReady's own delay to elapse, so no timer is
    // left pending when the page goes away.
    await tester.pump(const Duration(milliseconds: 600));

    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(client.enterRpcModeCalls, 1);
  });

  testWidgets('a BLE device is left alone rather than pushed back to RPC', (
    tester,
  ) async {
    final client = _FakeClient();
    addTearDown(client.text.close);

    await openThenDispose(tester, client);

    expect(client.enterRpcModeCalls, 0);
  });

  // The ordering dispose() documents as load-bearing: switchToRpcMode returns
  // an error while cliExclusive is still set, so clearing it has to come
  // first. Counting calls could not see this; deleting the assignment
  // altogether left every other test green.
  testWidgets('cli mode is released before the switch back to RPC', (
    tester,
  ) async {
    final client = _FakeClient(link: FlipperLink.usb);
    addTearDown(client.text.close);

    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(client.events, contains('cliExclusive=false'));
    expect(
      client.events.indexOf('cliExclusive=false'),
      lessThan(client.events.indexOf('enterRpcMode')),
    );
  });

  // _sendCtrlC is one of the two sites that carried the mirror-image bug -
  // a handler for the rejection and nothing for the synchronous throw, which
  // would leave it escaping the button's callback.
  testWidgets('the ctrl-c button survives a session that is already gone', (
    tester,
  ) async {
    final client = _FakeClient(link: FlipperLink.usb);
    addTearDown(client.text.close);

    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));

    client.writeFailure = _WriteFailure.throwsSynchronously;
    final before = client.writeCalls;
    final logs = await recordingLogs(() async {
      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await tester.pump();
    });

    expect(client.writeCalls, before + 1, reason: 'the button is live');
    expect(logs.where((l) => l.contains('ctrl-c failed')), isNotEmpty);
  });
  // #80. A keystroke that never reached the device drew nothing at all, and
  // LogService.enabled is bool.fromEnvironment('QLOG', kDebugMode) - so in a
  // release build the only evidence was gone too. What the user saw was a
  // terminal that had stopped echoing, which reads as a Flipper that has hung.
  testWidgets('a keystroke that cannot be delivered says so in the terminal', (
    tester,
  ) async {
    final client = _FakeClient(link: FlipperLink.usb);
    addTearDown(client.text.close);
    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));

    client.writeFailure = _WriteFailure.rejects;
    await recordingLogs(() async {
      _terminalOf(tester).textInput('ls');
      await tester.pump();
    });

    expect(_terminalText(tester), contains('not sent'));
  });

  // The same failure, from the synchronous side: resolving a session that is
  // gone throws before there is a future to attach a handler to.
  testWidgets('a keystroke refused before it is sent says so too', (
    tester,
  ) async {
    final client = _FakeClient(link: FlipperLink.usb);
    addTearDown(client.text.close);
    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));

    client.writeFailure = _WriteFailure.throwsSynchronously;
    await recordingLogs(() async {
      _terminalOf(tester).textInput('ls');
      await tester.pump();
    });

    expect(_terminalText(tester), contains('not sent'));
  });

  // A failed write does not mean the session is gone. Android USB fails one
  // write on a PlatformException without raising a transport fault, so the
  // transport stays usable - and a page that shut itself down on the first
  // failure would be dead for good, with nothing on screen saying how to
  // revive it. A session that has really gone raises a disconnect instead.
  testWidgets('a failed write leaves a still-live page usable', (tester) async {
    final client = _FakeClient(link: FlipperLink.usb);
    addTearDown(client.text.close);
    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));

    client.writeFailure = _WriteFailure.rejects;
    await recordingLogs(() async {
      _terminalOf(tester).textInput('ls');
      await tester.pump();
    });

    expect(_acceptsInput(tester), isTrue);
    client.writeFailure = _WriteFailure.none;
    final before = client.writeCalls;
    _terminalOf(tester).textInput('ls');
    await tester.pump();
    expect(client.writeCalls, before + 1, reason: 'and still delivering');
  });

  // Clearing _ready would have stopped new keystrokes but not the writes
  // already in flight, and on Android a write can sit for ten seconds before
  // it rejects - so a burst all fails at once, each one drawing a line.
  testWidgets('a burst of failed writes draws one line, not one each', (
    tester,
  ) async {
    final client = _FakeClient(link: FlipperLink.usb);
    addTearDown(client.text.close);
    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));

    client.writeFailure = _WriteFailure.rejects;
    await recordingLogs(() async {
      final terminal = _terminalOf(tester);
      terminal.textInput('l');
      terminal.textInput('s');
      terminal.textInput('\r');
      await tester.pump();
    });

    expect(_FakeClient.occurrences(_terminalText(tester), 'not sent'), 1);
  });

  testWidgets('the device answering makes the next failure news again', (
    tester,
  ) async {
    final client = _FakeClient(link: FlipperLink.usb);
    addTearDown(client.text.close);
    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));

    await recordingLogs(() async {
      client.writeFailure = _WriteFailure.rejects;
      _terminalOf(tester).textInput('ls');
      await tester.pump();

      client.text.add('the link is fine');
      await tester.pump();

      _terminalOf(tester).textInput('ls');
      await tester.pump();
    });

    expect(_FakeClient.occurrences(_terminalText(tester), 'not sent'), 2);
  });

  // Exception text carries driver and OS strings. An escape byte in one would
  // otherwise be handed straight to the emulator - here, a clear-screen that
  // would wipe the output the notice is meant to sit beside.
  testWidgets('an error carrying escape codes cannot drive the terminal', (
    tester,
  ) async {
    final client = _FakeClient(link: FlipperLink.usb);
    addTearDown(client.text.close);
    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));
    client.text.add('output worth keeping');
    await tester.pump();

    client.writeFailure = _WriteFailure.escapeInMessage;
    await recordingLogs(() async {
      _terminalOf(tester).textInput('ls');
      await tester.pump();
    });

    expect(_terminalText(tester), contains('output worth keeping'));
  });

  // _enterCliReady set _ready before sending the nudge, so a nudge that failed
  // left a black terminal taking every keystroke and posting it into a session
  // that had never been opened.
  testWidgets('the page does not claim ready when the nudge fails', (
    tester,
  ) async {
    final client = _FakeClient(link: FlipperLink.usb)
      ..writeFailure = _WriteFailure.rejects;
    addTearDown(client.text.close);

    await recordingLogs(() async {
      await tester.pumpWidget(_wrap(CliPage(client: client)));
      await tester.pump(const Duration(milliseconds: 600));
    });

    expect(_acceptsInput(tester), isFalse);
    expect(_terminalText(tester), contains('could not open'));
  });

  testWidgets('the terminal says when the device goes away', (tester) async {
    final client = _FakeClient(link: FlipperLink.usb);
    addTearDown(client.text.close);
    addTearDown(client.connection.close);
    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));

    client.connection.add(
      const FlipperConnectionState(
        mode: FlipperMode.cli,
        device: null,
        connected: false,
      ),
    );
    await tester.pump();

    expect(_terminalText(tester), contains('disconnected'));
    expect(_acceptsInput(tester), isFalse);
  });

  // The teardown race. _doSwitchToRpcMode flips mode partway through, so an
  // interrupt still in flight either died on "Cannot send CLI bytes while in
  // RPC mode" - logged as though the cable had been pulled - or landed as a
  // stray 0x03 inside an RPC stream. Counting calls cannot see it; holding the
  // write open can.
  testWidgets('the interrupt finishes before the switch back to RPC', (
    tester,
  ) async {
    final client = _FakeClient(link: FlipperLink.usb);
    addTearDown(client.text.close);
    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));
    client.text.add('doing something long');
    await tester.pump();

    final held = Completer<void>();
    client.heldWrite = held;
    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    await tester.pump();

    expect(client.writeCalls, greaterThan(0), reason: 'the interrupt went');
    expect(
      client.enterRpcModeCalls,
      0,
      reason: 'and the switch is waiting on it',
    );

    held.complete();
    await tester.pump();

    expect(client.enterRpcModeCalls, 1);
  });

  // Sequencing them is only safe because the wait is bounded. Desktop USB
  // hands the write to an isolate and waits on a completer with no timeout of
  // its own, so a wedged port must not hold the RPC restore open for the life
  // of the process.
  testWidgets('a write that never finishes does not strand the RPC restore', (
    tester,
  ) async {
    final client = _FakeClient(link: FlipperLink.usb);
    addTearDown(client.text.close);
    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));
    client.text.add('doing something long');
    await tester.pump();

    client.heldWrite = Completer<void>();
    await recordingLogs(() async {
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await tester.pump();
      expect(client.enterRpcModeCalls, 0);
      await tester.pump(const Duration(seconds: 3));
    });

    expect(client.enterRpcModeCalls, 1);
  });

  // The nudge is a second suspension point, and the page can be backed out of
  // while it is in flight. Without a mounted recheck the setState after it
  // throws "called after dispose()", which unwinds into _bootstrap's catch and
  // is reported there as a bootstrap failure - the exact misattribution the
  // stack trace was added to prevent.
  testWidgets('backing out while the nudge is in flight is not an error', (
    tester,
  ) async {
    final client = _FakeClient(link: FlipperLink.usb);
    addTearDown(client.text.close);
    final held = Completer<void>();
    client.heldWrite = held;

    final logs = await recordingLogs(() async {
      await tester.pumpWidget(_wrap(CliPage(client: client)));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await tester.pump();

      held.complete();
      await tester.pump();
    });

    expect(logs.where((l) => l.contains('bootstrap failed')), isEmpty);
    expect(logs.where((l) => l.contains('setState')), isEmpty);
  });

  // Chaining the switch behind the interrupt put up to two seconds between
  // dispose and the switch, and cliExclusive is re-read from whatever session
  // is active - so a CLI page opened in the meantime would be switched to RPC
  // mode under itself, and its own nudge would then fail.
  testWidgets('a teardown that outlives its session leaves the next alone', (
    tester,
  ) async {
    final client = _FakeClient(link: FlipperLink.usb);
    addTearDown(client.text.close);
    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));
    client.text.add('doing something long');
    await tester.pump();

    client.heldWrite = Completer<void>();
    await recordingLogs(() async {
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await tester.pump();
      // A new page connects while the old interrupt is still outstanding.
      client.startNewSession();
      await tester.pump(const Duration(seconds: 3));
    });

    expect(client.enterRpcModeCalls, 0);
  });
}
