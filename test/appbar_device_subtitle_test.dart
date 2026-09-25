import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/appbar.dart';
import 'package:qunleashed/theme/theme.dart';

/// The device line under a page title.
///
/// Sixteen pages build a `QPageAppBar`, so what this widget decides it does
/// per page it does sixteen times. Two of those decisions are worth pinning:
/// whether it subscribes to the device at all, and what name it shows.
///
/// It had no test, and could not have one - the title built its own client
/// from `FlipperOneClient()`. It takes one now (ADR 0002), optional and
/// falling back to the global, because most of those sixteen pages are on
/// pushed routes with nothing to pass.
/// Enough of a discovered device to build a [FlipperDevice] with.
class _Discovered implements DiscoveredDevice {
  const _Discovered(this.id);

  @override
  final String id;

  @override
  String get name => id;

  @override
  DeviceTransport get transport => DeviceTransport.usb;
}

FlipperDevice device(String id, String name) => FlipperDevice(
  id: id,
  name: name,
  link: FlipperLink.usb,
  source: _Discovered(id),
);

class FakeTitleClient implements FlipperClient {
  FakeTitleClient({this.connected = false, this.name, FlipperDevice? attached})
    : _device = attached;

  final _connection = StreamController<FlipperConnectionState>.broadcast();
  final _info = StreamController<Map<String, String>>.broadcast();

  bool connected;

  /// What `getName()` answers. The hardware name arrives after the link does,
  /// on the device-info stream, so it moves.
  String? name;

  FlipperDevice? _device;

  bool get watchesLink => _connection.hasListener;
  bool get watchesInfo => _info.hasListener;

  void link({required bool connected, FlipperDevice? arriving}) {
    this.connected = connected;
    if (arriving != null) _device = arriving;
    _connection.add(
      FlipperConnectionState(
        mode: connected ? FlipperMode.rpc : FlipperMode.disconnected,
        device: arriving,
        connected: connected,
      ),
    );
  }

  /// A device-info patch, which is the only thing that moves the name.
  void reported(String hardwareName) {
    name = hardwareName;
    _info.add(const {'hardware_name': 'x'});
  }

  Future<void> close() async {
    await _info.close();
    await _connection.close();
  }

  @override
  FlipperDevice? get connectedDevice => _device;

  @override
  bool get isConnected => connected;

  @override
  String? getName() => name;

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  Stream<Map<String, String>> get deviceInfoUpdates => _info.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeTitleClient client;

  setUp(() => client = FakeTitleClient());
  tearDown(() => client.close());

  Future<void> show(
    WidgetTester tester, {
    String? subtitle,
    bool showDeviceStatus = true,
    FlipperClient? use,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
      home: Scaffold(
        appBar: QPageAppBar(
          title: 'Archive',
          client: use ?? client,
          subtitle: subtitle,
          showDeviceStatus: showDeviceStatus,
        ),
        body: const SizedBox(),
      ),
    ),
  );

  bool shows(String text) => find.text(text).evaluate().isNotEmpty;

  group('whether it watches the device at all', () {
    // The condition is load-bearing: a title that subscribed regardless would
    // put sixteen listeners on the device's streams for subtitles that never
    // render a word of it.
    testWidgets('it does when the subtitle is the device line', (tester) async {
      await show(tester);

      expect(client.watchesLink, isTrue);
      expect(client.watchesInfo, isTrue);
    });

    testWidgets('it does not when a subtitle was given instead', (
      tester,
    ) async {
      await show(tester, subtitle: '/ext/infrared');

      expect(client.watchesLink, isFalse);
      expect(client.watchesInfo, isFalse);
    });

    testWidgets('it does not when the device line is switched off', (
      tester,
    ) async {
      await show(tester, showDeviceStatus: false);

      expect(client.watchesLink, isFalse);
    });

    testWidgets('it lets go when it goes away', (tester) async {
      await show(tester);
      expect(client.watchesLink, isTrue, reason: 'the starting point');

      await tester.pumpWidget(const SizedBox());

      expect(client.watchesLink, isFalse);
      expect(client.watchesInfo, isFalse);
    });
  });

  group('the name it shows', () {
    testWidgets('is what the client already knew, before any event', (
      tester,
    ) async {
      client.name = 'Kitchen';

      await show(tester);

      expect(shows('Kitchen'), isTrue);
    });

    testWidgets('is the hardware name once one is reported', (tester) async {
      await show(tester);

      client.reported('Kitchen');
      await tester.pump();

      expect(shows('Kitchen'), isTrue);
    });

    // The Flipper's own naming is noise in a title bar 17 pixels tall.
    testWidgets('drops the maker prefix', (tester) async {
      client.name = 'Flipper Zero Kitchen';

      await show(tester);

      expect(shows('Kitchen'), isTrue);
      expect(shows('Flipper Zero Kitchen'), isFalse);
    });

    // Pinned as it behaves, not as it reads. The pattern is
    // `^Flipper(?:\s+Zero)?[\s_-]+`, and the trailing separator is required -
    // so on a device called exactly "Flipper Zero" the optional group gives up
    // its match, the separator takes the space, and what is left is "Zero".
    // Cosmetic, pre-existing, and not changed here: a test that asserted the
    // intent would be asserting something the app does not do.
    testWidgets('shows only "Zero" for a device called "Flipper Zero"', (
      tester,
    ) async {
      client.name = 'Flipper Zero';

      await show(tester);

      expect(shows('Zero'), isTrue);
    });

    testWidgets('says so when there is no device at all', (tester) async {
      await show(tester);

      expect(
        shows('Zero'),
        isFalse,
        reason: 'nothing connected is not a device with a short name',
      );
    });
  });

  // The hardware name belongs to one Flipper. Keeping it across a swap puts
  // the previous device's name under the new one's link.
  testWidgets('forgets the name when a different device arrives', (
    tester,
  ) async {
    client.name = 'Kitchen';
    await show(tester);
    expect(shows('Kitchen'), isTrue, reason: 'the starting point');

    client.name = null;
    client.link(connected: true, arriving: device('other', 'Bench'));
    await tester.pump();

    expect(shows('Kitchen'), isFalse);
    expect(shows('Bench'), isTrue);
  });

  testWidgets('follows a client handed in later', (tester) async {
    await show(tester);
    expect(client.watchesLink, isTrue, reason: 'the starting point');

    final second = FakeTitleClient(connected: true, name: 'Bench');
    addTearDown(second.close);

    await show(tester, use: second);
    await tester.pump();

    expect(client.watchesLink, isFalse, reason: 'the old one was let go');
    expect(second.watchesLink, isTrue);
    expect(shows('Bench'), isTrue);
  });
}
