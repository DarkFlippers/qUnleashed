import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../../components/icon.dart';
import '../../../../../theme/theme.dart';
import '../gif_recorder.dart';
import '../layout.dart';

const double _kIconSize = 48;
const double _kLabelGap = 8;
const double _kLabelHeight = 20;

String _fmt(int ms) {
  final s = (ms ~/ 1000).clamp(0, 99);
  final tenths = (ms % 1000) ~/ 100;
  return '${s.toString().padLeft(2, '0')}.${tenths}s';
}

class RemoteActionSpec {
  const RemoteActionSpec({
    required this.label,
    this.icon,
    this.asset,
    this.onTap,
    this.timerElapsedMs,
    this.paused = false,
  });

  final String label;
  final IconData? icon;
  final String? asset;
  final VoidCallback? onTap;
  final int? timerElapsedMs;
  final bool paused;

  bool get isTimer => timerElapsedMs != null;
}

List<RemoteActionSpec> buildRemoteActionSpecs({
  required GifRecordingState gifState,
  required int gifElapsedMs,
  required bool justUnlocked,
  required bool savingScreenshot,
  required AsyncCallback onCopy,
  required AsyncCallback onSave,
  required AsyncCallback onUnlock,
  required VoidCallback onStartGif,
  required VoidCallback onPauseResumeGif,
  required AsyncCallback onStopGif,
  required VoidCallback onCancelGif,
}) {
  if (gifState == GifRecordingState.recording ||
      gifState == GifRecordingState.paused) {
    final paused = gifState == GifRecordingState.paused;
    return [
      RemoteActionSpec(
        label: 'Recording',
        timerElapsedMs: gifElapsedMs,
        paused: paused,
      ),
      RemoteActionSpec(
        icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
        label: paused ? 'Resume' : 'Pause',
        onTap: onPauseResumeGif,
      ),
      RemoteActionSpec(
        icon: Icons.stop_rounded,
        label: 'Save',
        onTap: onStopGif,
      ),
      RemoteActionSpec(
        icon: Icons.close_rounded,
        label: 'Cancel',
        onTap: onCancelGif,
      ),
    ];
  }

  final busy = gifState == GifRecordingState.encoding;
  return [
    RemoteActionSpec(
      icon: Icons.copy_rounded,
      label: savingScreenshot ? 'Saving' : 'Copy',
      onTap: onCopy,
    ),
    RemoteActionSpec(
      icon: Icons.download_rounded,
      label: savingScreenshot ? 'Saving' : 'Save',
      onTap: onSave,
    ),
    RemoteActionSpec(
      asset: justUnlocked
          ? 'assets/ic/action/unlock.svg'
          : 'assets/ic/action/lock.svg',
      label: justUnlocked ? 'Unlocked' : 'Unlock',
      onTap: onUnlock,
    ),
    RemoteActionSpec(
      icon: busy ? Icons.hourglass_empty_rounded : Icons.gif_box_outlined,
      label: busy ? 'Saving…' : 'GIF',
      onTap: busy ? null : onStartGif,
    ),
  ];
}

class RemoteActions extends StatelessWidget {
  const RemoteActions({
    super.key,
    required this.size,
    required this.gifState,
    required this.gifElapsedMs,
    required this.justUnlocked,
    required this.savingScreenshot,
    required this.onCopy,
    required this.onSave,
    required this.onUnlock,
    required this.onStartGif,
    required this.onPauseResumeGif,
    required this.onStopGif,
    required this.onCancelGif,
  });

  final Size size;
  final GifRecordingState gifState;
  final int gifElapsedMs;
  final bool justUnlocked;
  final bool savingScreenshot;
  final AsyncCallback onCopy;
  final AsyncCallback onSave;
  final AsyncCallback onUnlock;
  final VoidCallback onStartGif;
  final VoidCallback onPauseResumeGif;
  final AsyncCallback onStopGif;
  final VoidCallback onCancelGif;

  List<RemoteActionSpec> _specs() => buildRemoteActionSpecs(
    gifState: gifState,
    gifElapsedMs: gifElapsedMs,
    justUnlocked: justUnlocked,
    savingScreenshot: savingScreenshot,
    onCopy: onCopy,
    onSave: onSave,
    onUnlock: onUnlock,
    onStartGif: onStartGif,
    onPauseResumeGif: onPauseResumeGif,
    onStopGif: onStopGif,
    onCancelGif: onCancelGif,
  );

  @override
  Widget build(BuildContext context) {
    final specs = _specs();

    return SizedBox.fromSize(
      size: size,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox.fromSize(
          size: RemoteActionsGeometry.designRow,
          child: Row(
            children: [
              for (var i = 0; i < specs.length; i++) ...[
                if (i > 0) const SizedBox(width: RemoteActionsGeometry.rowGap),
                specs[i].isTimer
                    ? _TimerCell(
                        elapsedMs: specs[i].timerElapsedMs!,
                        paused: specs[i].paused,
                      )
                    : _ActionCell(
                        icon: specs[i].icon,
                        asset: specs[i].asset,
                        label: specs[i].label,
                        onTap: specs[i].onTap,
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: RemoteActionsGeometry.cellWidth,
      height: RemoteActionsGeometry.cellHeight,
      child: child,
    );
  }
}

class _ActionCell extends StatelessWidget {
  const _ActionCell({
    required this.label,
    required this.onTap,
    this.asset,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final String? asset;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final badge = QIconBadgeStyle.of(context, colors.accent);

    return _Cell(
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: _kIconSize,
              height: _kIconSize,
              decoration: BoxDecoration(
                color: badge.background,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: asset != null
                  ? SvgPicture.asset(
                      asset!,
                      colorFilter: ColorFilter.mode(
                        badge.foreground,
                        BlendMode.srcIn,
                      ),
                    )
                  : Icon(icon, color: badge.foreground, size: 24),
            ),
          ),
          const SizedBox(height: _kLabelGap),
          SizedBox(
            height: _kLabelHeight,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1, color: colors.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerCell extends StatelessWidget {
  const _TimerCell({required this.elapsedMs, required this.paused});

  final int elapsedMs;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final remaining = (GifRecorder.maxDurationMs - elapsedMs).clamp(
      0,
      GifRecorder.maxDurationMs,
    );

    return _Cell(
      child: Column(
        children: [
          SizedBox(
            height: _kIconSize,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: paused
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
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: colors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: _kLabelGap),
          SizedBox(
            height: _kLabelHeight,
            child: Center(
              child: Text(
                '−${_fmt(remaining)}',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 11,
                  height: 1,
                  color: colors.accent.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
