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
    if (variant == UnleashedVariant.base) return base;
    final suffix = variant == UnleashedVariant.compact ? 'c' : 'e';
    return FirmwareFile(
      url: _withVariantSuffix(base.url, suffix),
      target: base.target,
      type: base.type,
      sha256: '',
    );
  }

  List<FirmwareDirectoryChannel> getAvailableChannels() =>
      (cached?.channels ?? []).where((c) => c.versions.isNotEmpty).toList();

  static String _withVariantSuffix(String url, String suffix) {
    final re = RegExp(r'(.+-update-\d+)(\.tgz)$');
    final m = re.firstMatch(url);
    if (m == null) return url;
    return '${m.group(1)}$suffix${m.group(2)}';
  }
}
