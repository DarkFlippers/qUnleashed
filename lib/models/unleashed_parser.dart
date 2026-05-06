import 'firmware_directory.dart';

class UnleashedParser extends FirmwareParser {
  UnleashedParser._();

  static final UnleashedParser instance = UnleashedParser._();

  @override
  String get directoryUrl => 'https://up.unleashedflip.com/directory.json';

  FirmwareFile? getUpdatePackage(
    String channelId, {
    String target = 'f7',
    UnleashedVariant variant = UnleashedVariant.base,
  }) {
    final base = getLatestVersionById(channelId)?.updatePackageFor(target);
    if (base == null) return null;

    final channel = FirmwareChannel.fromId(channelId);
    if (variant == UnleashedVariant.base) return base;
    if (channel != FirmwareChannel.release) return null;

    final version = getLatestVersionById(channelId)?.version;
    if (version == null || version.isEmpty) return null;
    final suffix = variant == UnleashedVariant.compact ? 'c' : 'e';
    return FirmwareFile(
      url: _buildReleaseVariantUrl(version, target, suffix),
      target: base.target,
      type: base.type,
      sha256: '',
    );
  }

  List<FirmwareDirectoryChannel> getAvailableChannels() =>
      (cached?.channels ?? []).where((c) => c.versions.isNotEmpty).toList();

  static String _buildReleaseVariantUrl(String version, String target, String suffix) =>
      'https://unleashedflip.com/fw_extra_apps/flipper-z-$target-update-$version$suffix.tgz';
}
