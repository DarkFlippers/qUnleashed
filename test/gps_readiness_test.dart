// What `ensureReady` does with a platform error, and which ones it refuses
// to absorb.
//
// QUNLEASHED-B: a Windows session where `RequestAccessAsync` raised
// `UNKNOWN_ERROR` carrying the plugin's hard-coded `RequestAccess failed.
// Check the Geolocation Service is running.` It escaped `ensureReady`, and
// the desktop pre-warm runs that through `guarded`, so it filed a failed
// ambient service on every launch. The on-demand caller never showed it:
// `FlipperGpsResponder._ensureReady` already maps any throw to
// `GpsReadiness.unknown`.
//
// The boundary matters as much as the fix. `MethodChannelGeolocator` turns
// every code it recognises into a typed exception, none of which is a
// `PlatformException` - so the clause can only absorb errors the platform
// could not classify, and the one that means *our* bug
// (`PERMISSION_DEFINITIONS_NOT_FOUND`, a missing capability) still escapes.
// The cases below pin both halves.
//
// Driven through `MethodChannel('flutter.baseflow.com/geolocator')` rather
// than by swapping `GeolocatorPlatform.instance`: that is the channel the
// shipping Windows plugin itself registers, so the codec round-trip that
// rebuilds the `PlatformException` is exercised too. CI runs on Linux, where
// geolocator has no implementation, so the default instance stands.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/rpc/gps/geolocator_gps_provider.dart';
import 'package:qunleashed/services/rpc/gps/gps_responder.dart';

import 'kept_lines.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  const channel = MethodChannel('flutter.baseflow.com/geolocator');

  /// Answers the calls the cases below reach. `requestPermission` is reached
  /// only when `checkPermission` answers `denied`.
  ///
  /// An unmocked method throws `MissingPluginException` rather than returning
  /// null. Null would come back through the plugin as a decode `TypeError`,
  /// and a bare `fail()` would be worse still: the binding wraps a thrown
  /// error into `PlatformException(code: 'error')`, which is exactly what
  /// production now absorbs - a test passing on a failure the harness
  /// manufactured.
  void mockGeolocator({
    bool serviceEnabled = true,
    Object? Function()? onCheckPermission,
    Object? Function()? onRequestPermission,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'isLocationServiceEnabled':
              return serviceEnabled;
            case 'checkPermission':
              if (onCheckPermission != null) return onCheckPermission();
            case 'requestPermission':
              if (onRequestPermission != null) return onRequestPermission();
          }
          throw MissingPluginException('no mock for ${call.method}');
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // Returning at all is half the assertion: before the fix this threw, and
  // that throw is what the pre-warm reported.
  test('an error the platform could not classify is a readiness', () async {
    mockGeolocator(
      onCheckPermission: () => throw PlatformException(
        code: 'UNKNOWN_ERROR',
        message:
            'RequestAccess failed. Check the Geolocation Service is running.',
      ),
    );

    expect(await GeolocatorGpsProvider().ensureReady(), GpsReadiness.unknown);

    // The level is the whole argument of the change, so it is asserted and
    // not merely described: `keptLines` carries a prefix that `warn` would
    // satisfy just as well.
    expect(keptLevels, [KeptLevel.caught]);
    expect(keptLines.single, contains('[GPS] readiness unavailable'));
    expect(keptLines.single, contains('UNKNOWN_ERROR'));
  });

  // The other arm of the same Windows function. `RequestAccessAsync` has two
  // catches: the one above, and `catch (const std::exception&)`, which sends
  // `PERMISSION_DEFINITIONS_NOT_FOUND`. That is a missing capability or
  // manifest entry - our bug - and the plugin types it so it can be told
  // apart. It must keep escaping, or the clause above would be absorbing the
  // one failure here that somebody could act on.
  test('a failure the platform did classify still escapes', () async {
    mockGeolocator(
      onCheckPermission: () => throw PlatformException(
        code: 'PERMISSION_DEFINITIONS_NOT_FOUND',
        message: 'No location permissions are defined in the manifest.',
      ),
    );

    await expectLater(
      GeolocatorGpsProvider().ensureReady(),
      throwsA(isA<PermissionDefinitionsNotFoundException>()),
    );
    expect(keptLines, isEmpty, reason: 'it is reported where it is caught');
  });

  // A control: the branch above still decides first, so a location service
  // the platform does report as off reaches the answer that names it, and
  // records nothing. Without that last half, a desktop with location switched
  // off would keep a line at every launch.
  test('a service the platform says is off is still disabled', () async {
    mockGeolocator(serviceEnabled: false);

    expect(await GeolocatorGpsProvider().ensureReady(), GpsReadiness.disabled);
    expect(keptLines, isEmpty);
  });

  // Every Linux user takes this branch: geolocator ships no Linux
  // implementation at all, so the pre-warm reaches an unregistered channel.
  test('a platform with no implementation is notSupported', () async {
    expect(
      await GeolocatorGpsProvider().ensureReady(),
      GpsReadiness.notSupported,
    );
    expect(keptLines, isEmpty);
  });

  // The happy path and its neighbour, which nothing covered. They decide
  // whether the Flipper gets fixes at all, and inverting the `granted`
  // expression is otherwise a silent mutation.
  group('a permission the platform did answer', () {
    test('that allows it is ready', () async {
      mockGeolocator(onCheckPermission: () => 3);

      expect(await GeolocatorGpsProvider().ensureReady(), GpsReadiness.ready);
      expect(keptLines, isEmpty);
    });

    test('that refuses it is permissionDenied', () async {
      // 0 is `denied`, which sends it through `requestPermission`; 1 is
      // `deniedForever`, which is the answer that comes back.
      mockGeolocator(onCheckPermission: () => 0, onRequestPermission: () => 1);

      expect(
        await GeolocatorGpsProvider().ensureReady(),
        GpsReadiness.permissionDenied,
      );
      expect(keptLines, isEmpty);
    });
  });
}
