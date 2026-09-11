import 'dart:async';
import 'dart:typed_data';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/remote/cli/page.dart';
import 'package:qunleashed/theme/theme.dart';

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
enum _WriteFailure { none, throwsSynchronously, rejects }

class _FakeClient implements FlipperClient {
  _FakeClient({this.link = FlipperLink.ble});

  final FlipperLink link;
  final text = StreamController<String>.broadcast();
  final connection = StreamController<FlipperConnectionState>.broadcast();

  _WriteFailure writeFailure = _WriteFailure.none;
  bool enterRpcModeRejects = false;

  int writeCalls = 0;
  int enterRpcModeCalls = 0;

  /// What dispose did, in order. cliExclusive has to be cleared before the
  /// RPC switch — switchToRpcMode refuses outright while it is set — and a
  /// fake that only counted calls could not tell.
  final List<String> events = [];

  @override
  Stream<String> get textStream => text.stream;

  @override
  Stream<FlipperConnectionState> get connectionStream => connection.stream;

  @override
  FlipperDevice? get connectedDevice => _device(link);

  @override
  set cliExclusive(bool value) => events.add('cliExclusive=$value');

  @override
  Future<void> writeCliBytes(Uint8List bytes) {
    writeCalls += 1;
    events.add('write');
    switch (writeFailure) {
      case _WriteFailure.throwsSynchronously:
        throw StateError('No active transport');
      case _WriteFailure.rejects:
        return Future<void>.error(StateError('transport is gone'));
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
}
