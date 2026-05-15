import 'package:file_picker/file_picker.dart';
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../config.dart';
import '../../../widgets/notification.dart';
import '../../../widgets/progress_button.dart';
import '../models/firmware_directory.dart';
import '../models/firmware_updater.dart';
import '../../../theme.dart';

class FirmwareUpdateButton extends StatefulWidget {
  const FirmwareUpdateButton({
    super.key,
    required this.entry,
    required this.fetchLoading,
    required this.latestVersion,
    required this.deviceVersion,
    required this.deviceInfo,
    required this.selectedChannelId,
    required this.selectedVariant,
    required this.client,
  });

  final FirmwareEntry entry;
  final bool fetchLoading;
  final String? latestVersion;
  final String? deviceVersion;
  final Map<String, String> deviceInfo;
  final String selectedChannelId;
  final UnleashedVariant selectedVariant;
  final FlipperClient client;

  @override
  State<FirmwareUpdateButton> createState() => _FirmwareUpdateButtonState();
}

class _FirmwareUpdateButtonState extends State<FirmwareUpdateButton> {
  static const double _idleOpacity = 0.38;
  UpdateState? _updateState;
  String? _inlineMessage;

  Color get _activeColor => widget.entry.colors.primary;
  Color get _inactiveColor => FlipperOriginalColors.text16;

  bool get _isCustom => widget.selectedChannelId == kCustomFirmwareChannelId;

  _ResolvedButtonState _baseState() {
    final descriptionOverride = _inlineMessage;

    if (!widget.client.isConnected) {
      return _ResolvedButtonState(
        label: 'NO CONNECTION',
        color: _inactiveColor,
        description: descriptionOverride ?? 'Connect a Flipper to install firmware',
        enabled: false,
      );
    }

    if (_isCustom) {
      return _ResolvedButtonState(
        label: 'INSTALL',
        color: _activeColor,
        description: descriptionOverride ?? 'Pick a local update .tgz archive to install',
        enabled: true,
      );
    }

    if (widget.fetchLoading || widget.deviceVersion == '-') {
      return _ResolvedButtonState(
        label: 'CHECKING',
        color: _inactiveColor,
        description: 'Checking firmware status…',
        enabled: false,
      );
    }

    if (widget.latestVersion == null) {
      return _ResolvedButtonState(
        label: 'NO UPDATE',
        color: _inactiveColor,
        description: 'Can\'t connect to update server',
        enabled: false,
      );
    }

    final action = _resolveInstallAction();
    if (action == _InstallAction.noUpdate) {
      return _ResolvedButtonState(
        label: 'NO UPDATE',
        color: _inactiveColor,
        description: descriptionOverride ?? 'Installed firmware already matches the selected build',
        enabled: false,
      );
    }

    if (action == _InstallAction.update) {
      return _ResolvedButtonState(
        label: 'UPDATE',
        color: _activeColor,
        description: descriptionOverride ?? 'A newer version is available in the selected channel',
        enabled: true,
      );
    }

    return _ResolvedButtonState(
      label: 'INSTALL',
      color: _activeColor,
      description: descriptionOverride ?? 'Selected firmware differs by type, channel, or build',
      enabled: true,
    );
  }

  bool get _inProgress {
    final state = _updateState;
    return state is UpdateFetching ||
        state is UpdateDownloading ||
        state is UpdateUploading ||
        state is UpdateStarting;
  }

  Future<void> _onPressed() async {
    if (_inProgress) return;

    if (!widget.client.isConnected) {
      setState(() {
        _inlineMessage = 'Connect a Flipper first';
      });
      return;
    }

    String? localArchivePath;
    if (_isCustom) {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select firmware archive',
        type: FileType.custom,
        allowedExtensions: const ['tgz', 'gz', 'tar'],
      );
      final picked = result?.files.single.path;
      if (picked == null) return;
      localArchivePath = picked;
    }

    setState(() {
      _inlineMessage = null;
      _updateState = localArchivePath != null
          ? const UpdateUploading(0)
          : const UpdateFetching();
    });

    void onState(UpdateState state) {
      if (!mounted) return;
      setState(() {
        _updateState = state;
        if (state is! UpdateError) {
          _inlineMessage = null;
        }
      });
      if (state is UpdateError) {
        QNotification.show(
          context,
          message: 'Firmware update failed: ${state.message}',
          type: QNotificationType.error,
          duration: const Duration(seconds: 6),
        );
      } else if (state is UpdateDone) {
        QNotification.show(
          context,
          message: 'Update sent — Flipper will reboot to apply it',
          type: QNotificationType.good,
          duration: const Duration(seconds: 4),
        );
      }
    }

    try {
      if (localArchivePath != null) {
        await FirmwareUpdater.installLocal(
          archivePath: localArchivePath,
          client: widget.client,
          onState: onState,
        );
      } else {
        await FirmwareUpdater.install(
          entry: widget.entry,
          channelId: widget.selectedChannelId,
          variant: widget.selectedVariant,
          client: widget.client,
          onState: onState,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updateState = null;
        _inlineMessage = e.toString();
      });
      QNotification.show(
        context,
        message: 'Firmware update aborted: $e',
        type: QNotificationType.error,
        duration: const Duration(seconds: 6),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _resolve();
    final progress = _progressFor(state);
    final borderColor = state.color;
    final fillColor = progress?.color ?? borderColor;
    final isIndeterminate = progress != null && progress.value == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          ProgressButton(
            text: state.label.toUpperCase(),
            color: borderColor,
            progressColor: fillColor,
            progress: isIndeterminate ? null : progress?.value,
            indeterminate: isIndeterminate,
            onPressed: state.enabled ? _onPressed : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              state.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: FlipperOriginalColors.text30,
              ),
            ),
          ),
        ],
      ),
    );
  }

  _ResolvedButtonState _resolve() {
    final activeUpdateState = _updateState;
    if (activeUpdateState != null) {
      return _resolveUpdateState(activeUpdateState);
    }
    return _baseState();
  }

  _ResolvedButtonState _resolveUpdateState(UpdateState state) {
    return switch (state) {
      UpdateFetching() => _ResolvedButtonState(
          label: 'DOWNLOAD',
          color: _activeColor,
          description: 'Preparing firmware package…',
          enabled: false,
        ),
      UpdateDownloading() => _ResolvedButtonState(
          label: 'DOWNLOAD',
          color: _activeColor,
          description: 'Downloading firmware…',
          enabled: false,
        ),
      UpdateUploading() => _ResolvedButtonState(
          label: 'INSTALL',
          color: _activeColor,
          description: 'Installing firmware on Flipper…',
          enabled: false,
        ),
      UpdateStarting() => _ResolvedButtonState(
          label: 'RUN INSTALLER',
          color: _activeColor,
          description: 'Starting updater on Flipper…',
          enabled: false,
        ),
      UpdateDone() => _ResolvedButtonState(
          label: 'RUN INSTALLER',
          color: _activeColor,
          description: 'Flipper will reboot and apply the update.',
          enabled: false,
        ),
      UpdateError(:final message) => _ResolvedButtonState(
          label: _resolveInstallAction() == _InstallAction.update ? 'UPDATE' : 'INSTALL',
          color: _activeColor,
          description: message,
          enabled: true,
        ),
      UpdateIdle() => _baseState(),
    };
  }

  _ProgressVisual? _progressFor(_ResolvedButtonState state) {
    final updateState = _updateState;
    return switch (updateState) {
      UpdateFetching() => _ProgressVisual(
          value: null,
          color: state.color,
        ),
      UpdateDownloading(:final progress) => _ProgressVisual(
          value: progress,
          color: state.color,
        ),
      UpdateUploading(:final progress) => _ProgressVisual(
          value: progress,
          color: state.color,
        ),
      UpdateStarting() => _ProgressVisual(
          value: null,
          color: state.color,
        ),
      UpdateDone() => _ProgressVisual(
          value: 1,
          color: state.color,
        ),
      _ => null,
    };
  }

  _InstallAction _resolveInstallAction() {
    final latest = _buildSelectedFirmware();
    final installed = _parseInstalledFirmware();
    if (latest == null || installed == null) return _InstallAction.install;

    if (installed.type != latest.type) return _InstallAction.install;
    if (installed.channel != latest.channel) return _InstallAction.install;
    if (installed.variant != latest.variant) return _InstallAction.install;

    if (installed.version == latest.version) {
      return _InstallAction.noUpdate;
    }

    return _isIncrementalUpdate(installed.version, latest.version)
        ? _InstallAction.update
        : _InstallAction.install;
  }

  _SelectedFirmware? _buildSelectedFirmware() {
    final latestVersion = widget.latestVersion?.trim();
    final channel = FirmwareChannel.fromId(widget.selectedChannelId);
    if (latestVersion == null || latestVersion.isEmpty || channel == null) return null;

    final normalizedVersion = widget.entry.shortName == 'unlshd'
        ? _normalizeUnleashedVersion(latestVersion)
        : latestVersion;

    return _SelectedFirmware(
      type: widget.entry.shortName,
      channel: channel,
      version: normalizedVersion,
      variant: widget.entry.shortName == 'unlshd' ? widget.selectedVariant : null,
    );
  }

  _InstalledFirmware? _parseInstalledFirmware() {
    final raw = widget.deviceVersion?.trim();
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
      final value = widget.deviceInfo[key];
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

  _InstalledFirmware _parseInstalledUnleashed(String rawVersion, String? branchName) {
    final normalized = rawVersion.trim().toLowerCase();
    final releaseMatch = RegExp(r'((?:unlshd-\d+)|(?:\d+))([ce]?)').firstMatch(normalized);
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
    final split = rawVersion.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    final typeVersion = split.length >= 2 ? split[1] : rawVersion.trim();
    final channel = _detectOfwChannel(typeVersion, normalizedBranch);
    final version = switch (channel) {
      FirmwareChannel.development => split.isNotEmpty ? split.first : rawVersion.trim(),
      FirmwareChannel.releaseCandidate => typeVersion.replaceFirst(RegExp(r'-rc$', caseSensitive: false), ''),
      _ => typeVersion,
    };

    return _InstalledFirmware(
      type: 'ofw',
      channel: channel,
      version: version.trim(),
      variant: null,
    );
  }

  FirmwareChannel _detectUnleashedChannel(String rawVersion, String? branchName) {
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
    final match = RegExp(r'^((?:unlshd-\d+)|(?:\d+))(?:[ce])?$',
        caseSensitive: false).firstMatch(value.trim());
    return match?.group(1) ?? value.trim();
  }
}

class _ResolvedButtonState {
  const _ResolvedButtonState({
    required this.label,
    required this.color,
    required this.description,
    required this.enabled,
  });

  final String label;
  final Color color;
  final String description;
  final bool enabled;
}

class _ProgressVisual {
  const _ProgressVisual({
    required this.value,
    required this.color,
  });

  final double? value;
  final Color color;
}

enum _InstallAction {
  noUpdate,
  install,
  update,
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
