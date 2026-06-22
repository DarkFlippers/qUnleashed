import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flipperlib/flipperlib.dart';
import 'package:geolocator/geolocator.dart';

class GeolocatorGpsProvider implements GpsLocationProvider {
  static const Duration _keepAlive = Duration(seconds: 2);

  @override
  Future<GpsReadiness> ensureReady() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return GpsReadiness.disabled;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final granted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      return granted ? GpsReadiness.ready : GpsReadiness.permissionDenied;
    } on MissingPluginException {
      return GpsReadiness.notSupported;
    } on UnimplementedError {
      return GpsReadiness.notSupported;
    }
  }

  @override
  Stream<GpsFix> watch(int frequencyHz) {
    final hz = frequencyHz < 1 ? 1 : frequencyHz;
    final minInterval = Duration(milliseconds: (1000 / hz).round());

    final controller = StreamController<GpsFix>();
    StreamSubscription<Position>? positionSub;
    Timer? flushTimer;
    Timer? keepAliveTimer;
    Position? pending;
    GpsFix? lastSent;
    final sinceEmit = Stopwatch();

    void emit(GpsFix fix) {
      lastSent = fix;
      sinceEmit
        ..reset()
        ..start();
      controller.add(fix);
    }

    void flush() {
      flushTimer = null;
      final position = pending;
      if (position == null) return;
      pending = null;
      emit(_toFix(position));
    }

    controller.onListen = () {
      positionSub = Geolocator.getPositionStream(
        locationSettings: _locationSettings(minInterval),
      ).listen(
        (position) {
          pending = position;
          final elapsed = sinceEmit.elapsed;
          if (!sinceEmit.isRunning || elapsed >= minInterval) {
            flushTimer?.cancel();
            flush();
          } else {
            flushTimer ??= Timer(minInterval - elapsed, flush);
          }
        },
        onError: controller.addError,
      );
      keepAliveTimer = Timer.periodic(_keepAlive, (_) {
        final fix = lastSent;
        if (fix != null && sinceEmit.elapsed >= _keepAlive) {
          emit(fix);
        }
      });
    };

    Future<void> stop() async {
      flushTimer?.cancel();
      flushTimer = null;
      keepAliveTimer?.cancel();
      keepAliveTimer = null;
      await positionSub?.cancel();
      positionSub = null;
    }

    controller.onCancel = stop;
    return controller.stream;
  }

  @override
  Future<GpsFix?> current() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return _toFix(position);
  }

  LocationSettings _locationSettings(Duration interval) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        intervalDuration: interval,
      );
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(accuracy: LocationAccuracy.high);
    }
    return const LocationSettings(accuracy: LocationAccuracy.high);
  }

  GpsFix _toFix(Position position) => GpsFix(
        latitude: position.latitude,
        longitude: position.longitude,
        heading: position.heading,
        speed: position.speed,
        altitude: position.altitude,
        accuracy: position.accuracy,
      );
}
