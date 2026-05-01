import 'firmware_directory.dart';

/// Parser for Unleashed firmware.
/// Directory: https://up.unleashedflip.com/directory.json
///
/// Channels:
///   - release           — stable
///   - release-candidate — upcoming release
///   - development       — latest dev builds
///
/// Build variants (identified by suffix in the file URL):
///   - base        — essential apps only (same set as OFW), no suffix
///   - extraPacks  — large list of pre-installed apps, suffix 'e'
///   - compact     — firmware only, no apps, suffix 'c'
class UnleashedParser extends FirmwareParser {
  UnleashedParser._();

  static final UnleashedParser instance = UnleashedParser._();

  @override
  String get directoryUrl => 'https://up.unleashedflip.com/directory.json';

  /// Returns update_tgz files for the given [channel] and [variant].
  ///
  /// The variant is detected from the file URL:
  ///   - compact:    URL contains 'c-f7' or version ends with 'c'
  ///   - extraPacks: URL contains 'e-f7' or version ends with 'e'
  ///   - base:       neither of the above
  List<FirmwareFile> getVariantFiles(FirmwareChannel channel, UnleashedVariant variant) {
    final files = getLatestVersion(channel)?.files ?? [];
    return files.where((f) => _matchesVariant(f, variant)).toList();
  }

  /// Returns the update_tgz file for the given [channel] and [variant], or null.
  FirmwareFile? getUpdatePackage(FirmwareChannel channel, UnleashedVariant variant) {
    final files = getVariantFiles(channel, variant);
    for (final f in files) {
      if (f.type == 'update_tgz') return f;
    }
    return null;
  }

  /// Returns available channels that have at least one version.
  List<FirmwareDirectoryChannel> getAvailableChannels() =>
      (cached?.channels ?? []).where((c) => c.versions.isNotEmpty).toList();

  bool _matchesVariant(FirmwareFile file, UnleashedVariant variant) {
    final name = file.fileName.toLowerCase();
    final isCompact = _isCompact(name);
    final isExtra = _isExtra(name);

    return switch (variant) {
      UnleashedVariant.compact => isCompact,
      UnleashedVariant.extraPacks => isExtra && !isCompact,
      UnleashedVariant.base => !isCompact && !isExtra,
    };
  }

  // Compact variant: filename has 'c' suffix before the target tag or before extension.
  // Examples: unlshd-086c-f7.tgz, update_unlshd-086c.tgz
  static bool _isCompact(String name) => RegExp(r'c[-_.]|c-f7').hasMatch(name);

  // Extra variant: filename has 'e' suffix before the target tag or before extension.
  // Examples: unlshd-086e-f7.tgz, update_unlshd-086e.tgz
  static bool _isExtra(String name) => RegExp(r'e[-_.]|e-f7').hasMatch(name);
}
