import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../../theme.dart';
import '../gif_recorder.dart';
import 'action_button.dart';

class RemoteActionRow extends StatelessWidget {
  const RemoteActionRow({
    super.key,
    required this.isVertical,
    required this.gifState,
    required this.gifElapsedMs,
    required this.isLocked,
    required this.savingScreenshot,
    required this.onCopy,
    required this.onSave,
    required this.onUnlock,
    required this.onStartGif,
    required this.onPauseResumeGif,
    required this.onStopGif,
    required this.onCancelGif,
  });

  final bool isVertical;
  final GifRecordingState gifState;
  final int gifElapsedMs;
  final bool isLocked;
  final bool savingScreenshot;
  final AsyncCallback onCopy;
  final AsyncCallback onSave;
  final AsyncCallback? onUnlock;
  final VoidCallback onStartGif;
  final VoidCallback onPauseResumeGif;
  final AsyncCallback onStopGif;
  final VoidCallback onCancelGif;

  @override
  Widget build(BuildContext context) {
    if (gifState == GifRecordingState.recording ||
        gifState == GifRecordingState.paused) {
      return _RecordingControls(
        isVertical: isVertical,
        isPaused: gifState == GifRecordingState.paused,
        elapsedMs: gifElapsedMs,
        onPauseResume: onPauseResumeGif,
        onStop: onStopGif,
        onCancel: onCancelGif,
      );
    }

    return _IdleControls(
      isVertical: isVertical,
      isLocked: isLocked,
      savingScreenshot: savingScreenshot,
      gifBusy: gifState == GifRecordingState.encoding,
      onCopy: onCopy,
      onSave: onSave,
      onUnlock: onUnlock,
      onStartGif: onStartGif,
    );
  }
}

class _IdleControls extends StatelessWidget {
  const _IdleControls({
    required this.isVertical,
    required this.isLocked,
    required this.savingScreenshot,
    required this.gifBusy,
    required this.onCopy,
    required this.onSave,
    required this.onUnlock,
    required this.onStartGif,
  });

  final bool isVertical;
  final bool isLocked;
  final bool savingScreenshot;
  final bool gifBusy;
  final AsyncCallback onCopy;
  final AsyncCallback onSave;
  final AsyncCallback? onUnlock;
  final VoidCallback onStartGif;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isVertical ? 0 : 12),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: RemoteControlActionButton(
                icon: Icons.copy_rounded,
                label: savingScreenshot ? 'Saving' : 'Copy',
                onTap: onCopy,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: RemoteControlActionButton(
                icon: Icons.download_rounded,
                label: savingScreenshot ? 'Saving' : 'Save',
                onTap: onSave,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: RemoteControlActionButton(
                asset: isLocked
                    ? 'assets/ic/action/unlock.svg'
                    : 'assets/ic/action/lock.svg',
                label: isLocked ? 'Unlock' : 'Unlocked',
                onTap: onUnlock,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: RemoteControlActionButton(
                icon: gifBusy
                    ? Icons.hourglass_empty_rounded
                    : Icons.gif_box_outlined,
                label: gifBusy ? 'Saving…' : 'GIF',
                onTap: gifBusy ? null : onStartGif,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(int ms) {
  final s = (ms ~/ 1000).clamp(0, 99);
  final tenths = (ms % 1000) ~/ 100;
  return '${s.toString().padLeft(2, '0')}.${tenths}s';
}

class _RecordingControls extends StatelessWidget {
  const _RecordingControls({
    required this.isVertical,
    required this.isPaused,
    required this.elapsedMs,
    required this.onPauseResume,
    required this.onStop,
    required this.onCancel,
  });

  final bool isVertical;
  final bool isPaused;
  final int elapsedMs;
  final VoidCallback onPauseResume;
  final AsyncCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final remaining = (GifRecorder.maxDurationMs - elapsedMs).clamp(
      0,
      GifRecorder.maxDurationMs,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isVertical ? 0 : 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isPaused
                            ? colors.accent.withValues(alpha: 0.4)
                            : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _fmt(elapsedMs),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '−${_fmt(remaining)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.accent.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: RemoteControlActionButton(
                icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                label: isPaused ? 'Resume' : 'Pause',
                onTap: onPauseResume,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: RemoteControlActionButton(
                icon: Icons.stop_rounded,
                label: 'Save',
                onTap: onStop,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: RemoteControlActionButton(
                icon: Icons.close_rounded,
                label: 'Cancel',
                onTap: onCancel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
