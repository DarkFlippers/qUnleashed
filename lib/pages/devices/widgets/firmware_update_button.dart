import 'package:file_picker/file_picker.dart';
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../config.dart';
import '../../../theme/theme.dart';
import '../../../widgets/notification.dart';
import '../../../widgets/progress_button.dart';
import '../firmware/directory.dart';
import '../firmware/installer.dart';
import '../firmware/matcher.dart';
import '../firmware/source.dart';
import '../firmware/update_state.dart';

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
  UpdateState? _updateState;
  String? _inlineMessage;

  Color get _activeColor => widget.entry.colors.primary;
  Color get _inactiveColor => FlipperOriginalColors.text16;

  bool get _isCustom => widget.selectedChannelId == kCustomFirmwareChannelId;

  InstallAction _installAction() => FirmwareMatcher(
    entry: widget.entry,
    latestVersion: widget.latestVersion,
    deviceVersion: widget.deviceVersion,
    deviceInfo: widget.deviceInfo,
    selectedChannelId: widget.selectedChannelId,
    selectedVariant: widget.selectedVariant,
  ).resolve();

  bool get _inProgress {
    final state = _updateState;
    return state is UpdateFetching ||
        state is UpdateDownloading ||
        state is UpdateUploading ||
        state is UpdateStarting;
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

  Future<void> _onPressed() async {
    if (_inProgress) return;

    if (!widget.client.isConnected) {
      setState(() => _inlineMessage = 'Connect a Flipper first');
      return;
    }

    final FirmwareSource source;
    if (_isCustom) {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select firmware archive',
        type: FileType.custom,
        allowedExtensions: const ['tgz', 'gz', 'tar'],
      );
      final picked = result?.files.single.path;
      if (picked == null) return;
      source = LocalFirmwareSource(picked);
    } else {
      source = RemoteFirmwareSource(
        entry: widget.entry,
        channelId: widget.selectedChannelId,
        target: 'f7',
        variant: widget.selectedVariant,
      );
    }

    setState(() {
      _inlineMessage = null;
      _updateState = source.isRemote
          ? const UpdateFetching()
          : const UpdateUploading(0);
    });

    try {
      await FirmwareInstaller.install(
        source: source,
        client: widget.client,
        onState: _onState,
      );
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

  void _onState(UpdateState state) {
    if (!mounted) return;
    setState(() {
      _updateState = state;
      if (state is! UpdateError) _inlineMessage = null;
    });
    if (state is UpdateError) {
      QNotification.show(
        context,
        message: 'Firmware update failed: ${state.message}',
        type: QNotificationType.error,
        duration: const Duration(seconds: 6),
      );
    }
  }

  _ResolvedButtonState _resolve() {
    final state = _updateState;
    if (state != null && state is! UpdateIdle) {
      return _resolveUpdateState(state);
    }
    return _baseState();
  }

  _ResolvedButtonState _baseState() {
    final description = _inlineMessage;

    if (!widget.client.isConnected) {
      return _ResolvedButtonState(
        label: 'NO CONNECTION',
        color: _inactiveColor,
        description: description ?? 'Connect a Flipper to install firmware',
        enabled: false,
      );
    }

    if (_isCustom) {
      return _ResolvedButtonState(
        label: 'INSTALL',
        color: _activeColor,
        description:
            description ?? 'Pick a local update .tgz archive to install',
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

    return switch (_installAction()) {
      InstallAction.noUpdate => _ResolvedButtonState(
        label: 'NO UPDATE',
        color: _inactiveColor,
        description:
            description ??
            'Installed firmware already matches the selected build',
        enabled: false,
      ),
      InstallAction.update => _ResolvedButtonState(
        label: 'UPDATE',
        color: _activeColor,
        description:
            description ??
            'A newer version is available in the selected channel',
        enabled: true,
      ),
      InstallAction.install => _ResolvedButtonState(
        label: 'INSTALL',
        color: _activeColor,
        description:
            description ??
            'Selected firmware differs by type, channel, or build',
        enabled: true,
      ),
    };
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
        label: _installAction() == InstallAction.update ? 'UPDATE' : 'INSTALL',
        color: _activeColor,
        description: message,
        enabled: true,
      ),
      UpdateIdle() => _baseState(),
    };
  }

  _ProgressVisual? _progressFor(_ResolvedButtonState state) {
    return switch (_updateState) {
      UpdateFetching() => _ProgressVisual(value: null, color: state.color),
      UpdateDownloading(:final progress) => _ProgressVisual(
        value: progress,
        color: state.color,
      ),
      UpdateUploading(:final progress) => _ProgressVisual(
        value: progress,
        color: state.color,
      ),
      UpdateStarting() => _ProgressVisual(value: null, color: state.color),
      UpdateDone() => _ProgressVisual(value: 1, color: state.color),
      _ => null,
    };
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
  const _ProgressVisual({required this.value, required this.color});

  final double? value;
  final Color color;
}
