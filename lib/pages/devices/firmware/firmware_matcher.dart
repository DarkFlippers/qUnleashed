import '../../../config.dart';
import '../../../services/update/firmware_directory.dart';

enum InstallAction { noUpdate, install, update }

class FirmwareMatcher {
  const FirmwareMatcher({
    required this.entry,
    required this.latestVersion,
    required this.deviceVersion,
    required this.deviceInfo,
    required this.selectedChannelId,
    required this.selectedVariant,
  });

  final FirmwareEntry entry;
  final String? latestVersion;
  final String? deviceVersion;
  final Map<String, String> deviceInfo;
  final String selectedChannelId;
  final UnleashedVariant selectedVariant;

  InstallAction resolve() {
    final latest = _buildSelectedFirmware();
    final installed = _parseInstalledFirmware();
    if (latest == null || installed == null) return InstallAction.install;

    if (installed.type != latest.type) return InstallAction.install;
    if (installed.channel != latest.channel) return InstallAction.install;
    if (installed.variant != latest.variant) return InstallAction.install;

    if (installed.version == latest.version) {
      return InstallAction.noUpdate;
    }

    return _isIncrementalUpdate(installed.version, latest.version)
        ? InstallAction.update
        : InstallAction.install;
  }

  _SelectedFirmware? _buildSelectedFirmware() {
    final version = latestVersion?.trim();
    final channel = FirmwareChannel.fromId(selectedChannelId);
    if (version == null || version.isEmpty || channel == null) {
      return null;
    }

    final normalizedVersion = entry.shortName == 'unlshd'
        ? _normalizeUnleashedVersion(version)
        : version;

    return _SelectedFirmware(
      type: entry.shortName,
      channel: channel,
      version: normalizedVersion,
      variant: entry.shortName == 'unlshd' ? selectedVariant : null,
    );
  }

  _InstalledFirmware? _parseInstalledFirmware() {
    final raw = deviceVersion?.trim();
    if (raw == null || raw.isEmpty || raw == '-') return null;

    final originFork = _lookupInfo(const [
      'devinfo_firmware.origin.fork',
      'firmware.origin.fork',
      'firmware_origin_fork',
      'origin.fork',
      'origin_fork',
    ]);
    final branchName = _lookupInfo(const [
      'devinfo_firmware.branch.name',
      'firmware.branch.name',
      'firmware_branch_name',
      'branch.name',
      'branch_name',
    ]);

    if (_looksLikeUnleashed(raw, originFork)) {
      return _parseInstalledUnleashed(raw, branchName);
    }
    return _parseInstalledOfw(raw, branchName);
  }

  String? _lookupInfo(List<String> keys) {
    for (final key in keys) {
      final value = deviceInfo[key];
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  bool _looksLikeUnleashed(String rawVersion, String? originFork) {
    final normalizedVersion = rawVersion.toLowerCase();
    final normalizedOrigin = originFork?.toLowerCase() ?? '';
    return normalizedVersion.contains('unlshd') ||
        normalizedVersion.contains('unleashed') ||
        normalizedOrigin.contains('unleashed');
  }

  _InstalledFirmware _parseInstalledUnleashed(
    String rawVersion,
    String? branchName,
  ) {
    final normalized = rawVersion.trim().toLowerCase();
    final releaseMatch = RegExp(
      r'((?:unlshd-\d+)|(?:\d+))([ce]?)',
    ).firstMatch(normalized);
    final channel = _detectUnleashedChannel(normalized, branchName);
    if (releaseMatch != null) {
      final suffix = releaseMatch.group(2) ?? '';
      return _InstalledFirmware(
        type: 'unlshd',
        channel: channel,
        version: releaseMatch.group(1)!,
        variant: switch (suffix) {
          'c' => UnleashedVariant.compact,
          'e' => UnleashedVariant.extraPacks,
          _ => UnleashedVariant.base,
        },
      );
    }

    return _InstalledFirmware(
      type: 'unlshd',
      channel: channel,
      version: rawVersion.trim(),
      variant: UnleashedVariant.base,
    );
  }

  _InstalledFirmware _parseInstalledOfw(String rawVersion, String? branchName) {
    final normalizedBranch = branchName?.trim().toLowerCase();
    final split = rawVersion
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final typeVersion = split.length >= 2 ? split[1] : rawVersion.trim();
    final channel = _detectOfwChannel(typeVersion, normalizedBranch);
    final version = switch (channel) {
      FirmwareChannel.development =>
        split.isNotEmpty ? split.first : rawVersion.trim(),
      FirmwareChannel.releaseCandidate => typeVersion.replaceFirst(
        RegExp(r'-rc$', caseSensitive: false),
        '',
      ),
      _ => typeVersion,
    };

    return _InstalledFirmware(
      type: 'ofw',
      channel: channel,
      version: version.trim(),
      variant: null,
    );
  }

  FirmwareChannel _detectUnleashedChannel(
    String rawVersion,
    String? branchName,
  ) {
    final normalizedBranch = branchName?.trim().toLowerCase();
    if (normalizedBranch != null) {
      final branchChannel = FirmwareChannel.fromId(normalizedBranch);
      if (branchChannel != null) return branchChannel;
    }
    if (rawVersion.contains('unlshd-')) {
      return FirmwareChannel.release;
    }
    return FirmwareChannel.development;
  }

  FirmwareChannel _detectOfwChannel(String typeVersion, String? branchName) {
    final normalizedType = typeVersion.trim().toLowerCase();
    final normalizedBranch = branchName?.trim().toLowerCase();

    if (normalizedBranch == 'dev' || normalizedBranch == 'development') {
      return FirmwareChannel.development;
    }
    if (normalizedBranch == 'release-candidate' ||
        normalizedBranch == 'release_candidate' ||
        normalizedBranch == 'rc' ||
        normalizedBranch == 'candidate') {
      return FirmwareChannel.releaseCandidate;
    }
    if (RegExp(r'^\d+\.\d+\.\d+-rc').hasMatch(normalizedType)) {
      return FirmwareChannel.releaseCandidate;
    }
    if (RegExp(r'^\d+\.\d+\.\d+').hasMatch(normalizedType)) {
      return FirmwareChannel.release;
    }
    return FirmwareChannel.development;
  }

  bool _isIncrementalUpdate(String installedVersion, String latestVersion) {
    final installedParts = _numericParts(installedVersion);
    final latestParts = _numericParts(latestVersion);
    if (installedParts.isEmpty || latestParts.isEmpty) return false;

    final length = installedParts.length > latestParts.length
        ? installedParts.length
        : latestParts.length;
    for (var i = 0; i < length; i++) {
      final installed = i < installedParts.length ? installedParts[i] : 0;
      final latest = i < latestParts.length ? latestParts[i] : 0;
      if (latest > installed) return true;
      if (latest < installed) return false;
    }
    return false;
  }

  List<int> _numericParts(String value) => RegExp(r'\d+')
      .allMatches(value)
      .map((match) => int.tryParse(match.group(0) ?? '') ?? 0)
      .toList();

  String _normalizeUnleashedVersion(String value) {
    final match = RegExp(
      r'^((?:unlshd-\d+)|(?:\d+))(?:[ce])?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    return match?.group(1) ?? value.trim();
  }
}

class _InstalledFirmware {
  const _InstalledFirmware({
    required this.type,
    required this.channel,
    required this.version,
    this.variant,
  });

  final String type;
  final FirmwareChannel channel;
  final String version;
  final UnleashedVariant? variant;
}

class _SelectedFirmware {
  const _SelectedFirmware({
    required this.type,
    required this.channel,
    required this.version,
    this.variant,
  });

  final String type;
  final FirmwareChannel channel;
  final String version;
  final UnleashedVariant? variant;
}
