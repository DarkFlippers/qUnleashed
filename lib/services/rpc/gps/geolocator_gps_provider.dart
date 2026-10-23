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
    } on PlatformException catch (e, st) {
      // An error this layer cannot interpret, so it answers the readiness
      // that means exactly that - from any of the platform calls above, not
      // only `checkPermission`.
      //
      // What makes that safe rather than a shrug is the carve-out:
      // `MethodChannelGeolocator` converts every code it recognises into a
      // typed exception, none of which is a `PlatformException`, so the one
      // failure here that is *our* bug - a missing capability, arriving as
      // `PermissionDefinitionsNotFoundException` - keeps escaping to be
      // reported. That rests on the package's type hierarchy, so
      // `gps_readiness_test.dart` pins it against the real channel.
      //
      // A readiness and not a throw, because the Flipper is told the same
      // either way: `FlipperGpsResponder._ensureReady` already mapped any
      // throw to this. What changes is the desktop pre-warm, which ran this
      // through `guarded` and so filed an issue and an error log on every
      // launch. QUNLEASHED-B, where Windows raised `UNKNOWN_ERROR` with the
      // plugin's hard-coded `RequestAccess failed. Check the Geolocation
      // Service is running.` - not a finding, just what it prints for
      // anything it cannot identify, on a machine whose service read had
      // already said yes one line earlier.
      //
      // `caught` rather than `warn` for the reason the budget file holds.
      // `describe` like the permission probes that absorb the same shape:
      // the trace is what names which of the awaited platform calls threw,
      // and it appends only when there is one.
      LogService.caught(
        '[GPS] readiness unavailable on this platform: '
        '${LogService.describe(e, st)}',
      );
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
