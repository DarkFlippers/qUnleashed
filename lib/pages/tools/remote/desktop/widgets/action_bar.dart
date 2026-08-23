import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../../components/icon.dart';
import '../../../../../theme/theme.dart';
import '../gif_recorder.dart';
import '../layout.dart';
import 'actions.dart';

class RemoteActionBar extends StatelessWidget {
  const RemoteActionBar({
    super.key,
    required this.size,
    required this.showSession,
    required this.sessionBusy,
    required this.onRequestSession,
    required this.gifState,
    required this.gifElapsedMs,
    required this.justUnlocked,
    required this.savingScreenshot,
    required this.onBack,
    required this.onCopy,
    required this.onSave,
    required this.onUnlock,
    required this.onStartGif,
    required this.onPauseResumeGif,
    required this.onStopGif,
    required this.onCancelGif,
  });

  final Size size;
  final bool showSession;
  final bool sessionBusy;
  final VoidCallback onRequestSession;
  final GifRecordingState gifState;
  final int gifElapsedMs;
  final bool justUnlocked;
  final bool savingScreenshot;
  final VoidCallback onBack;
  final AsyncCallback onCopy;
  final AsyncCallback onSave;
  final AsyncCallback onUnlock;
  final VoidCallback onStartGif;
  final VoidCallback onPauseResumeGif;
  final AsyncCallback onStopGif;
  final VoidCallback onCancelGif;

  @override
  Widget build(BuildContext context) {
    final specs = buildRemoteActionSpecs(
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

    final cells = specs.length + (showSession ? 1 : 0);
    final scale = math.min(
      size.height / RemoteActionBarGeometry.pillHeight,
      size.width / RemoteActionBarGeometry.designFor(cells).width,
    );

    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _Pill(
              scale: scale,
              width: RemoteActionBarGeometry.backWidth,
              icon: Icons.chevron_left_rounded,
              label: 'Back',
              onTap: onBack,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSession) ...[
                  _SessionPill(
                    scale: scale,
                    busy: sessionBusy,
                    onTap: onRequestSession,
                  ),
                  SizedBox(width: RemoteActionBarGeometry.pillGap * scale),
                ],
                for (var i = 0; i < specs.length; i++) ...[
                  if (i > 0)
                    SizedBox(width: RemoteActionBarGeometry.pillGap * scale),
                  if (specs[i].isTimer)
                    _TimerPill(
                      scale: scale,
                      elapsedMs: specs[i].timerElapsedMs!,
                      paused: specs[i].paused,
                    )
                  else
                    _Pill(
                      scale: scale,
                      width: RemoteActionBarGeometry.pillWidth,
                      icon: specs[i].icon,
                      asset: specs[i].asset,
                      label: specs[i].label,
                      onTap: specs[i].onTap,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.width, required this.scale, required this.child});

  final double width;
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final badge = QIconBadgeStyle.of(context, context.appColors.accent);
    return SizedBox(
      width: width * scale,
      height: RemoteActionBarGeometry.pillHeight * scale,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Container(
          width: width,
          height: RemoteActionBarGeometry.pillHeight,
          decoration: BoxDecoration(
            color: badge.background,
            borderRadius: BorderRadius.circular(
              RemoteActionBarGeometry.pillRadius,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.width,
    required this.scale,
    required this.label,
    required this.onTap,
    this.icon,
    this.asset,
  });

  final double width;
  final double scale;
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final String? asset;

  @override
  Widget build(BuildContext context) {
    final badge = QIconBadgeStyle.of(context, context.appColors.accent);
    return GestureDetector(
      onTap: onTap,
      child: _Shell(
        width: width,
        scale: scale,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (asset != null)
              SizedBox(
                width: 22,
                height: 22,
                child: SvgPicture.asset(
                  asset!,
                  colorFilter: ColorFilter.mode(
                    badge.foreground,
                    BlendMode.srcIn,
                  ),
                ),
              )
            else if (icon != null)
              Icon(icon, size: 22, color: badge.foreground),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: badge.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerPill extends StatelessWidget {
  const _TimerPill({
    required this.scale,
    required this.elapsedMs,
    required this.paused,
  });

  final double scale;
  final int elapsedMs;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final badge = QIconBadgeStyle.of(context, colors.accent);
    final remaining = (GifRecorder.maxDurationMs - elapsedMs).clamp(
      0,
      GifRecorder.maxDurationMs,
    );

    return _Shell(
      width: RemoteActionBarGeometry.pillWidth,
      scale: scale,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: paused
                  ? badge.foreground.withValues(alpha: 0.4)
                  : colors.danger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${_fmt(elapsedMs)}  −${_fmt(remaining)}',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1,
                fontWeight: FontWeight.w700,
                color: badge.foreground,
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

class _SessionPill extends StatelessWidget {
  const _SessionPill({
    required this.scale,
    required this.busy,
    required this.onTap,
  });

  final double scale;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badge = QIconBadgeStyle.of(context, context.appColors.accent);

    return GestureDetector(
      onTap: busy ? null : onTap,
      child: _Shell(
        width: RemoteActionBarGeometry.pillWidth,
        scale: scale,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SpinningIcon(spinning: busy, color: badge.foreground),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Session',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: badge.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon({required this.spinning, required this.color});

  final bool spinning;
  final Color color;

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) {
      _ctrl.repeat();
    } else {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant _SpinningIcon old) {
    super.didUpdateWidget(old);
    if (old.spinning == widget.spinning) return;
    if (widget.spinning) {
      _ctrl.repeat();
    } else {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: Icon(Icons.sync_rounded, size: 22, color: widget.color),
    );
  }
}
