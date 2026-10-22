import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../guarded.dart';
import '../../logging.dart';
import 'gnss_satellites.dart';
import 'gps_responder.dart';

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
      if (Platform.isIOS && permission == LocationPermission.whileInUse) {
        permission = await _escalateToAlways();
      }
      final granted =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      return granted ? GpsReadiness.ready : GpsReadiness.permissionDenied;
    } on MissingPluginException {
      return GpsReadiness.notSupported;
    } on UnimplementedError {
      return GpsReadiness.notSupported;
    } on PlatformException catch (e) {
      // A platform that has the plugin and still cannot answer. Windows 8.1
      // raises `RequestAccess failed. Check the Geolocation Service is
      // running.` out of `checkPermission` when that service is stopped -
      // after `isLocationServiceEnabled` has already said yes, so there is no
      // earlier branch that could have caught it. QUNLEASHED-B.
      //
      // A readiness rather than a throw, because it is a fact about the
      // machine and not a fault. The one caller that asks on demand already
      // turned a throw into exactly this (`GpsResponder._ensureReady`), so
      // the Flipper still gets `ERROR_GPS_UNKNOWN` and nothing there changes.
      // What changes is the desktop pre-warm at startup, which goes through
      // `guarded` and so filed every one of these as a failed ambient
      // service.
      //
      // `caught` and not `warn`: it is worth keeping - it is the difference
      // between a machine that cannot do GPS and one that can - and there is
      // nobody to alert, because nothing was asked for yet.
      LogService.caught('[GPS] readiness unavailable on this platform: $e');
      return GpsReadiness.unknown;
    }
  }

  Future<LocationPermission> _escalateToAlways() async {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return LocationPermission.whileInUse;
    }
    try {
      await ph.Permission.locationAlways.request();
    } on PlatformException {
      return LocationPermission.whileInUse;
    } on MissingPluginException {
      return LocationPermission.whileInUse;
    }
    return Geolocator.checkPermission();
  }

  @override
  Stream<GpsFix> watch(int frequencyHz) {
    final controller = StreamController<GpsFix>();
    StreamSubscription<Position>? positionSub;
    Timer? gnssTimer;

    controller.onListen = () {
      unawaited(guarded('[GPS] start GNSS status', _gnss.start));
      gnssTimer = Timer.periodic(
        _gnssPollInterval,
        (_) => unawaited(guarded('[GPS] poll GNSS status', _gnss.poll)),
      );
      positionSub =
          Geolocator.getPositionStream(
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
      return AppleSettings(
        accuracy: accuracy,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
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
