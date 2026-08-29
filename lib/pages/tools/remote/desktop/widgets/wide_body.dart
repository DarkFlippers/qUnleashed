import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../../theme/theme.dart';
import '../gif_recorder.dart';
import '../layout.dart';
import '../models/models.dart';
import 'action_bar.dart';
import 'controls.dart';
import 'info_hint.dart';
import 'screen.dart';

class RemoteWideBody extends StatelessWidget {
  const RemoteWideBody({
    super.key,
    required this.layout,
    required this.frameListenable,
    required this.queue,
    required this.orientation,
    required this.connected,
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
    required this.onHoldBegin,
    required this.onHoldEnd,
  });

  final RemoteLayout layout;
  final ValueListenable<ui.Image?> frameListenable;
  final List<QueuedButton> queue;
  final StreamOrientation orientation;
  final bool connected;
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
  final void Function(RemoteButton) onHoldBegin;
  final void Function(RemoteButton) onHoldEnd;

  Widget _ledSlot(RemoteLayout layout, bool connected) {
    final radius =
        RemoteControlsGeometry.deviceDpadDiameter(layout.controlsSize.height) /
        2;
    final orbit = radius + RemoteLayout.ledSize / 2 + RemoteLayout.ledGap;
    final activeBottom =
        layout.screenSize.height -
        RemoteScreenGeometry.strip -
        RemoteScreenGeometry.bezel / 2;

    return Positioned(
      right:
          layout.controlsSize.width -
          radius +
          orbit * math.sqrt1_2 -
          RemoteLayout.ledSize / 2,
      top: activeBottom - RemoteLayout.ledSize / 2,
      child: _Led(connected: connected),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: RemoteLayout.panelMargin,
      child: Center(
        child: SizedBox.fromSize(
          size: layout.panelSize,
          child: Container(
            decoration: BoxDecoration(
              color: context.appColors.card,
              borderRadius: BorderRadius.circular(RemoteLayout.panelRadius),
            ),
            padding: RemoteLayout.panelPadding,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            RemoteScreen(
                              size: layout.screenSize,
                              queueAtBottom: true,
                              frameListenable: frameListenable,
                              queue: queue,
                              orientation: orientation,
                            ),
                            RemoteControls(
                              size: layout.controlsSize,
                              arrangement: layout.controlsArrangement,
                              onHoldBegin: onHoldBegin,
                              onHoldEnd: onHoldEnd,
                            ),
                          ],
                        ),
                        _ledSlot(layout, connected),
                      ],
                    ),
                    const Spacer(),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: RemoteActionBar(
                        size: layout.actionsSize,
                        gifState: gifState,
                        gifElapsedMs: gifElapsedMs,
                        justUnlocked: justUnlocked,
                        savingScreenshot: savingScreenshot,
                        onBack: onBack,
                        onCopy: onCopy,
                        onSave: onSave,
                        onUnlock: onUnlock,
                        onStartGif: onStartGif,
                        onPauseResumeGif: onPauseResumeGif,
                        onStopGif: onStopGif,
                        onCancelGif: onCancelGif,
                      ),
                    ),
                  ],
                ),
                const Align(
                  alignment: Alignment.bottomRight,
                  child: RemoteInfoHint(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Led extends StatelessWidget {
  const _Led({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = connected ? colors.success : colors.textMuted;

    return Container(
      width: RemoteLayout.ledSize,
      height: RemoteLayout.ledSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: connected
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
    );
  }
}
