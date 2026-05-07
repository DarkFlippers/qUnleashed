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
    if (channel != FirmwareChannel.release &&
        channel != FirmwareChannel.development) {
      return null;
    }

    final suffix = variant == UnleashedVariant.compact ? 'c' : 'e';
    return FirmwareFile(
      url: _buildVariantUrl(base.url, suffix),
      target: base.target,
      type: base.type,
      sha256: '',
    );
  }

  List<FirmwareDirectoryChannel> getAvailableChannels() =>
      (cached?.channels ?? []).where((c) => c.versions.isNotEmpty).toList();

  String? getDisplayVersion(
    String channelId, {
    String target = 'f7',
    UnleashedVariant variant = UnleashedVariant.base,
  }) {
    final file = getUpdatePackage(channelId, target: target, variant: variant);
    if (file == null) return null;
    return _extractVersionFromUrl(file.url);
  }

  static String _buildVariantUrl(String baseUrl, String suffix) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return baseUrl;

    final segments = uri.pathSegments.toList();
    if (segments.isEmpty) return baseUrl;

    final fileName = segments.removeLast();
    final match = RegExp(r'^(flipper-z-[^-]+-update-[^.]+)(\.tgz)$').firstMatch(fileName);
    if (match == null) return baseUrl;

    final variantFileName = '${match.group(1)}$suffix${match.group(2)}';
    return uri.replace(
      pathSegments: <String>[
        'fw_extra_apps',
        variantFileName,
      ],
    ).toString();
  }

  static String? _extractVersionFromUrl(String url) {
    final fileName = Uri.tryParse(url)?.pathSegments.last ?? url.split('/').last;
    final match = RegExp(r'^flipper-z-[^-]+-update-([^.]+)\.tgz$').firstMatch(fileName);
    return match?.group(1);
  }
}
