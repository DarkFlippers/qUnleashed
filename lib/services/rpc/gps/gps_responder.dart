import 'dart:async';

import 'package:flipperlib/flipperlib.dart';

import '../../logging.dart';

class GpsFix {
  const GpsFix({
    required this.latitude,
    required this.longitude,
    this.heading = 0,
    this.speed = 0,
    this.altitude = 0,
    this.accuracy = 0,
    this.satellites = 0,
  });

  factory GpsFix.fromLocation(Location location) => GpsFix(
    latitude: location.latitude / 1e7,
    longitude: location.longitude / 1e7,
    heading: location.heading / 100,
    speed: location.speed / 1000,
    altitude: location.altitude / 100,
    accuracy: location.accuracy / 1000,
    satellites: location.satellites,
  );

  final double latitude;
  final double longitude;
  final double heading;
  final double speed;
  final double altitude;
  final double accuracy;
  final int satellites;

  bool get hasFix => latitude != 0 || longitude != 0;
}

enum GpsReadiness { ready, notSupported, disabled, permissionDenied, unknown }

abstract class GpsLocationProvider {
  Future<GpsReadiness> ensureReady();

  Stream<GpsFix> watch(int frequencyHz);

  Future<GpsFix?> current();
}

class _GpsStreamPump {
  _GpsStreamPump({
    required GpsLocationProvider provider,
    required int hz,
    required void Function(GpsFix) onFix,
  }) : _provider = provider,
       _hz = hz,
       _onFix = onFix;

  static const Duration _heartbeat = Duration(seconds: 2);

  final GpsLocationProvider _provider;
  final int _hz;
  final void Function(GpsFix) _onFix;

  StreamSubscription<GpsFix>? _sub;
  Timer? _flushTimer;
  Timer? _heartbeatTimer;
  GpsFix? _pending;
  GpsFix? _lastSent;
  final Stopwatch _sinceEmit = Stopwatch();

  void start() {
    _sub = _provider
        .watch(_hz)
        .listen(
          _onPosition,
          // cancelOnError leaves the Flipper with no further fixes, and
          // the platform stream has no other channel.
          onError: (Object error) =>
              LogService.warn('[GPS] location stream error: $error'),
        );
    _heartbeatTimer = Timer.periodic(_heartbeat, (_) {
      final fix = _lastSent;
      if (fix != null && _sinceEmit.elapsed >= _heartbeat) _emit(fix);
    });
  }

  Duration get _interval => Duration(milliseconds: (1000 / _hz).round());

  void _onPosition(GpsFix fix) {
    _pending = fix;
    final interval = _interval;
    final elapsed = _sinceEmit.elapsed;
    if (!_sinceEmit.isRunning || elapsed >= interval) {
      _flushTimer?.cancel();
      _flush();
    } else {
      _flushTimer ??= Timer(interval - elapsed, _flush);
    }
  }

  void _flush() {
    _flushTimer = null;
    final fix = _pending;
    if (fix == null) return;
    _pending = null;
    _emit(fix);
  }

  void _emit(GpsFix fix) {
    _lastSent = fix;
    _sinceEmit
      ..reset()
      ..start();
    _onFix(fix);
  }

  Future<void> stop() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _sub?.cancel();
    _sub = null;
  }
}

class FlipperGpsResponder {
  FlipperGpsResponder(this._client, this._provider);

  static const int minFrequency = 1;
  static const int maxFrequency = 10;

  final FlipperClient _client;
  final GpsLocationProvider _provider;

  StreamSubscription<Main>? _notifications;
  StreamSubscription<FlipperConnectionState>? _connection;
  _GpsStreamPump? _pump;
  int? _streamFrequency;

  /// The Flipper that asked for location, held for as long as it is being sent.
  ///
  /// A responder answers the device that spoke to it. Once a stream is running
  /// nothing further arrives to say who it is for, so without this the fixes
  /// would go to whichever Flipper happened to be active - one that never asked
  /// and has no GPS app open - while the one that did asked would go quiet.
  FlipperSessionBinding? _binding;

  Future<void> _reply(Future<void> Function() send) {
    final binding = _binding;
    return binding == null ? send() : binding.run(send);
  }

  void attach() {
    _notifications ??= _client.notificationStream.listen(_onNotification);
    _connection ??= _client.connectionStream.listen(_onConnection);
  }

  Future<void> detach() async {
    await _stopStream();
    final notifications = _notifications;
    final connection = _connection;
    _notifications = null;
    _connection = null;
    await notifications?.cancel();
    await connection?.cancel();
  }

  void _onConnection(FlipperConnectionState state) {
    // Judged by the held session, not the active one: after a switch the state
    // describes a different Flipper, and its being ready says nothing about
    // whether the one receiving the fixes still is.
    final binding = _binding;
    if (binding != null ? !binding.isAlive : !state.rpcReady) {
      unawaited(_stopStream());
    }
  }

  void _onNotification(Main frame) {
    if (frame.hasGpsStreamStartRequest()) {
      unawaited(_onStreamStart(frame.gpsStreamStartRequest.frequency));
    } else if (frame.hasGpsStreamStopRequest()) {
      unawaited(_stopStream());
    } else if (frame.hasGpsLocationRequest()) {
      unawaited(_onLocationRequest());
    }
  }

  Future<void> _onStreamStart(int frequency) async {
    _binding ??= _client.bindCurrentSession();
    final hz = frequency.clamp(minFrequency, maxFrequency);
    if (_streamFrequency == hz) return;
    _streamFrequency = hz;
    if (!await _ensureReady()) {
      if (_streamFrequency == hz) _streamFrequency = null;
      return;
    }
    if (_streamFrequency != hz) return;
    await _stopPump();
    _pump = _GpsStreamPump(
      provider: _provider,
      hz: hz,
      onFix: (fix) => unawaited(_sendLocation(fix)),
    )..start();
  }

  Future<void> _onLocationRequest() async {
    if (!await _ensureReady()) return;
    final fix = await _provider.current();
    if (fix != null) await _sendLocation(fix);
  }

  Future<bool> _ensureReady() async {
    GpsReadiness readiness;
    try {
      readiness = await _provider.ensureReady();
    } catch (error) {
      LogService.warn('[GPS] readiness check failed: $error');
      readiness = GpsReadiness.unknown;
    }
    switch (readiness) {
      case GpsReadiness.ready:
        return true;
      case GpsReadiness.notSupported:
        await _sendError(CommandStatus.ERROR_GPS_NOT_SUPPORTED);
        return false;
      case GpsReadiness.disabled:
        await _sendError(CommandStatus.ERROR_GPS_DISABLED);
        return false;
      case GpsReadiness.permissionDenied:
        await _sendError(CommandStatus.ERROR_GPS_NO_PERMISSION);
        return false;
      case GpsReadiness.unknown:
        await _sendError(CommandStatus.ERROR_GPS_UNKNOWN);
        return false;
    }
  }

  Future<void> _stopStream() async {
    _streamFrequency = null;
    // Released with the stream: nothing is being sent any more, so a later
    // one-off request binds whichever Flipper asks for it next.
    _binding = null;
    await _stopPump();
  }

  Future<void> _stopPump() async {
    final pump = _pump;
    _pump = null;
    await pump?.stop();
  }

  static int _scaleUnsigned(double value, double factor) =>
      value.isFinite && value > 0 ? (value * factor).round() : 0;

  Future<void> _sendLocation(GpsFix fix) async {
    final location = Location(
      latitude: (fix.latitude * 1e7).round(),
      longitude: (fix.longitude * 1e7).round(),
      altitude: (fix.altitude * 100).round(),
      speed: _scaleUnsigned(fix.speed, 1000),
      heading: _scaleUnsigned(fix.heading, 100),
      accuracy: _scaleUnsigned(fix.accuracy, 1000),
      satellites: fix.satellites,
    );
    try {
      // Bound work, so not foreground - and ordinary rather than background,
      // because a fix is one small frame the device is waiting on, not bulk.
      await _reply(
        () => _client.sendRpc(
          Main(gpsLocation: location),
          priority: FlipperRequestPriority.unattended,
        ),
      );
    } catch (error) {
      LogService.info('[GPS] failed to send location: $error');
    }
  }

  Future<void> _sendError(CommandStatus status) async {
    try {
      await _reply(
        () => _client.sendRpc(
          Main(commandStatus: status, gpsLocation: Location()),
        ),
      );
    } catch (error) {
      LogService.info('[GPS] failed to send error ${status.name}: $error');
    }
  }
}

extension FlipperGpsApi on FlipperClient {
  FlipperGpsResponder attachGpsResponder(GpsLocationProvider provider) {
    final responder = FlipperGpsResponder(this, provider);
    responder.attach();
    return responder;
  }

  Stream<GpsFix> flipperLocationStream() {
    return notificationStream.transform(
      StreamTransformer<Main, GpsFix>.fromHandlers(
        handleData: (frame, sink) {
          if (frame.hasGpsLocation()) {
            sink.add(GpsFix.fromLocation(frame.gpsLocation));
          }
        },
      ),
    );
  }
}
