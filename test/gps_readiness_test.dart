// What `ensureReady` does with a platform that has the plugin and still
// cannot answer.
//
// Windows 8.1 raises `PlatformException(UNKNOWN_ERROR, RequestAccess failed.
// Check the Geolocation Service is running.)` out of `checkPermission` when
// that service is stopped - and it does so *after* `isLocationServiceEnabled`
// has already returned true, so no earlier branch catches it. The throw
// escaped `ensureReady`, and the desktop pre-warm at startup runs it through
// `guarded`, which filed every one as a failed ambient service.
// QUNLEASHED-B.
//
// The on-demand caller never saw it: `GpsResponder._ensureReady` already
// turns any throw into `GpsReadiness.unknown`. So the fix returns that same
// readiness rather than throwing, and what the Flipper is told is unchanged.
//
// Driven through the method channel rather than by swapping
// `GeolocatorPlatform.instance`: the default instance *is*
// `MethodChannelGeolocator`, so this exercises the real plugin path, and it
// keeps the test off two packages this app does not depend on directly.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/rpc/gps/geolocator_gps_provider.dart';
import 'package:qunleashed/services/rpc/gps/gps_responder.dart';

import 'kept_lines.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);
  setUp(clearKeptLines);

  const channel = MethodChannel('flutter.baseflow.com/geolocator');

  /// Answers the two calls `ensureReady` makes, with [onCheckPermission]
  /// either returning a permission index or throwing.
  void mockGeolocator({
    required bool serviceEnabled,
    required Object? Function() onCheckPermission,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'isLocationServiceEnabled':
              return serviceEnabled;
            case 'checkPermission':
              return onCheckPermission();
          }
          return null;
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a platform that cannot answer is a readiness, not a throw', () async {
    mockGeolocator(
      serviceEnabled: true,
      onCheckPermission: () => throw PlatformException(
        code: 'UNKNOWN_ERROR',
        message:
            'RequestAccess failed. Check the Geolocation Service is running.',
      ),
    );

    // The assertion is that this returns at all. Before the fix it threw, and
    // that throw is what the startup pre-warm reported.
    expect(await GeolocatorGpsProvider().ensureReady(), GpsReadiness.unknown);
  });

  // Kept rather than swallowed: it is the difference between a machine that
  // cannot do GPS and one that can. At `caught`, because nothing has been
  // asked for yet, so there is nobody to alert.
  test('and the reason is kept', () async {
    mockGeolocator(
      serviceEnabled: true,
      onCheckPermission: () => throw PlatformException(
        code: 'UNKNOWN_ERROR',
        message: 'RequestAccess failed.',
      ),
    );

    await GeolocatorGpsProvider().ensureReady();

    expect(keptLines.single, contains('[GPS] readiness unavailable'));
    expect(keptLines.single, contains('RequestAccess failed'));
  });

  // A control: the branch above still decides first, so a location service
  // the platform does report as off reaches the answer that names it, and
  // records nothing.
  test('a service the platform says is off is still disabled', () async {
    mockGeolocator(serviceEnabled: false, onCheckPermission: () => 0);

    expect(await GeolocatorGpsProvider().ensureReady(), GpsReadiness.disabled);
    expect(keptLines, isEmpty);
  });
}
