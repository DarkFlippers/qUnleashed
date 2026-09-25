import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/archive/models/key.dart';
import 'package:qunleashed/services/emulate/service.dart';

/// Opening a key on the Flipper, and every way that goes wrong.
///
/// This is the half of `EmulateService` that `emulate_service_test.dart` said
/// it could not reach: `start` binds the session first, and
/// `FlipperSessionBinding`'s only constructor was private to flipperlib, so a
/// fake client could not return one. `FlipperSessionBinding.unbound()` is what
/// opened it — dart-flipperlib#5.
///
/// What is still not covered is the reason the binding exists: an emulation
/// belongs to the Flipper it started on, and `_onConnection` closes it when
/// another takes its place. That needs a *live* session, which `unbound` is
/// by definition not.
class FakeAppClient implements FlipperClient {
  final _frames = StreamController<Main>.broadcast();
  final _connection = StreamController<FlipperConnectionState>.broadcast();

  bool connected = true;

  /// Raised instead of answering `appStart`, when set.
  Object? startThrows;

  /// Raised instead of answering `appLoadFile`, when set.
  Object? loadThrows;

  /// Whether the app ever reports itself started. False is the real case
  /// where the fallback delay has to carry the call.
  bool reportsStarted = true;

  final calls = <String>[];

  Future<void> close() async {
    await _frames.close();
    await _connection.close();
  }

  void _notify(AppState state) => scheduleMicrotask(
    () => _frames.add(Main(appStateResponse: AppStateResponse(state: state))),
  );

  @override
  bool get isConnected => connected;

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  /// Where `appStateStream()` gets its frames: the API is an extension over
  /// this, so faking it is faking the notification stream.
  @override
  Stream<Main> get notificationStream => _frames.stream;

  /// Unbound, which is what the real one returns with nothing connected.
  @override
  FlipperSessionBinding bindCurrentSession() =>
      const FlipperSessionBinding.unbound();

  /// The one method the whole app API runs through.
  ///
  /// `appStart`, `appLoadFile` and `appExit` are extensions on
  /// `FlipperClient`, and an extension is resolved statically - declaring
  /// them on a fake does nothing, the real bodies run. They all reach here,
  /// so this is the boundary a fake belongs at.
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
    if (request.hasAppStartRequest()) {
      final r = request.appStartRequest;
      calls.add('appStart(${r.name}, ${r.args})');
      if (startThrows != null) throw startThrows!;
      if (reportsStarted) _notify(AppState.APP_STARTED);
      return const [];
    }
    if (request.hasAppLoadFileRequest()) {
      calls.add('appLoadFile(${request.appLoadFileRequest.path})');
      if (loadThrows != null) throw loadThrows!;
      return const [];
    }
    if (request.hasAppExitRequest()) {
      calls.add('appExit');
      _notify(AppState.APP_CLOSED);
      return const [];
    }
    calls.add('unexpected ${request.whichContent()}');
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ArchiveKey key() => ArchiveKey(
  name: 'garage',
  category: ArchiveCategory.subghz,
  state: ArchiveKeyState.synced,
  extension: '.sub',
  remotePath: '/ext/subghz/garage.sub',
);

/// An RPC failure of [T]'s kind. The response carries no status the service
/// reads; it is the type that decides the answer.
FlipperRpcException rpcFailure(FlipperRpcException Function(Main) build) =>
    build(Main());

void main() {
  late FakeAppClient client;
  late EmulateService service;

  setUp(() {
    client = FakeAppClient();
    service = EmulateService(client: client);
  });
  tearDown(() => client.close());

  group('a run that works', () {
    test('starts the app and loads the file, in that order', () async {
      final result = await service.start(key());

      expect(result.isOk, isTrue);
      expect(client.calls, [
        'appStart(Sub-GHz, RPC)',
        'appLoadFile(/ext/subghz/garage.sub)',
      ]);
    });

    test('is running, and remembers what on', () async {
      await service.start(key());

      expect(service.isRunning, isTrue);
      expect(service.activeKey?.name, 'garage');
    });

    // The app is started with `RPC` as its argument, not the file: the file
    // arrives separately through appLoadFile, and an app handed a path as an
    // argument opens it without the app ever entering RPC mode.
    test('starts the app in RPC mode rather than with the file', () async {
      await service.start(key());

      expect(client.calls.first, contains('RPC'));
      expect(client.calls.first, isNot(contains('/ext/')));
    });
  });

  group('the app refusing to start', () {
    test('reads a locked system as busy, not as a failure', () async {
      client.startThrows = rpcFailure(FlipperRpcAppSystemLockedException.new);

      final result = await service.start(key());

      expect(result.error, EmulateError.busy);
    });

    test('reads a busy device as busy', () async {
      client.startThrows = rpcFailure(FlipperRpcBusyException.new);

      final result = await service.start(key());

      expect(result.error, EmulateError.busy);
    });

    // Busy is a "try again"; anything else is not, and the two show the user
    // different things.
    test('reads anything else as a failed start', () async {
      client.startThrows = StateError('transport is gone');

      final result = await service.start(key());

      expect(result.error, EmulateError.appStartFailed);
    });

    test('never reaches the file', () async {
      client.startThrows = StateError('transport is gone');

      await service.start(key());

      expect(client.calls, ['appStart(Sub-GHz, RPC)']);
      expect(service.isRunning, isFalse);
    });
  });

  group('the file refusing to load', () {
    setUp(() => client.loadThrows = StateError('no such file'));

    test('is its own answer, not a failed start', () async {
      final result = await service.start(key());

      expect(result.error, EmulateError.loadFileFailed);
    });

    // The app is already up at this point. Leaving it there would strand a
    // scene on the Flipper with nothing driving it.
    test('closes the app it had already started', () async {
      await service.start(key());

      expect(client.calls, contains('appExit'));
      expect(service.isRunning, isFalse);
      expect(service.activeKey, isNull);
    });
  });

  // The real device does not always send APP_STARTED, so the call waits and
  // then goes on anyway. Without the fallback the load would never be tried.
  test('loads the file even when the app never says it started', () async {
    client.reportsStarted = false;

    final result = await service
        .start(key())
        .timeout(const Duration(seconds: 30));

    expect(result.isOk, isTrue);
    expect(client.calls, contains('appLoadFile(/ext/subghz/garage.sub)'));
  });

  test('a second start closes the first', () async {
    await service.start(key());
    client.calls.clear();

    await service.start(key());

    expect(
      client.calls.first,
      'appExit',
      reason: 'the run still open belongs to the Flipper it started on',
    );
  });
}
