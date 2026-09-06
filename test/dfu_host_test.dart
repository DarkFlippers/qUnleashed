import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flipperlib/src/dfu/android_backend.dart';
import 'package:flipperlib/src/dfu/isolate_proxy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBackend implements DfuUsbBackend {
  bool present = false;
  final StreamController<bool> _presence = StreamController<bool>.broadcast();
  final List<String> calls = [];
  DfuHostException? acquireFailure;
  int nextFd = 7;

  void setPresent(bool value) {
    present = value;
    _presence.add(value);
  }

  @override
  bool get available => true;

  @override
  Future<bool> isPresent() async {
    calls.add('isPresent');
    return present;
  }

  @override
  Stream<bool> get presence => _presence.stream;

  @override
  Future<bool> waitPresence(bool wanted, Duration timeout) async {
    calls.add('wait:$wanted');
    if (present == wanted) return true;
    return _presence.stream
        .firstWhere((v) => v == wanted)
        .then((_) => true)
        .timeout(timeout, onTimeout: () => false);
  }

  @override
  Future<DfuDeviceRef?> acquire() async {
    calls.add('acquire');
    final failure = acquireFailure;
    if (failure != null) throw failure;
    if (!present) return null;
    return UsbFdDeviceRef(nextFd++);
  }

  @override
  Future<void> release(DfuDeviceRef ref) async {
    calls.add('release:${(ref as UsbFdDeviceRef).fd}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DfuProxy', () {
    late _FakeBackend backend;
    late DfuProxyServer server;
    late DfuProxyClient client;

    setUp(() {
      backend = _FakeBackend();
      server = DfuProxyServer(backend);
      client = DfuProxyClient(server.sendPort);
    });

    tearDown(() => server.close());

    test('round-trips presence, acquire and release', () async {
      expect(await client.isPresent(), isFalse);
      backend.present = true;
      expect(await client.isPresent(), isTrue);

      final ref = await client.acquire();
      expect(ref, const UsbFdDeviceRef(7));
      await client.release(ref!);
      expect(backend.calls, ['isPresent', 'isPresent', 'acquire', 'release:7']);
    });

    test('returns null when no device is present', () async {
      expect(await client.acquire(), isNull);
    });

    test(
      'waitPresence resolves on a transition and false on timeout',
      () async {
        final wait = client.waitPresence(true, const Duration(seconds: 5));
        await Future<void>.delayed(Duration.zero);
        backend.setPresent(true);
        expect(await wait, isTrue);

        expect(
          await client.waitPresence(false, const Duration(milliseconds: 50)),
          isFalse,
        );
      },
    );

    test('carries host failures across the port', () async {
      backend.acquireFailure = const DfuHostException(
        DfuHostFailure.permissionDenied,
        'declined',
      );
      await expectLater(
        client.acquire(),
        throwsA(
          isA<DfuHostException>()
              .having(
                (e) => e.failure,
                'failure',
                DfuHostFailure.permissionDenied,
              )
              .having((e) => e.message, 'message', 'declined'),
        ),
      );
    });

    test('presence stream is not served on the worker side', () {
      expect(() => client.presence, throwsUnsupportedError);
    });
  });

  group('AndroidDfuBackend', () {
    const methods = MethodChannel('test/dfu');
    const events = EventChannel('test/dfu/events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    late List<MethodCall> log;
    late Map<String, Object? Function(MethodCall)> handlers;
    late AndroidDfuBackend backend;

    setUp(() {
      log = [];
      handlers = {};
      messenger.setMockMethodCallHandler(methods, (call) async {
        log.add(call);
        final handler = handlers[call.method];
        if (handler == null) return null;
        return handler(call);
      });
      backend = AndroidDfuBackend(methods: methods, events: events);
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(methods, null);
      messenger.setMockStreamHandler(events, null);
    });

    test('acquire wraps the descriptor the host returns', () async {
      handlers['open'] = (_) => {'fd': 42, 'name': '/dev/bus/usb/001/005'};
      final ref = await backend.acquire();
      expect(ref, const UsbFdDeviceRef(42));

      await backend.release(ref!);
      expect(log.last.method, 'close');
      expect(log.last.arguments, {'fd': 42});
    });

    test('acquire maps host error codes', () async {
      handlers['open'] = (_) => throw PlatformException(code: 'no_device');
      expect(await backend.acquire(), isNull);

      handlers['open'] = (_) =>
          throw PlatformException(code: 'permission_denied', message: 'no');
      await expectLater(
        backend.acquire(),
        throwsA(
          isA<DfuHostException>().having(
            (e) => e.failure,
            'failure',
            DfuHostFailure.permissionDenied,
          ),
        ),
      );

      handlers['open'] = (_) => throw PlatformException(code: 'busy');
      await expectLater(
        backend.acquire(),
        throwsA(
          isA<DfuHostException>().having(
            (e) => e.failure,
            'failure',
            DfuHostFailure.other,
          ),
        ),
      );
    });

    test('presence forwards transitions from the event channel', () async {
      MockStreamHandlerEventSink? sink;
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, eventSink) => sink = eventSink,
          onCancel: (_) => sink = null,
        ),
      );

      final seen = <bool>[];
      final sub = backend.presence.listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(sink, isNotNull);

      sink!.success(true);
      sink!.success(true);
      sink!.success(false);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [true, false]);

      await sub.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(sink, isNull);
    });

    test('waitPresence answers from the current state first', () async {
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
      handlers['isPresent'] = (_) => true;
      expect(
        await backend.waitPresence(true, const Duration(seconds: 1)),
        isTrue,
      );

      handlers['isPresent'] = (_) => false;
      expect(
        await backend.waitPresence(true, const Duration(milliseconds: 50)),
        isFalse,
      );
    });
  });

  group('DfuDetector', () {
    test('reports the initial state and later transitions once', () async {
      final backend = _FakeBackend()..present = true;
      final detector = DfuDetector(backend: backend);
      final seen = <bool>[];
      detector.presence.listen(seen.add);

      detector.start();
      await Future<void>.delayed(Duration.zero);
      expect(detector.isPresent, isTrue);

      backend.setPresent(true);
      backend.setPresent(false);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [true, false]);

      detector.stop();
      backend.setPresent(true);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [true, false]);
      await detector.dispose();
    });
  });
}
