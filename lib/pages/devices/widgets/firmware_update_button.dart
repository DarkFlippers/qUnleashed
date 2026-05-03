import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../models/firmware_config.dart';
import '../../../models/firmware_directory.dart';
import '../../../models/firmware_updater.dart';
import '../../../theme.dart';

const _kFlipperButtonText = TextStyle(
  fontFamily: 'FlipperBold',
  fontSize: 40,
  fontWeight: FontWeight.w500,
);

class FirmwareUpdateButton extends StatefulWidget {
  const FirmwareUpdateButton({
    super.key,
    required this.entry,
    required this.fetchLoading,
    required this.latestVersion,
    required this.deviceVersion,
    required this.selectedChannelId,
    required this.selectedVariant,
    required this.client,
  });

  final FirmwareEntry entry;
  final bool fetchLoading;
  final String? latestVersion;
  final String? deviceVersion;
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

  _ResolvedButtonState _baseState() {
    if (widget.fetchLoading) {
      return _ResolvedButtonState(
        label: 'INSTALL',
        color: FlipperOriginalColors.accent,
        description: 'Checking for updates…',
        enabled: false,
      );
    }

    if (widget.latestVersion == null) {
      return _ResolvedButtonState(
        label: 'INSTALL',
        color: FlipperOriginalColors.accent,
        description: 'Can\'t connect to update server',
        enabled: false,
      );
    }

    final descriptionOverride = _inlineMessage;

    if (widget.deviceVersion == null) {
      return _ResolvedButtonState(
        label: 'INSTALL',
        color: FlipperOriginalColors.accent,
        description: descriptionOverride ??
            'Firmware on Flipper doesn\'t match the selected update channel.\nSelected version will be installed.',
        enabled: true,
      );
    }

    if (widget.deviceVersion == '-') {
      return _ResolvedButtonState(
        label: 'INSTALL',
        color: FlipperOriginalColors.accent,
        description: 'Checking device firmware version…',
        enabled: false,
      );
    }

    final match = _matchSelectedFirmware();
    if (match == _SelectedFirmwareMatch.exact) {
      return _ResolvedButtonState(
        label: 'NO UPDATES',
        color: FlipperOriginalColors.text16,
        description: 'There are no updates in the selected channel',
        enabled: false,
      );
    }

    if (match == _SelectedFirmwareMatch.versionOnly) {
      return _ResolvedButtonState(
        label: 'INSTALL',
        color: FlipperOriginalColors.accent,
        description: descriptionOverride ??
            'Firmware version matches, but the selected modification is different.\nSelected firmware will be installed.',
        enabled: true,
      );
    }

    return _ResolvedButtonState(
      label: 'UPDATE',
      color: FlipperOriginalColors.green,
      description: descriptionOverride ?? 'Update Flipper to the latest version',
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

    setState(() {
      _inlineMessage = null;
      _updateState = const UpdateFetching();
    });

    try {
      await FirmwareUpdater.install(
        entry: widget.entry,
        channelId: widget.selectedChannelId,
        variant: widget.selectedVariant,
        client: widget.client,
        onState: (state) {
          if (!mounted) return;
          setState(() {
            _updateState = state;
            if (state is! UpdateError) {
              _inlineMessage = null;
            }
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updateState = null;
        _inlineMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _resolve();
    final progress = _progressFor(state);
    final borderColor = state.color;
    final baseColor = progress == null
        ? state.color
        : state.color.withValues(alpha: _idleOpacity);
    final fillColor = progress?.color ?? borderColor;
    final progressValue = progress?.value?.clamp(0.0, 1.0) ?? 1.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          GestureDetector(
            onTap: state.enabled ? _onPressed : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                height: 50,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: baseColor,
                          border: Border.all(
                            color: borderColor,
                            width: 1.25,
                          ),
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                    ),
                    if (progress != null)
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: constraints.maxWidth * progressValue,
                                height: constraints.maxHeight,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: fillColor,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: borderColor,
                            width: 1.25,
                          ),
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Center(
                        child: Text(
                          state.label.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: _kFlipperButtonText.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
          color: FlipperOriginalColors.accent,
          description: 'Preparing firmware package…',
          enabled: false,
        ),
      UpdateDownloading() => _ResolvedButtonState(
          label: 'DOWNLOAD',
          color: FlipperOriginalColors.accent,
          description: 'Downloading firmware…',
          enabled: false,
        ),
      UpdateUploading() => _ResolvedButtonState(
          label: 'INSTALL',
          color: FlipperOriginalColors.green,
          description: 'Installing firmware on Flipper…',
          enabled: false,
        ),
      UpdateStarting() => _ResolvedButtonState(
          label: 'RUN INSTALLER',
          color: FlipperOriginalColors.green,
          description: 'Starting updater on Flipper…',
          enabled: false,
        ),
      UpdateDone() => _ResolvedButtonState(
          label: 'RUN INSTALLER',
          color: FlipperOriginalColors.green,
          description: 'Flipper will reboot and apply the update.',
          enabled: false,
        ),
      UpdateError(:final message) => _ResolvedButtonState(
          label: _matchSelectedFirmware() == _SelectedFirmwareMatch.noMatch ? 'UPDATE' : 'INSTALL',
          color: FlipperOriginalColors.accent,
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
      _ when state.description == 'Checking for updates…' => _ProgressVisual(
          value: null,
          color: state.color,
        ),
      _ => null,
    };
  }

  _SelectedFirmwareMatch _matchSelectedFirmware() {
    final installed = _parseInstalledFirmware();
    if (installed == null) return _SelectedFirmwareMatch.noMatch;

    if (installed.version != widget.latestVersion) {
      return _SelectedFirmwareMatch.noMatch;
    }

    if (widget.entry.shortName != 'unlshd') {
      return _SelectedFirmwareMatch.exact;
    }

    final installedVariant = installed.variant ?? UnleashedVariant.base;
    return installedVariant == widget.selectedVariant
        ? _SelectedFirmwareMatch.exact
        : _SelectedFirmwareMatch.versionOnly;
  }

  _InstalledFirmwareSelection? _parseInstalledFirmware() {
    final raw = widget.deviceVersion?.trim();
    final latest = widget.latestVersion?.trim();
    if (raw == null || raw.isEmpty || latest == null || latest.isEmpty) return null;

    if (widget.entry.shortName != 'unlshd') {
      return _InstalledFirmwareSelection(version: raw);
    }

    final normalized = raw.toLowerCase();
    final latestNormalized = latest.toLowerCase();
    if (!normalized.startsWith(latestNormalized)) {
      return _InstalledFirmwareSelection(version: raw);
    }

    final suffix = normalized.substring(latestNormalized.length);
    final variant = switch (suffix) {
      'c' => UnleashedVariant.compact,
      'e' => UnleashedVariant.extraPacks,
      '' => UnleashedVariant.base,
      _ => null,
    };
    return _InstalledFirmwareSelection(version: latest, variant: variant);
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

enum _SelectedFirmwareMatch {
  exact,
  versionOnly,
  noMatch,
}

class _InstalledFirmwareSelection {
  const _InstalledFirmwareSelection({
    required this.version,
    this.variant,
  });

  final String version;
  final UnleashedVariant? variant;
}
