import 'package:flutter/material.dart';

import '../../../../components/icon.dart';
import '../../../../components/notification.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import 'media_remote.dart';
import 'models/models.dart';

Future<void> showMediaRemoteSettingsDialog(
  BuildContext context,
  MediaRemoteBridge bridge,
) async {
  await bridge.ensureLoaded();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final colors = context.appColors;

          Future<void> guard(Future<void> Function() operation) async {
            try {
              await operation();
            } catch (e) {
              if (context.mounted) {
                // Only setEnabled reaches the native side, and only it can
                // fail with the preference already saved - saying the save
                // failed there would contradict the switch, which the bridge
                // correctly leaves showing the stored intent for a later retry
                // to honour. Everything else here is a write that did not land.
                context.showNotification(
                  e is WristRemoteStartException
                      ? context.l10n.wristRemoteStartFailed('$e')
                      : context.l10n.remoteSaveFailed('$e'),
                  type: QNotificationType.error,
                );
              }
            }
            if (context.mounted) setState(() {});
          }

          Future<void> setEnabled(bool value) =>
              guard(() => bridge.setEnabled(value));

          Future<void> setMapping(
            MediaRemoteInput input,
            RemoteButton? button,
          ) => guard(() => bridge.setButtonFor(input, button));

          Future<void> setAction(
            MediaRemoteInput input,
            WristRemoteAction nextAction,
          ) => guard(() => bridge.setActionFor(input, nextAction));

          Future<void> reset() => guard(bridge.resetMappings);

          return AlertDialog(
            title: Text(context.l10n.wristRemoteMappingTitle),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.wristRemoteMappingIntro,
                      style: TextStyle(color: colors.dialogText),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.wristRemoteEnabledTitle,
                                style: TextStyle(
                                  color: colors.dialogText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context.l10n.wristRemoteEnabledSubtitle,
                                style: TextStyle(
                                  color: colors.dialogMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Switch(
                          value: bridge.enabled,
                          activeThumbColor: colors.accent,
                          onChanged: setEnabled,
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    for (final input in MediaRemoteInput.values) ...[
                      _MappingRow(
                        input: input,
                        value: bridge.buttonFor(input),
                        action: bridge.actionFor(input),
                        onChanged: (button) => setMapping(input, button),
                        onActionChanged: (nextAction) =>
                            setAction(input, nextAction),
                      ),
                      if (input != MediaRemoteInput.values.last)
                        const Divider(height: 20),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.wristRemoteHoldHelp,
                      style: TextStyle(color: colors.dialogMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.wristRemoteVolumeNote,
                      style: TextStyle(color: colors.dialogMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: reset,
                child: Text(context.l10n.wristRemoteResetDefaults),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.wristRemoteDone),
              ),
            ],
          );
        },
      );
    },
  );
}

class _MappingRow extends StatelessWidget {
  const _MappingRow({
    required this.input,
    required this.value,
    required this.action,
    required this.onChanged,
    required this.onActionChanged,
  });

  final MediaRemoteInput input;
  final RemoteButton? value;
  final WristRemoteAction action;
  final ValueChanged<RemoteButton?> onChanged;
  final ValueChanged<WristRemoteAction> onActionChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _inputIcon(input),
              size: _kGlyphSize,
              color: colors.dialogText,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _inputLabel(context, input),
                style: TextStyle(
                  color: colors.dialogText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButton<RemoteButton?>(
                isExpanded: true,
                value: value,
                onChanged: onChanged,
                items: [
                  // "Not assigned" goes through the same builder as the rest,
                  // so its label lines up with the icon rows by construction
                  // rather than by a spacer that has to be kept in step.
                  for (final button in <RemoteButton?>[
                    null,
                    ...RemoteButton.values,
                  ])
                    DropdownMenuItem<RemoteButton?>(
                      value: button,
                      child: _buttonEntry(context, button),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<WristRemoteAction>(
              value: action,
              onChanged: value == null
                  ? null
                  : (next) {
                      if (next != null) onActionChanged(next);
                    },
              items: [
                for (final candidate in WristRemoteAction.values)
                  DropdownMenuItem(
                    value: candidate,
                    child: Text(_actionLabel(context, candidate)),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// Glyphs stay out of the translated strings. Concatenating one onto an ARB
// value puts it outside what Crowdin sees, so a locale can neither reorder it
// nor drop it - and for the Flipper buttons the app already ships the real
// icons the remote itself uses.

String _inputLabel(BuildContext context, MediaRemoteInput input) =>
    switch (input) {
      MediaRemoteInput.previous => context.l10n.wristRemotePrevious,
      MediaRemoteInput.doublePrevious => context.l10n.wristRemoteDoublePrevious,
      MediaRemoteInput.playPause => context.l10n.wristRemotePlayPause,
      MediaRemoteInput.doublePlayPause =>
        context.l10n.wristRemoteDoublePlayPause,
      MediaRemoteInput.next => context.l10n.wristRemoteNext,
      MediaRemoteInput.doubleNext => context.l10n.wristRemoteDoubleNext,
      MediaRemoteInput.volumeUp => context.l10n.wristRemoteVolumeUp,
      MediaRemoteInput.volumeDown => context.l10n.wristRemoteVolumeDown,
    };

IconData _inputIcon(MediaRemoteInput input) => switch (input) {
  MediaRemoteInput.previous ||
  MediaRemoteInput.doublePrevious => Icons.skip_previous,
  MediaRemoteInput.playPause ||
  MediaRemoteInput.doublePlayPause => Icons.play_arrow,
  MediaRemoteInput.next || MediaRemoteInput.doubleNext => Icons.skip_next,
  MediaRemoteInput.volumeUp => Icons.volume_up,
  MediaRemoteInput.volumeDown => Icons.volume_down,
};

String _buttonLabel(BuildContext context, RemoteButton button) =>
    switch (button) {
      RemoteButton.up => context.l10n.wristRemoteButtonUp,
      RemoteButton.down => context.l10n.wristRemoteButtonDown,
      RemoteButton.left => context.l10n.wristRemoteButtonLeft,
      RemoteButton.right => context.l10n.wristRemoteButtonRight,
      RemoteButton.ok => context.l10n.commonOk,
      RemoteButton.back => context.l10n.remoteBack,
    };

/// One dropdown entry, with [button] null standing for "not assigned" so both
/// cases share a layout instead of agreeing on one.
Widget _buttonEntry(BuildContext context, RemoteButton? button) => Row(
  children: [
    SizedBox(
      width: _kGlyphSize,
      height: _kGlyphSize,
      // The same artwork the press animation and the keyboard hint legend use.
      child: button == null
          ? null
          : QIcon(
              asset: button.hintAsset,
              color: context.appColors.accent,
              size: _kGlyphSize,
            ),
    ),
    const SizedBox(width: 10),
    Expanded(
      child: Text(
        button == null
            ? context.l10n.wristRemoteNotAssigned
            : _buttonLabel(context, button),
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
);

const double _kGlyphSize = 18;

String _actionLabel(BuildContext context, WristRemoteAction action) =>
    switch (action) {
      WristRemoteAction.tap => context.l10n.wristRemoteTap,
      WristRemoteAction.hold1s => context.l10n.wristRemoteHoldSeconds(1),
      WristRemoteAction.hold2s => context.l10n.wristRemoteHoldSeconds(2),
      WristRemoteAction.hold3s => context.l10n.wristRemoteHoldSeconds(3),
    };
