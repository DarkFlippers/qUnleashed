import 'dart:async';
import 'dart:typed_data';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/remote/cli/page.dart';
import 'package:qunleashed/services/logging.dart';
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
  _FakeClient() {
    _current = _device(FlipperLink.usb);
  }

  final text = StreamController<String>.broadcast();
  final connection = StreamController<FlipperConnectionState>.broadcast();

  _WriteFailure writeFailure = _WriteFailure.none;
  bool closeRejects = false;

  /// Holds a write open, so a test can see what happens while one is still in
  /// flight. Desktop USB waits on a completer with no timeout of its own, so
  /// "never finishes" is a real state, not a contrived one.
  Completer<void>? heldWrite;

  int writeCalls = 0;

  /// Every channel the page opened, in order. A channel is bound to the session
  /// it was opened on, so which one was closed is what tells one page's
  /// teardown from the next page's session.
  final List<_FakeChannel> channels = [];

  int get closeCalls => channels.fold(0, (sum, c) => sum + c.closeCalls);

  /// Lets a test count what the terminal drew, where `contains` cannot tell
  /// one notice from fifteen.
  static int occurrences(String haystack, String needle) =>
      needle.allMatches(haystack).length;

  late FlipperDevice _current;

  @override
  FlipperDevice? get connectedDevice => _current;

  /// Stands in for a reconnect: the next openCli lands on a fresh session
  /// carrying a fresh device.
  void startNewSession() => _current = _device(FlipperLink.usb);

  @override
  Future<FlipperCliChannel> openCli(FlipperDevice device) {
    final channel = _FakeChannel(this, device);
    channels.add(channel);
    return Future<FlipperCliChannel>.value(channel);
  }

  Future<void> _write() {
    writeCalls += 1;
    final held = heldWrite;
    if (held != null) return held.future;
    switch (writeFailure) {
      case _WriteFailure.throwsSynchronously:
        throw StateError('No active transport');
      case _WriteFailure.rejects:
        return Future<void>.error(StateError('transport is gone'));
      case _WriteFailure.escapeInMessage:
        return Future<void>.error(
          StateError('write failed \x1b[2J\x1b[H and then some'),
        );
      case _WriteFailure.none:
        return Future<void>.value();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChannel implements FlipperCliChannel {
  _FakeChannel(this._client, this.device);

  final _FakeClient _client;

  @override
  final FlipperDevice device;

  int closeCalls = 0;

  @override
  Stream<String> get text => _client.text.stream;

  @override
  Stream<FlipperConnectionState> get connection => _client.connection.stream;

  @override
  Future<void> write(Uint8List bytes) => _client._write();

  @override
  Future<void> close({bool backToRpc = true}) {
    closeCalls += 1;
    return _client.closeRejects
        ? Future<void>.error(StateError('rpc switch failed'))
        : Future<void>.value();
  }

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

/// Silences the console for [body] and hands back what it would have printed.
///
/// Restored inline rather than through addTearDown, which flutter_test rejects
/// as changing a debug variable.
///
/// For asserting a failure *was* recorded, read LogService.history instead:
/// what prints follows the build, so these assertions failed outright under
/// --dart-define=QLOG=false, and they could not tell a handler logging at info
/// - which a release build compiles away - from one logging at error. The
/// history is the surface the log screen reads and the one a bug report
/// carries. What is left here is asserting a line is *absent*, where printing
/// is the wider net of the two.
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
    // Past _enterCliReady's own delay, so no timer is left pending.
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('a ctrl-c refused before it is sent does not escape teardown', (
    tester,
  ) async {
    final client = _FakeClient()
      ..writeFailure = _WriteFailure.throwsSynchronously;
    addTearDown(client.text.close);

    LogService.clearHistory();
    await recordingLogs(() => openThenDispose(tester, client));

    expect(client.writeCalls, 1);
    expect(
      LogService.history.where((l) => l.contains('ctrl-c on dispose failed')),
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

    LogService.clearHistory();
    await recordingLogs(() => openThenDispose(tester, client));

    expect(client.writeCalls, 1);
    expect(
      LogService.history.where((l) => l.contains('ctrl-c on dispose failed')),
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

  // The other half of teardown: handing the session back to RPC can fail
  // too, and dispose has nowhere to report it but the log.
  testWidgets('a failed return to RPC mode does not escape teardown', (
    tester,
  ) async {
    final client = _FakeClient()..closeRejects = true;
    addTearDown(client.text.close);

    await tester.pumpWidget(_wrap(CliPage(client: client)));
    // Long enough for _enterCliReady's own delay to elapse, so no timer is
    // left pending when the page goes away.
    await tester.pump(const Duration(milliseconds: 600));

    LogService.clearHistory();
    await recordingLogs(() async {
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 50));
    });

    expect(client.closeCalls, 1);
    expect(
      LogService.history.where((l) => l.contains('leaving cli mode failed')),
      isNotEmpty,
    );
  });

  // _sendCtrlC is one of the two sites that carried the mirror-image bug -
  // a handler for the rejection and nothing for the synchronous throw, which
  // would leave it escaping the button's callback.
  testWidgets('the ctrl-c button survives a session that is already gone', (
    tester,
  ) async {
    final client = _FakeClient();
    addTearDown(client.text.close);

    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));

    client.writeFailure = _WriteFailure.throwsSynchronously;
    final before = client.writeCalls;
    LogService.clearHistory();
    await recordingLogs(() async {
      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await tester.pump();
    });

    expect(client.writeCalls, before + 1, reason: 'the button is live');
    expect(
      LogService.history.where((l) => l.contains('ctrl-c failed')),
      isNotEmpty,
    );
  });
  // #80. A keystroke that never reached the device drew nothing at all, and
  // the only other evidence was a log line - since #89 kept in a buffer, but
  // not something anyone reads while typing. What the user saw was a terminal
  // that had stopped echoing, which reads as a Flipper that has hung.
  testWidgets('a keystroke that cannot be delivered says so in the terminal', (
    tester,
  ) async {
    final client = _FakeClient();
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
    final client = _FakeClient();
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
    final client = _FakeClient();
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
    final client = _FakeClient();
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
    final client = _FakeClient();
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
    final client = _FakeClient();
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
    final client = _FakeClient()..writeFailure = _WriteFailure.rejects;
    addTearDown(client.text.close);

    await recordingLogs(() async {
      await tester.pumpWidget(_wrap(CliPage(client: client)));
      await tester.pump(const Duration(milliseconds: 600));
    });

    expect(_acceptsInput(tester), isFalse);
    expect(_terminalText(tester), contains('could not open'));
  });

  testWidgets('the terminal says when the device goes away', (tester) async {
    final client = _FakeClient();
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
    final client = _FakeClient();
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
    expect(client.closeCalls, 0, reason: 'and the close is waiting on it');

    held.complete();
    await tester.pump();

    expect(client.closeCalls, 1);
  });

  // Sequencing them is only safe because the wait is bounded. Desktop USB
  // hands the write to an isolate and waits on a completer with no timeout of
  // its own, so a wedged port must not hold the RPC restore open for the life
  // of the process.
  testWidgets('a write that never finishes does not strand the RPC restore', (
    tester,
  ) async {
    final client = _FakeClient();
    addTearDown(client.text.close);
    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));
    client.text.add('doing something long');
    await tester.pump();

    client.heldWrite = Completer<void>();
    await recordingLogs(() async {
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await tester.pump();
      expect(client.closeCalls, 0);
      await tester.pump(const Duration(seconds: 3));
    });

    expect(client.closeCalls, 1);
  });

  // The nudge is a second suspension point, and the page can be backed out of
  // while it is in flight. Without a mounted recheck the setState after it
  // throws "called after dispose()", which unwinds into _bootstrap's catch and
  // is reported there as a bootstrap failure - the exact misattribution the
  // stack trace was added to prevent.
  testWidgets('backing out while the nudge is in flight is not an error', (
    tester,
  ) async {
    final client = _FakeClient();
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

  // Chaining the close behind the interrupt puts up to two seconds between
  // dispose and the close. A CLI page opened in the meantime has its own
  // channel on its own session, and the old teardown must close only the one
  // it opened - never hand the new page's session back to RPC under it.
  testWidgets('a teardown that outlives its session leaves the next alone', (
    tester,
  ) async {
    final client = _FakeClient();
    addTearDown(client.text.close);
    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump(const Duration(milliseconds: 600));
    client.text.add('doing something long');
    await tester.pump();

    client.heldWrite = Completer<void>();
    await recordingLogs(() async {
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await tester.pump();
      client
        ..heldWrite = null
        ..startNewSession();
      await tester.pumpWidget(_wrap(CliPage(client: client)));
      await tester.pump(const Duration(seconds: 3));
    });

    expect(client.channels, hasLength(2));
    expect(client.channels.first.closeCalls, 1);
    expect(client.channels.last.closeCalls, 0);
  });
}
