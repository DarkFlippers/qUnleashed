import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/remote/desktop/media_remote.dart';
import 'package:qunleashed/pages/tools/remote/desktop/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('defaults are safe and single taps are instant', () async {
    final events = <(RemoteButton, WristRemoteAction)>[];
    final bridge = MediaRemoteBridge(
      onButton: (button, action) => events.add((button, action)),
    );

    await bridge.ensureLoaded();

    expect(bridge.enabled, isFalse);
    expect(bridge.buttonFor(MediaRemoteInput.previous), RemoteButton.left);
    expect(bridge.buttonFor(MediaRemoteInput.playPause), RemoteButton.ok);
    expect(bridge.buttonFor(MediaRemoteInput.next), RemoteButton.right);
    expect(bridge.buttonFor(MediaRemoteInput.doublePrevious), isNull);
    expect(bridge.buttonFor(MediaRemoteInput.doublePlayPause), isNull);
    expect(bridge.buttonFor(MediaRemoteInput.doubleNext), isNull);

    await bridge.handleCallForTesting(const MethodCall('button', 'playPause'));
    expect(events, [(RemoteButton.ok, WristRemoteAction.tap)]);
  });

  test('stored mappings, actions and enabled state load', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'remote.media.enabled': true,
      'remote.media.previous': 'right',
      'remote.media.previous.action': 'hold2s',
      'remote.media.doubleNext': '__none__',
    });

    final bridge = MediaRemoteBridge(onButton: (_, _) {});
    await bridge.ensureLoaded();

    expect(bridge.enabled, isTrue);
    expect(bridge.buttonFor(MediaRemoteInput.previous), RemoteButton.right);
    expect(
      bridge.actionFor(MediaRemoteInput.previous),
      WristRemoteAction.hold2s,
    );
    expect(bridge.buttonFor(MediaRemoteInput.doubleNext), isNull);
  });

  test('failed preference load can be retried', () async {
    final preferences = await SharedPreferences.getInstance();
    var attempts = 0;
    final bridge = MediaRemoteBridge(
      onButton: (_, _) {},
      preferencesLoader: () {
        attempts++;
        if (attempts == 1) {
          return Future<SharedPreferences>.error(
            StateError('transient preferences failure'),
          );
        }
        return Future<SharedPreferences>.value(preferences);
      },
    );

    await expectLater(bridge.ensureLoaded(), throwsStateError);
    await bridge.ensureLoaded();

    expect(attempts, 2);
  });

  test('assigned double tap delays single and wins on second tap', () async {
    final events = <(RemoteButton, WristRemoteAction)>[];
    final bridge = MediaRemoteBridge(
      onButton: (button, action) => events.add((button, action)),
    );
    await bridge.ensureLoaded();
    await bridge.setButtonFor(
      MediaRemoteInput.doublePlayPause,
      RemoteButton.back,
    );

    await bridge.handleCallForTesting(const MethodCall('button', 'playPause'));
    expect(
      events,
      isEmpty,
      reason: 'the assigned double gesture opens a window',
    );

    await Future<void>.delayed(
      wristRemoteDoubleTapDuration + const Duration(milliseconds: 30),
    );
    expect(events, [(RemoteButton.ok, WristRemoteAction.tap)]);

    events.clear();
    await bridge.handleCallForTesting(const MethodCall('button', 'playPause'));
    await bridge.handleCallForTesting(const MethodCall('button', 'playPause'));
    expect(events, [(RemoteButton.back, WristRemoteAction.tap)]);
  });

  test(
    'start stopped during preference load never creates MediaSession',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'remote.media.enabled': true,
      });
      final preferences = await SharedPreferences.getInstance();
      final loadGate = Completer<SharedPreferences>();
      final nativeCalls = <String>[];
      const channel = MethodChannel('qunleashed/media_remote');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        nativeCalls.add(call.method);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final bridge = MediaRemoteBridge(
        onButton: (_, _) {},
        supportedOverride: true,
        preferencesLoader: () => loadGate.future,
      );

      final starting = bridge.start();
      await Future<void>.delayed(Duration.zero);
      await bridge.stop();
      loadGate.complete(preferences);
      await starting;

      expect(nativeCalls, isEmpty);
    },
  );

  test('new bridge keeps ownership when old bridge stops', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'remote.media.enabled': true,
    });
    final nativeCalls = <String>[];
    const channel = MethodChannel('qunleashed/media_remote');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final oldBridge = MediaRemoteBridge(
      onButton: (_, _) {},
      supportedOverride: true,
    );
    final newBridge = MediaRemoteBridge(
      onButton: (_, _) {},
      supportedOverride: true,
    );

    await oldBridge.start();
    await newBridge.start();
    await oldBridge.stop();

    expect(nativeCalls, [
      'start',
    ], reason: 'the outgoing page must not stop the new page MediaSession');

    await newBridge.stop();
    expect(nativeCalls, ['start', 'stop']);
  });

  test('MediaSession is opt-in and follows the enabled setting', () async {
    final nativeCalls = <String>[];
    const channel = MethodChannel('qunleashed/media_remote');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final bridge = MediaRemoteBridge(
      onButton: (_, _) {},
      supportedOverride: true,
    );

    await bridge.start();
    expect(nativeCalls, isEmpty, reason: 'Wrist Remote defaults to disabled');

    await bridge.setEnabled(true);
    expect(nativeCalls, ['start']);

    await bridge.setEnabled(false);
    expect(nativeCalls, ['start', 'stop']);
  });

  test('reset restores mappings without disabling Wrist Remote', () async {
    final bridge = MediaRemoteBridge(onButton: (_, _) {});
    await bridge.ensureLoaded();
    await bridge.setEnabled(true);
    await bridge.setButtonFor(MediaRemoteInput.previous, RemoteButton.up);
    await bridge.setActionFor(
      MediaRemoteInput.previous,
      WristRemoteAction.hold3s,
    );
    await bridge.setButtonFor(
      MediaRemoteInput.doublePlayPause,
      RemoteButton.back,
    );

    await bridge.resetMappings();

    expect(bridge.enabled, isTrue);
    expect(bridge.buttonFor(MediaRemoteInput.previous), RemoteButton.left);
    expect(bridge.actionFor(MediaRemoteInput.previous), WristRemoteAction.tap);
    expect(bridge.buttonFor(MediaRemoteInput.doublePlayPause), isNull);
  });
}
