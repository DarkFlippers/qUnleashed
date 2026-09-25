import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/remote/desktop/media_remote.dart';
import 'package:qunleashed/pages/tools/remote/desktop/models/models.dart';
import 'package:qunleashed/pages/tools/remote/desktop/page.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quiet_device_title.dart';

/// Enough of a client for the page to open a session over and for the test to
/// see what actually reached the wire. Shaped like the fakes in
/// remote_session_test.dart rather than shared with them: those pin the session
/// in isolation, this one pins what the page does in front of it.
/// The one link this fake stands for: requests made under it reach the same
/// client, and it is alive exactly while that client is connected.
class _FakeBinding implements FlipperSessionBinding {
  _FakeBinding(this._client);

  final _FakeClient _client;

  @override
  FlipperDevice? get device => null;

  @override
  bool get isAlive => _client.isConnected;

  @override
  T run<T>(T Function() body) => body();
}

class _FakeClient with QuietDeviceTitle implements FlipperClient {
  final broadcast = StreamController<Main>.broadcast();
  final connection = StreamController<FlipperConnectionState>.broadcast();
  final List<Main> sent = [];

  bool connected = true;

  int get inputEvents =>
      sent.where((r) => r.hasGuiSendInputEventRequest()).length;

  @override
  bool get isConnected => connected;

  @override
  FlipperSessionBinding bindCurrentSession() => _FakeBinding(this);

  @override
  Stream<Main> get broadcastStream => broadcast.stream;

  @override
  Stream<Main> get notificationStream => broadcast.stream;

  @override
  Stream<FlipperConnectionState> get connectionStream => connection.stream;

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
    sent.add(request);
    onSent?.call();
    return const <Main>[];
  }

  @override
  Future<void> sendRpc(
    Main message, {
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    Duration sendTimeout = const Duration(seconds: 30),
  }) async {
    sent.add(message);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: child,
);

void main() {
  const channel = MethodChannel('qunleashed/media_remote');
  late TestDefaultBinaryMessenger messenger;
  final nativeCalls = <String>[];

  setUp(() {
    nativeCalls.clear();
    MediaRemoteBridge.resetNativeStateForTesting();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'remote.media.enabled': true,
    });
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          ..setMockMethodCallHandler(channel, (call) async {
            nativeCalls.add(call.method);
            return null;
          });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    // Also on the way out: dispose fires an unawaited stop() that these tests
    // never wait for, and a straggler landing during the next setUp would
    // write the statics back after they were reset.
    addTearDown(MediaRemoteBridge.resetNativeStateForTesting);
  });

  /// Delivers one media button the way MediaRemoteChannel.sendInput does.
  Future<void> pressWrist(String input) => messenger.handlePlatformMessage(
    channel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall('button', input)),
    (_) {},
  );

  testWidgets('a wrist press while the page is closing never reaches the wire', (
    tester,
  ) async {
    final client = _FakeClient();
    // Phone-sized and portrait: RemoteLayout.isWide is width > height, and the
    // narrow layout is both where Wrist Remote is actually used and the one
    // that renders the app bar's back button.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(RemoteControlPage(client: client, mediaRemoteSupported: true)),
    );
    // Loading preferences and reconciling the native session are real async,
    // which the widget tester's fake clock does not drive - settle the actual
    // event loop before any of this means anything.
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    expect(
      nativeCalls,
      contains('start'),
      reason:
          'the page must own the MediaSession before any of this means '
          'anything',
    );

    // playPause maps to OK by default, and no double gesture is assigned, so
    // this dispatches immediately rather than opening the 400 ms window.
    await pressWrist('playPause');
    await tester.pumpAndSettle();
    expect(
      client.inputEvents,
      greaterThan(0),
      reason: 'a live page forwards wrist input',
    );

    final beforeClose = client.inputEvents;

    // Back runs _close(): shutdown() and pop. dispose - and with it the
    // bridge's stop() - only runs once the exit transition finishes, so the
    // MediaSession is still live and the handler still registered right here.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();

    await pressWrist('playPause');
    await tester.pump(const Duration(milliseconds: 20));

    // Two independent guards hold this: _close() shuts the session down, which
    // clears inputAvailable, and _onMediaRemoteButton also checks _closing.
    // Either alone satisfies the assertion, so this fails only if both go -
    // which is the point. The property is what matters, not which check
    // enforces it.
    expect(
      client.inputEvents,
      beforeClose,
      reason:
          'the page is going away - a press in the exit transition must not '
          'land on whatever screen the Flipper is showing by then',
    );

    await tester.pumpAndSettle();
  });

  testWidgets('the mapping dialog lays out every row without overflowing', (
    tester,
  ) async {
    final client = _FakeClient();
    // Narrow enough to squeeze the dropdown rows, which is where the icon plus
    // an elided label has to survive.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(RemoteControlPage(client: client, mediaRemoteSupported: true)),
    );
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.watch_outlined));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    // One row per media input, each with its own leading icon, and the labels
    // are the bare l10n strings now rather than glyph-prefixed ones.
    expect(find.text('Previous'), findsOneWidget);
    expect(find.text('Double Play / Pause'), findsOneWidget);
    // The single and double variants of a transport control deliberately share
    // one icon; the label is what tells them apart.
    expect(find.byIcon(Icons.skip_previous), findsNWidgets(2));
    expect(find.byIcon(Icons.volume_down), findsOneWidget);

    // The closed dropdown gets a bounded width from isExpanded, so the row
    // that actually risks overflowing is the open menu. Open one.
    await tester.tap(find.byType(DropdownButton<RemoteButton?>).first);
    await tester.pumpAndSettle();
    expect(find.text('Not assigned'), findsWidgets);

    // A RenderFlex overflow reports through the exception channel rather than
    // failing a finder, so ask directly.
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Not assigned').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  });
}
