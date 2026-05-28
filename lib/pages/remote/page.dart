import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/notification.dart';
import 'gif_recorder.dart';
import 'input/keyboard_listener.dart';
import 'models/models.dart';
import 'screenshot_saver.dart';
import 'session.dart';
import 'widgets/action_button.dart';
import 'widgets/controls.dart';
import 'widgets/view.dart';

class RemoteControlPage extends StatefulWidget {
  const RemoteControlPage({super.key});

  @override
  State<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _GifExportOptions {
  const _GifExportOptions({required this.scale, required this.speed});

  final int scale;
  final int speed;
}

class _RemoteControlPageState extends State<RemoteControlPage> {
  late final RemoteSession _session;
  late final GifRecorder _gifRecorder;

  bool _savingScreenshot = false;
  bool _closing = false;
  Object? _shownStartError;

  Timer? _recordingTick;

  @override
  void initState() {
    super.initState();
    _gifRecorder = GifRecorder();
    _session = RemoteSession()
      ..addListener(_onSessionChanged)
      ..onDecodedFrame = _onDecodedFrame;
  }

  @override
  void dispose() {
    _recordingTick?.cancel();
    _session
      ..removeListener(_onSessionChanged)
      ..onDecodedFrame = null;
    _session.dispose();
    if (_gifRecorder.state != GifRecordingState.idle) _gifRecorder.cancel();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final err = _session.startError;
    if (err != null && err != _shownStartError) {
      _shownStartError = err;
      context.showNotification(
        'Remote control unavailable: $err',
        type: QNotificationType.error,
      );
    }
    setState(() {});
  }

  // ── GIF recording ──────────────────────────────────────────────────────────

  void _onDecodedFrame(DecodedFrame frame) {
    if (_gifRecorder.state != GifRecordingState.recording) return;
    final autoStop = _gifRecorder.addFrame(frame);
    if (autoStop && mounted) {
      _stopGifRecording();
    }
  }

  void _startGifRecording() {
    if (_gifRecorder.state != GifRecordingState.idle) return;
    _gifRecorder.start(
      _session.lastBgColor ?? 0xFFDFDFDF,
      _session.lastFgColor ?? 0xFF000000,
    );
    _recordingTick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  void _togglePauseGifRecording() {
    if (_gifRecorder.state == GifRecordingState.recording) {
      _gifRecorder.pause();
      _recordingTick?.cancel();
      _recordingTick = null;
    } else if (_gifRecorder.state == GifRecordingState.paused) {
      _gifRecorder.resume();
      _recordingTick = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) setState(() {});
      });
    }
    setState(() {});
  }

  Future<void> _stopGifRecording() async {
    final state = _gifRecorder.state;
    if (state == GifRecordingState.idle ||
        state == GifRecordingState.encoding) {
      return;
    }

    _recordingTick?.cancel();
    _recordingTick = null;

    if (_gifRecorder.frameCount == 0) {
      _gifRecorder.cancel();
      setState(() {});
      return;
    }

    final export = await _showGifExportDialog();
    if (export == null) {
      _gifRecorder.cancel();
      if (mounted) setState(() {});
      return;
    }

    String? savedPath;
    Object? saveError;

    try {
      final encodeFuture = _gifRecorder.encode(
        scale: export.scale,
        speed: export.speed,
      );
      if (mounted) setState(() {});
      final gifBytes = await encodeFuture;
      if (gifBytes != null) {
        final path = await saveGifToAppStorage(gifBytes);
        savedPath = path;
        try {
          await copyGifFileToClipboard(path);
        } catch (_) {
          // clipboard copy is best-effort
        }
      }
    } catch (e) {
      saveError = e;
    } finally {
      _gifRecorder.reset();
    }

    if (!mounted) return;
    setState(() {});

    if (saveError != null) {
      context.showNotification(
        'GIF save failed: $saveError',
        type: QNotificationType.error,
      );
    } else if (savedPath != null) {
      context.showNotification(
        'GIF saved: $savedPath',
        type: QNotificationType.good,
      );
    }
  }

  Future<_GifExportOptions?> _showGifExportDialog() {
    var selectedScale = 2;
    var selectedSpeed = 1;

    return showDialog<_GifExportOptions>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.appColors;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget optionRow({
              required int value,
              required int selected,
              required ValueChanged<int> onSelected,
            }) {
              return ChoiceChip(
                label: Text('${value}x'),
                selected: selected == value,
                onSelected: (_) => setDialogState(() => onSelected(value)),
                selectedColor: colors.accent.withValues(alpha: 0.18),
                labelStyle: TextStyle(
                  color: selected == value ? colors.accent : colors.textPrimary,
                  fontWeight: selected == value
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
                side: BorderSide(
                  color: selected == value ? colors.accent : colors.divider,
                ),
              );
            }

            return AlertDialog(
              title: const Text('Export GIF'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scale',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final value in const [1, 2, 4])
                        optionRow(
                          value: value,
                          selected: selectedScale,
                          onSelected: (v) => selectedScale = v,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Speed',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final value in const [1, 2, 4])
                        optionRow(
                          value: value,
                          selected: selectedSpeed,
                          onSelected: (v) => selectedSpeed = v,
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(
                    _GifExportOptions(
                      scale: selectedScale,
                      speed: selectedSpeed,
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _cancelGifRecording() {
    _recordingTick?.cancel();
    _recordingTick = null;
    _gifRecorder.cancel();
    setState(() {});
  }

  // ── Screenshot ─────────────────────────────────────────────────────────────

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _session.stop();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _copyScreenshot() async {
    final png = _session.lastPng;
    if (png == null || _savingScreenshot) return;
    setState(() => _savingScreenshot = true);
    try {
      await copyScreenshotToClipboard(png);
      if (!mounted) return;
      context.showNotification(
        'Screenshot copied to clipboard',
        type: QNotificationType.good,
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        'Copy failed: $e',
        type: QNotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _savingScreenshot = false);
    }
  }

  Future<void> _saveScreenshot() async {
    final png = _session.lastPng;
    if (png == null || _savingScreenshot) return;
    setState(() => _savingScreenshot = true);
    try {
      final path = await saveScreenshotToAppStorage(png);
      if (!mounted) return;
      context.showNotification(
        'Screenshot saved: $path',
        type: QNotificationType.good,
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        'Save failed: $e',
        type: QNotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _savingScreenshot = false);
    }
  }

  void _onHoldBegin(RemoteButton b) => unawaited(_session.beginHold(b));
  void _onHoldEnd(RemoteButton b) => unawaited(_session.endHold(b));

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final topInset = MediaQuery.paddingOf(context).top;
    final orientation = _session.orientation;
    final isVertical =
        orientation == StreamOrientation.vertical ||
        orientation == StreamOrientation.verticalFlip;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => _close(),
      child: RemoteKeyboardListener(
        onHoldBegin: (b) => unawaited(_session.beginHold(b)),
        onHoldEnd: (b) => unawaited(_session.endHold(b)),
        child: Scaffold(
          backgroundColor: colors.background,
          body: Column(
            children: [
              _buildAppBar(colors, topInset),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final controlsHeight = isVertical
                        ? math.min(150.0, constraints.maxHeight * 0.28)
                        : math.min(174.0, constraints.maxHeight * 0.32);
                    final hPad = isVertical ? 12.0 : 24.0;

                    return Column(
                      children: [
                        Expanded(
                          child: SafeArea(
                            top: false,
                            bottom: false,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 8),
                              child: Column(
                                children: [
                                  _buildActionRow(isVertical),
                                  const SizedBox(height: 6),
                                  Expanded(
                                    child: RemoteControlView(
                                      image: _session.frameImage,
                                      queue: _session.queue,
                                      orientation: orientation,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SizedBox(
                              height: controlsHeight,
                              child: RemoteControlControls(
                                onHoldBegin: _onHoldBegin,
                                onHoldEnd: _onHoldEnd,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(QAppColors colors, double topInset) {
    return Container(
      color: colors.accent,
      padding: EdgeInsets.only(top: topInset),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              onPressed: _close,
              icon: Icon(Icons.arrow_back, color: colors.onAccent),
            ),
            Expanded(
              child: Text(
                'Remote Control',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.onAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(bool isVertical) {
    final gifState = _gifRecorder.state;

    if (gifState == GifRecordingState.recording ||
        gifState == GifRecordingState.paused) {
      return _buildRecordingControls(isVertical);
    }

    final isLocked = _session.isLocked;
    final gifBusy = gifState == GifRecordingState.encoding;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isVertical ? 0 : 12),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: RemoteControlActionButton(
                icon: Icons.copy_rounded,
                label: _savingScreenshot ? 'Saving' : 'Copy',
                onTap: _copyScreenshot,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: RemoteControlActionButton(
                icon: Icons.download_rounded,
                label: _savingScreenshot ? 'Saving' : 'Save',
                onTap: _saveScreenshot,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: RemoteControlActionButton(
                asset: isLocked
                    ? 'assets/flipper_svg/screenstreaming/ic_unlock.svg'
                    : 'assets/flipper_svg/screenstreaming/ic_lock.svg',
                label: isLocked ? 'Unlock' : 'Unlocked',
                onTap: isLocked ? () => unawaited(_session.unlock()) : null,
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
                onTap: gifBusy ? null : _startGifRecording,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingControls(bool isVertical) {
    final colors = context.appColors;
    final isPaused = _gifRecorder.state == GifRecordingState.paused;
    final elapsed = _gifRecorder.elapsedMs;
    final remaining = (GifRecorder.maxDurationMs - elapsed).clamp(
      0,
      GifRecorder.maxDurationMs,
    );

    String fmt(int ms) {
      final s = (ms ~/ 1000).clamp(0, 99);
      final tenths = (ms % 1000) ~/ 100;
      return '${s.toString().padLeft(2, '0')}.${tenths}s';
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isVertical ? 0 : 12),
      child: Row(
        children: [
          // Timer display
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
                      fmt(elapsed),
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
                  '−${fmt(remaining)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.accent.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          // Pause / Resume
          Expanded(
            child: Center(
              child: RemoteControlActionButton(
                icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                label: isPaused ? 'Resume' : 'Pause',
                onTap: _togglePauseGifRecording,
              ),
            ),
          ),
          // Stop (save)
          Expanded(
            child: Center(
              child: RemoteControlActionButton(
                icon: Icons.stop_rounded,
                label: 'Save',
                onTap: _stopGifRecording,
              ),
            ),
          ),
          // Cancel (discard)
          Expanded(
            child: Center(
              child: RemoteControlActionButton(
                icon: Icons.close_rounded,
                label: 'Cancel',
                onTap: _cancelGifRecording,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
