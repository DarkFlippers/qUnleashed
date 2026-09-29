import 'dart:async';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flipperlib/flipperlib.dart' as fl show File;
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/archive/models/key.dart';

/// A Flipper that answers the calls `EmulateService` makes, and refuses
/// whichever of them a test says to.
///
/// Shared rather than copied: `appStart`, `appLoadFile`, `appExit` and
/// `storageReadChunked` are all extensions on `FlipperClient`, resolved
/// statically, so every test that drives this service has to fake the same
/// one method underneath them. Two files did before this was pulled out.

class FakeAppClient implements FlipperClient {
  final _frames = StreamController<Main>.broadcast();
  final _connection = StreamController<FlipperConnectionState>.broadcast();

  bool connected = true;

  /// Raised instead of answering `appStart`, when set.
  Object? startThrows;

  /// Raised instead of answering `appLoadFile`, when set.
  Object? loadThrows;

  /// Raised instead of answering `appExit`, when set.
  Object? exitThrows;

  /// Raised instead of answering a storage read, when set.
  Object? readThrows;

  /// What a storage read answers with when it does not throw.
  String fileBody = '';

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
      if (exitThrows != null) throw exitThrows!;
      _notify(AppState.APP_CLOSED);
      return const [];
    }
    if (request.hasStorageReadRequest()) {
      calls.add('storageRead(${request.storageReadRequest.path})');
      if (readThrows != null) throw readThrows!;
      final frame = Main(
        storageReadResponse: ReadResponse(
          file: fl.File(data: utf8.encode(fileBody)),
        ),
      );
      onFrame?.call(frame);
      return const [];
    }
    if (request.hasAppButtonPressRequest()) {
      calls.add('appButtonPress');
      return const [];
    }
    if (request.hasAppButtonReleaseRequest()) {
      calls.add('appButtonRelease');
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
