import 'package:file_picker/file_picker.dart';
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../services/localization/l10n.dart';
import '../../../services/logging.dart';
import '../../../components/config.dart';
import '../../../theme/theme.dart';
import '../../../components/notification.dart';
import '../../../components/progress_button.dart';
import '../device_scope.dart';
import '../firmware/directory.dart';
import '../firmware/installer.dart';
import '../firmware/matcher.dart';
import '../firmware/source.dart';
import '../firmware/update_state.dart';

class FirmwareUpdateButton extends StatefulWidget {
  const FirmwareUpdateButton({
    super.key,
    required this.entry,
    required this.fetchState,
    required this.latestVersion,
    required this.deviceVersion,
    required this.deviceInfo,
    required this.selectedChannelId,
    required this.selectedVariant,
    required this.client,
    @visibleForTesting this.install,
  });

  final FirmwareEntry entry;

  /// What the firmware directory is doing. See [FirmwareFetchState].
  final FirmwareFetchState fetchState;

  final String? latestVersion;
  final String? deviceVersion;
  final Map<String, String> deviceInfo;
  final String selectedChannelId;
  final UnleashedVariant selectedVariant;
  final FlipperClient client;

  /// Stands in for [FirmwareInstaller.install].
  ///
  /// For tests, and a constructor argument rather than a static so nothing can
  /// replace the flasher process-wide: the widget under test gets its own and
  /// no other instance is touched. The state the failure path below exists to
  /// leave - `UpdateWaitingForReconnect` - is emitted only from the DFU
  /// recovery path, which runs a real flash over FFI, so there is no other way
  /// to reach it from a test.
  @visibleForTesting
  final Future<void> Function({
    required FirmwareSource source,
    required FlipperClient client,
    required void Function(UpdateState) onState,
  })?
  install;

  @override
  State<FirmwareUpdateButton> createState() => _FirmwareUpdateButtonState();
}

class _FirmwareUpdateButtonState extends State<FirmwareUpdateButton> {
  UpdateState? _updateState;
  String? _inlineMessage;

  bool _dfuPresent = false;

  late QAppColors _colors;

  Color get _activeColor => widget.entry.colors.primary;
  Color get _inactiveColor => _colors.textMuted;

  bool get _isCustom => widget.selectedChannelId == kCustomFirmwareChannelId;

  bool get _dfuOnly => !widget.client.isConnected && _dfuPresent;

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
        state is UpdateVerifying ||
        state is UpdateUploading ||
        state is UpdateStarting ||
        state is UpdateRecovering ||
        state is UpdateWaitingForReconnect;
  }

  @override
  Widget build(BuildContext context) {
    _colors = context.appColors;
    _dfuPresent = DeviceScope.of(context).dfuPresent;
    if (_updateState is UpdateWaitingForReconnect &&
        widget.client.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finishRecovery());
    }
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
            textStyle: ProgressButton.defaultTextStyle.copyWith(
              color: QAppColors.onColorFor(borderColor),
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
                color: _colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onPressed() async {
    if (_inProgress) return;

    if (!widget.client.isConnected && !_dfuPresent) {
      QNotification.show(
        context,
        message: l10n.fwuConnectFirst,
        type: QNotificationType.warning,
      );
      return;
    }

    final device = _dfuOnly ? DeviceScope.of(context) : null;

    final FirmwareSource source;
    if (_isCustom) {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: l10n.fwuPickArchiveTitle,
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

    device?.setRecovering(true);

    setState(() {
      _inlineMessage = null;
      _updateState = source.isRemote
          ? const UpdateFetching()
          : const UpdateUploading(0);
    });

    var waitForReconnect = false;
    try {
      await (widget.install ?? FirmwareInstaller.install)(
        source: source,
        client: widget.client,
        onState: _onState,
      );
      // The state decides this, not a prediction made at press time. It used
      // to be guarded on `_dfuOnly` read before the archive was fetched, but
      // install() picks the DFU path from client.isConnected much later - so a
      // link that dropped during a 90-second download flashed over DFU,
      // emitted UpdateWaitingForReconnect, and was then never waited for,
      // leaving the button disabled on RESTARTING for good. #118.
      //
      // Reading the last state install() emitted is safe only because
      // UpdateWaitingForReconnect is terminal: it is emitted from one place
      // and nothing follows it. Anything added after it there brings the latch
      // straight back, with these tests still green - #132 makes install()
      // return the state it ended on so this stops being an ordering
      // assumption.
      waitForReconnect = _updateState is UpdateWaitingForReconnect;
    } catch (e, st) {
      // FirmwareInstaller.install keeps its own failures, but the temp
      // directory it creates before that try is outside it - a full disk or an
      // unwritable temp path arrives here, and used to leave the log with
      // nothing while the user got a raw toString in a toast.
      LogService.error(
        '[Firmware] install aborted: ${LogService.describe(e, st)}',
      );
      if (!mounted) return;
      setState(() => _updateState = null);
      QNotification.show(
        context,
        message: l10n.fwuAborted('$e'),
        type: QNotificationType.error,
        duration: const Duration(seconds: 6),
      );
    } finally {
      device?.setRecovering(false);
    }

    if (waitForReconnect) {
      await _completeRecoveryOnReconnect();
    }
  }

  Future<void> _completeRecoveryOnReconnect() async {
    final returned = await FirmwareInstaller.awaitReconnect(widget.client);
    // Asked again rather than trusting the answer alone: build() carries a
    // post-frame _finishRecovery for a device that connects without this
    // noticing, so if that has already run, accusing the hardware here would
    // overwrite fwuRecovered with fwuRecoveryNoReconnect a frame later.
    if (returned || widget.client.isConnected) {
      _finishRecovery();
      return;
    }
    if (!mounted) return;
    // The transitional state has to go whatever the answer was. It renders as
    // a disabled RESTARTING button, so returning early and leaving it set - as
    // this did until #118 - is a button the user cannot press again for the
    // rest of the session, on the one path where trying again is the whole of
    // what they can do. Clearing it drops back to the base state, which says
    // what the device is actually doing and carries the message below in its
    // description slot.
    setState(() {
      _updateState = null;
      _inlineMessage = l10n.fwuRecoveryNoReconnect;
    });
    // The two other failures in this widget get a six-second red toast: an
    // aborted install in _onPressed, an UpdateError in _onState. A device that
    // was flashed and did not come back is the worst of the three, and it was
    // the only one reported in 12px muted grey.
    QNotification.show(
      context,
      message: l10n.fwuRecoveryNoReconnect,
      type: QNotificationType.error,
      duration: const Duration(seconds: 6),
    );
  }

  void _finishRecovery() {
    if (!mounted) return;
    setState(() {
      _updateState = null;
      _inlineMessage = l10n.fwuRecovered;
    });
  }

  void _onState(UpdateState state) {
    if (!mounted) return;
    setState(() {
      _updateState = state;
      _inlineMessage = null;
    });
    if (state is UpdateError) {
      QNotification.show(
        context,
        message: l10n.fwuFailed(state.message),
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

  /// Why there is no version to offer.
  ///
  /// A fetch that failed and a directory that simply carries nothing on this
  /// channel are different facts, and only the first can honestly say the
  /// server was not reached.
  String get _noVersionReason => widget.fetchState.hasFailed
      ? l10n.fwuDescCantCheck
      : l10n.fwuDescNoServer;

  _ResolvedButtonState _baseState() {
    final description = _inlineMessage;

    if (!widget.client.isConnected && !_dfuPresent) {
      return _ResolvedButtonState(
        label: l10n.fwuLabelNoConnection,
        color: _inactiveColor,
        description: description ?? l10n.fwuDescConnect,
        enabled: false,
      );
    }

    if (_isCustom) {
      return _ResolvedButtonState(
        label: l10n.fwuLabelInstall,
        color: _activeColor,
        description:
            description ??
            (_dfuOnly ? l10n.fwuDescPickDfu : l10n.fwuDescPickInstall),
        enabled: true,
      );
    }

    if (_dfuOnly) {
      if (widget.latestVersion == null) {
        return _ResolvedButtonState(
          label: l10n.fwuLabelNoFirmware,
          color: _inactiveColor,
          description: description ?? _noVersionReason,
          enabled: false,
        );
      }
      return _ResolvedButtonState(
        label: l10n.fwuLabelRepair,
        color: _activeColor,
        description: description ?? l10n.fwuDescDfuMode,
        enabled: true,
      );
    }

    if (widget.fetchState.isLoading || widget.deviceVersion == '-') {
      return _ResolvedButtonState(
        label: l10n.fwuLabelChecking,
        color: _inactiveColor,
        description: l10n.fwuDescChecking,
        enabled: false,
      );
    }

    if (widget.latestVersion == null) {
      // "NO UPDATE" is a claim about what the server answered. When the fetch
      // failed there was no answer, and saying it anyway tells someone with no
      // network that their firmware is current - which is the one thing nobody
      // here knows. #118.
      return _ResolvedButtonState(
        label: widget.fetchState.hasFailed
            ? l10n.fwuLabelCantCheck
            : l10n.fwuLabelNoUpdate,
        color: _inactiveColor,
        description: description ?? _noVersionReason,
        enabled: false,
      );
    }

    return switch (_installAction()) {
      InstallAction.noUpdate => _ResolvedButtonState(
        label: l10n.fwuLabelNoUpdate,
        color: _inactiveColor,
        // A refresh that failed leaves the previous directory standing, so
        // the comparison behind "up to date" was made against whatever was
        // last fetched - which may be arbitrarily old. The other branch of
        // this reads fwuLabelCantCheck for the same reason; here there is a
        // version to show, so only the explanation changes.
        description:
            description ??
            (widget.fetchState.hasFailed
                ? l10n.fwuDescCantCheck
                : l10n.fwuDescUpToDate),
        enabled: false,
      ),
      InstallAction.update => _ResolvedButtonState(
        label: l10n.fwuLabelUpdate,
        color: _activeColor,
        description: description ?? l10n.fwuDescNewer,
        enabled: true,
      ),
      InstallAction.install => _ResolvedButtonState(
        label: l10n.fwuLabelInstall,
        color: _activeColor,
        description: description ?? l10n.fwuDescDiffers,
        enabled: true,
      ),
    };
  }

  _ResolvedButtonState _resolveUpdateState(UpdateState state) {
    return switch (state) {
      UpdateFetching() => _ResolvedButtonState(
        label: l10n.fwuLabelDownload,
        color: _activeColor,
        description: l10n.fwuDescPreparing,
        enabled: false,
      ),
      UpdateDownloading() => _ResolvedButtonState(
        label: l10n.fwuLabelDownload,
        color: _activeColor,
        description: l10n.fwuDescDownloading,
        enabled: false,
      ),
      UpdateVerifying(:final fileIndex, :final fileCount) =>
        _ResolvedButtonState(
          label: l10n.fwuLabelChecking,
          color: _activeColor,
          description: fileCount == 0
              ? l10n.fwuDescCheckingFiles
              : l10n.fwuDescCheckingFilesCount(fileIndex, fileCount),
          enabled: false,
        ),
      UpdateUploading(:final fileIndex, :final fileCount) =>
        _ResolvedButtonState(
          label: l10n.fwuLabelInstalling,
          color: _activeColor,
          description: fileCount == 0
              ? l10n.fwuDescInstalling
              : l10n.fwuDescInstallingCount(fileIndex, fileCount),
          enabled: false,
        ),
      UpdateStarting() => _ResolvedButtonState(
        label: l10n.fwuLabelRunInstaller,
        color: _activeColor,
        description: l10n.fwuDescStartingUpdater,
        enabled: false,
      ),
      UpdateRecovering(:final step, :final progress) => _ResolvedButtonState(
        label: _recoveryLabel(step),
        color: _activeColor,
        description: _recoveryDescription(step, progress),
        enabled: false,
      ),
      UpdateWaitingForReconnect() => _ResolvedButtonState(
        label: l10n.fwuLabelRestarting,
        color: _activeColor,
        description: l10n.fwuDescWaitingReconnect,
        enabled: false,
      ),
      UpdateDone() => _ResolvedButtonState(
        label: l10n.fwuLabelRunInstaller,
        color: _activeColor,
        description: l10n.fwuDescWillReboot,
        enabled: false,
      ),
      UpdateError() => _ResolvedButtonState(
        label: _installAction() == InstallAction.update
            ? l10n.fwuLabelUpdate
            : l10n.fwuLabelInstall,
        color: _activeColor,
        description: _baseState().description,
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
      UpdateVerifying(:final fileIndex, :final fileCount) => _ProgressVisual(
        value: fileCount == 0 ? null : fileIndex / fileCount,
        color: state.color,
      ),
      UpdateUploading(:final progress) => _ProgressVisual(
        value: progress,
        color: state.color,
      ),
      UpdateStarting() => _ProgressVisual(value: null, color: state.color),
      UpdateRecovering(:final step, :final progress) => _ProgressVisual(
        value: switch (step) {
          RecoveryStep.flashingRadio ||
          RecoveryStep.flashingFirmware => progress,
          _ => null,
        },
        color: state.color,
      ),
      UpdateWaitingForReconnect() => _ProgressVisual(
        value: null,
        color: state.color,
      ),
      UpdateDone() => _ProgressVisual(value: 1, color: state.color),
      _ => null,
    };
  }

  static String _recoveryLabel(RecoveryStep step) => switch (step) {
    RecoveryStep.settingBootMode => l10n.fwuLabelPreparing,
    RecoveryStep.flashingRadio => l10n.fwuLabelRadio,
    RecoveryStep.flashingFirmware => l10n.fwuLabelFirmware,
    RecoveryStep.correctingOptionBytes => l10n.fwuLabelFinalizing,
    RecoveryStep.restarting => l10n.fwuLabelRestarting,
  };

  static String _recoveryDescription(RecoveryStep step, double progress) {
    final percent = (progress * 100).round();
    return switch (step) {
      RecoveryStep.settingBootMode => l10n.fwuDescRecoveryPrepare,
      RecoveryStep.flashingRadio => l10n.fwuDescFlashingRadio(percent),
      RecoveryStep.flashingFirmware => l10n.fwuDescFlashingFirmware(percent),
      RecoveryStep.correctingOptionBytes => l10n.fwuDescRestoringOptionBytes,
      RecoveryStep.restarting => l10n.fwuDescRestarting,
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
