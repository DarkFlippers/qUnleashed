import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flipperlib/flipperlib.dart';
import 'package:geolocator/geolocator.dart';

import 'gnss_satellites.dart';

class GeolocatorGpsProvider implements GpsLocationProvider {
  GeolocatorGpsProvider({GnssSatelliteSource? gnss})
      : _gnss = gnss ?? GnssSatelliteSource();

  static const Duration _gnssPollInterval = Duration(seconds: 2);

  final GnssSatelliteSource _gnss;

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
    final controller = StreamController<GpsFix>();
    StreamSubscription<Position>? positionSub;
    Timer? gnssTimer;

    controller.onListen = () {
      unawaited(_gnss.start());
      gnssTimer =
          Timer.periodic(_gnssPollInterval, (_) => unawaited(_gnss.poll()));
      positionSub = Geolocator.getPositionStream(
        locationSettings: _locationSettings(frequencyHz),
      ).listen(
        (position) => controller.add(_toFix(position)),
        onError: controller.addError,
      );
    };

    controller.onCancel = () async {
      gnssTimer?.cancel();
      gnssTimer = null;
      await positionSub?.cancel();
      positionSub = null;
      await _gnss.stop();
    };

    return controller.stream;
  }

  @override
  Future<GpsFix?> current() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return _toFix(position);
  }

  LocationSettings _locationSettings(int frequencyHz) {
    const accuracy = LocationAccuracy.high;
    final interval = frequencyHz > 0
        ? Duration(milliseconds: (1000 / frequencyHz).round())
        : null;
    if (Platform.isAndroid) {
      return AndroidSettings(accuracy: accuracy, intervalDuration: interval);
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(accuracy: accuracy);
    }
    return const LocationSettings(accuracy: accuracy);
  }

  GpsFix _toFix(Position position) => GpsFix(
        latitude: position.latitude,
        longitude: position.longitude,
        heading: position.heading,
        speed: position.speed,
        altitude: position.altitude,
        accuracy: position.accuracy,
        satellites: resolveSatellites(
          accuracy: position.accuracy,
          realCount: _gnss.cached,
        ),
      );
}
