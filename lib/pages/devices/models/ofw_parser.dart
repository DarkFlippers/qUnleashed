import 'firmware_directory.dart';

/// Parser for Official Flipper Zero firmware.
/// Directory: https://update.flipperzero.one/firmware/directory.json
///
/// Channels:
///   - release           — stable, tested by QA
///   - release-candidate — upcoming release, undergoing QA
///   - development       — latest builds, not QA-tested
class OfwParser extends FirmwareParser {
  OfwParser._();

  static final OfwParser instance = OfwParser._();

  @override
  String get directoryUrl => 'https://update.flipperzero.one/firmware/directory.json';

  /// Returns the update package (.tgz) for the given channel.
  FirmwareFile? getUpdatePackage(String channelId) =>
      getLatestVersionById(channelId)?.updatePackage;

  /// Returns all available channels that have at least one version.
  List<FirmwareDirectoryChannel> getAvailableChannels() =>
      (cached?.channels ?? []).where((c) => c.versions.isNotEmpty).toList();
}
