import 'dart:async';
import 'dart:io';

import 'package:flipperlib/flipperlib.dart';
import 'package:geolocator/geolocator.dart';

/// [GpsLocationProvider] backed by the `geolocator` plugin. Streams the phone's
/// location to the Flipper at a fixed rate by emitting the latest known fix on
/// a periodic tick, decoupled from how often the OS delivers updates.
class GeolocatorGpsProvider implements GpsLocationProvider {
  @override
  bool get isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows;

  @override
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  @override
  Stream<GpsFix> watch(int frequencyHz) {
    final period = Duration(milliseconds: (1000 / frequencyHz).round());
    final controller = StreamController<GpsFix>();
    StreamSubscription<Position>? positionSub;
    Timer? ticker;
    Position? latest;

    controller.onListen = () {
      positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).listen(
        (position) => latest = position,
        onError: controller.addError,
      );
      ticker = Timer.periodic(period, (_) {
        final position = latest;
        if (position != null) controller.add(_toFix(position));
      });
    };

    Future<void> stop() async {
      ticker?.cancel();
      ticker = null;
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

  GpsFix _toFix(Position position) => GpsFix(
        latitude: position.latitude,
        longitude: position.longitude,
        heading: position.heading,
        speed: position.speed,
        altitude: position.altitude,
        accuracy: position.accuracy,
      );
}
