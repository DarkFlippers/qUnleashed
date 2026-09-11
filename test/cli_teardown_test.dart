import 'dart:async';
import 'dart:typed_data';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/remote/cli/page.dart';
import 'package:qunleashed/theme/theme.dart';

class _FakeDiscovered implements DiscoveredDevice {
  @override
  String get id => 'fake';
  @override
  String get name => 'Flipper';
  @override
  DeviceTransport get transport => DeviceTransport.ble;
}

/// A BLE device, so `_bootstrap` takes its early exit rather than trying to
/// open a USB session the fake cannot provide.
final _device = FlipperDevice(
  id: 'fake',
  name: 'Flipper',
  link: FlipperLink.ble,
  source: _FakeDiscovered(),
);

class _FakeClient implements FlipperClient {
  final text = StreamController<String>.broadcast();
  final connection = StreamController<FlipperConnectionState>.broadcast();

  /// How the write fails. Both are real: resolving the session throws
  /// synchronously when there is no transport, while the session's own write
  /// is async and rejects instead.
  bool throwsSynchronously = false;
  bool rejects = false;

  int writeCalls = 0;

  @override
  Stream<String> get textStream => text.stream;

  @override
  Stream<FlipperConnectionState> get connectionStream => connection.stream;

  @override
  FlipperDevice? get connectedDevice => _device;

  @override
  set cliExclusive(bool value) {}

  @override
  Future<void> writeCliBytes(Uint8List bytes) {
    writeCalls += 1;
    if (throwsSynchronously) throw StateError('No active transport');
    if (rejects) return Future<void>.error(StateError('transport is gone'));
    return Future<void>.value();
  }

  @override
  Future<void> enterRpcMode() => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: child,
);

void main() {
  /// Opens the page, leaves it mid-command so teardown sends Ctrl-C, then
  /// disposes it. A failure that escapes here fails the test on its own —
  /// flutter_test reports an unhandled async error against whatever is
  /// running — which is exactly the symptom being fixed.
  Future<_FakeClient> tearDownMidCommand(
    WidgetTester tester, {
    bool throwsSynchronously = false,
    bool rejects = false,
  }) async {
    final client = _FakeClient()
      ..throwsSynchronously = throwsSynchronously
      ..rejects = rejects;

    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump();

    // Output without the prompt means a command is still running, which is
    // what arms the interrupt on teardown.
    client.text.add('doing something long');
    await tester.pump();

    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 50));
    return client;
  }

  testWidgets('a ctrl-c that is refused outright does not escape teardown', (
    tester,
  ) async {
    final client = await tearDownMidCommand(tester, throwsSynchronously: true);

    expect(client.writeCalls, 1);
  });

  // The one the old handler could not see: dispose() is not async, so its
  // catch only ever ran over the synchronous prologue, and a rejected write —
  // the common case, since the link is usually already gone by teardown — had
  // nothing listening.
  testWidgets('a ctrl-c the transport rejects does not escape teardown', (
    tester,
  ) async {
    final client = await tearDownMidCommand(tester, rejects: true);

    expect(client.writeCalls, 1);
  });

  testWidgets('no ctrl-c is sent when the prompt is already back', (
    tester,
  ) async {
    final client = _FakeClient()..rejects = true;

    await tester.pumpWidget(_wrap(CliPage(client: client)));
    await tester.pump();
    client.text.add('done >: ');
    await tester.pump();

    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(client.writeCalls, 0);
  });
}
