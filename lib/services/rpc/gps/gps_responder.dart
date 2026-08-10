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
          onError: (Object error) =>
              LogService.log('[GPS] location stream error: $error'),
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
    if (!state.connected || state.mode != FlipperMode.rpc) {
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
      LogService.log('[GPS] readiness check failed: $error');
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
      await _client.sendRpc(
        Main(gpsLocation: location),
        priority: FlipperRequestPriority.background,
      );
    } catch (error) {
      LogService.log('[GPS] failed to send location: $error');
    }
  }

  Future<void> _sendError(CommandStatus status) async {
    try {
      await _client.sendRpc(
        Main(commandStatus: status, gpsLocation: Location()),
      );
    } catch (error) {
      LogService.log('[GPS] failed to send error ${status.name}: $error');
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
