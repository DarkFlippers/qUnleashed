import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/progress_button.dart';
import 'package:qunleashed/pages/tools/infrared/widgets/ir_file_viewer.dart';
import 'package:qunleashed/theme/theme.dart';

import 'quiet_device_title.dart';

/// Whether the send button does anything, which is the one thing this screen
/// decides for itself.
///
/// Everything else on it is handed down - the file, its text, the error, the
/// send handler. The link is not: the viewer watches the client for as long as
/// the file is on screen, because a Flipper can go away while someone is
/// reading a remote and the send would then fail halfway through a transfer
/// rather than not start.
///
/// It could not be tested before. The viewer built its own client from
/// `FlipperOneClient()`; it takes one as a parameter now (ADR 0002), and both
/// builders already had one to give it.
class FakeLinkClient with QuietDeviceTitle implements FlipperClient {
  FakeLinkClient({this.connected = false});

  final _connection = StreamController<FlipperConnectionState>.broadcast();

  bool connected;

  bool get isListening => _connection.hasListener;

  /// A link event, which is how the viewer hears about anything after the
  /// first frame.
  void say({required bool connected}) {
    this.connected = connected;
    _connection.add(
      FlipperConnectionState(
        mode: connected ? FlipperMode.rpc : FlipperMode.disconnected,
        device: null,
        connected: connected,
      ),
    );
  }

  Future<void> close() => _connection.close();

  @override
  bool get isConnected => connected;

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeLinkClient client;
  late int sends;

  setUp(() {
    client = FakeLinkClient(connected: true);
    sends = 0;
  });
  tearDown(() => client.close());

  Future<void> show(
    WidgetTester tester, {
    bool isConnected = true,
    FlipperClient? use,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
      home: IrFileViewer(
        client: use ?? client,
        fileName: 'tv.ir',
        subtitle: '/ext/infrared/tv.ir',
        loading: false,
        error: null,
        text: 'Filetype: IR signals file',
        bytes: const [1, 2, 3],
        isConnected: isConnected,
        onSend: ({required bytes, required onProgress}) async {
          sends++;
          return true;
        },
      ),
    ),
  );

  Future<void> tapSend(WidgetTester tester) async {
    await tester.tap(find.byType(ProgressButton));
    await tester.pump();
  }

  testWidgets('sends while the link is up', (tester) async {
    await show(tester);

    await tapSend(tester);

    expect(sends, 1);
  });

  testWidgets('does not send when the client says there is no link', (
    tester,
  ) async {
    client = FakeLinkClient(connected: false);
    await show(tester);

    await tapSend(tester);

    expect(sends, 0, reason: 'the page thought it was connected; the link did');
  });

  testWidgets('does not send when the page says there is no link', (
    tester,
  ) async {
    await show(tester, isConnected: false);

    await tapSend(tester);

    expect(sends, 0);
  });

  // The case the subscription exists for: the file is already open when the
  // Flipper goes away.
  testWidgets('stops sending when the link drops under it', (tester) async {
    await show(tester);
    await tapSend(tester);
    expect(sends, 1, reason: 'the starting point');

    client.say(connected: false);
    await tester.pump();
    await tapSend(tester);

    expect(sends, 1, reason: 'nothing was sent the second time');
  });

  testWidgets('sends again when the link comes back', (tester) async {
    client = FakeLinkClient(connected: false);
    await show(tester);

    client.say(connected: true);
    await tester.pump();
    await tapSend(tester);

    expect(sends, 1);
  });

  // The client can change under this now that it is passed in. The
  // subscription belongs to the one it was opened on, so a page that swapped
  // devices would otherwise keep reading the link that left.
  testWidgets('follows a client handed in later', (tester) async {
    await show(tester);

    final second = FakeLinkClient(connected: false);
    addTearDown(second.close);
    await show(tester, use: second);
    await tester.pump();

    expect(client.isListening, isFalse, reason: 'the old one was let go');
    await tapSend(tester);
    expect(sends, 0, reason: 'the new client has no link');

    second.say(connected: true);
    await tester.pump();
    await tapSend(tester);

    expect(sends, 1, reason: 'and its events are the ones that count');
  });

  testWidgets('stops listening when it goes away', (tester) async {
    await show(tester);
    expect(client.isListening, isTrue, reason: 'the starting point');

    await tester.pumpWidget(const SizedBox());

    expect(client.isListening, isFalse);
  });
}
