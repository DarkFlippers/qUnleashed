import 'package:flipperlib/flipperlib.dart' hide DateTime;

/// A [FlipperDevice] for a connection event to carry, and the discovery stub
/// it needs.
///
/// **Its own file, small on purpose.** Two files want one: `firmware_fixture`'s
/// `FakeFlipperClient.arriveWithDevice` (#413) and
/// `appbar_device_subtitle_test.dart`, where this started as `_Discovered`.
/// Putting it in `firmware_fixture.dart` would have made a test about an app
/// bar depend on the firmware directory feed and - since #413 - on
/// `archive_fakes.dart` behind it, with the archive controller, its storage
/// and a `path_provider` mock, for twelve lines. A second copy would drift
/// against a submodule signature instead. This is the third option.
class FakeDiscovered implements DiscoveredDevice {
  const FakeDiscovered(this.id);

  @override
  final String id;

  @override
  String get name => id;

  @override
  DeviceTransport get transport => DeviceTransport.usb;
}

/// A USB Flipper, identified by [id] and named [name].
FlipperDevice flipperDevice(String id, String name) => FlipperDevice(
  id: id,
  name: name,
  link: FlipperLink.usb,
  source: FakeDiscovered(id),
);
