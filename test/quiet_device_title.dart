import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;

/// What a page title reads off the client, answered with "there is nothing
/// here", for fakes that are not about the title.
///
/// Every `QPageAppBar` carries a device line, and since ADR 0002 made its
/// client a parameter every fake handed to a page has to answer these - even
/// a fake testing CLI teardown or wrist input, which has no opinion about
/// what the title shows. Before that the title quietly used
/// `FlipperOneClient()`, so these tests were rendering a real client's answers
/// inside a tree that had nothing else real in it.
///
/// A class that mixes this in can still declare any of these itself; its own
/// member wins. `appbar_device_subtitle_test.dart` is the one that has
/// opinions, and it implements the lot rather than using this.
mixin QuietDeviceTitle implements FlipperClient {
  final _noEvents = StreamController<Never>.broadcast();

  @override
  FlipperDevice? get connectedDevice => null;

  @override
  bool get isConnected => false;

  @override
  String? getName() => null;

  /// Broadcast and never closed, rather than `Stream.empty()`: the title
  /// subscribes and holds the subscription for its life, and a stream that
  /// ends immediately would report `hasListener` false to any case that looks.
  @override
  Stream<FlipperConnectionState> get connectionStream => _noEvents.stream;

  @override
  Stream<Map<String, String>> get deviceInfoUpdates => _noEvents.stream;
}
