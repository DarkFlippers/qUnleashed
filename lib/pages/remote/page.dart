import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/notification.dart';
import 'gif_export_dialog.dart';
import 'gif_recorder.dart';
import 'input/keyboard_listener.dart';
import 'models/models.dart';
import 'screenshot_saver.dart';
import 'session.dart';
import 'widgets/action_row.dart';
import 'widgets/controls.dart';
import 'widgets/view.dart';

class RemoteControlPage extends StatefulWidget {
  const RemoteControlPage({super.key});

  @override
  State<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _RemoteControlPageState extends State<RemoteControlPage> {
  late final RemoteSession _session;
  late final GifRecorder _gifRecorder;

  bool _savingScreenshot = false;
  bool _closing = false;

  Timer? _recordingTick;

  @override
  void initState() {
    super.initState();
    _gifRecorder = GifRecorder();
    _session = RemoteSession()
      ..addListener(_onSessionChanged)
      ..onRawFrame = _onRawFrame;
  }

  @override
  void dispose() {
    _recordingTick?.cancel();
    _session
      ..removeListener(_onSessionChanged)
      ..onRawFrame = null;
    _session.dispose();
    if (_gifRecorder.state != GifRecordingState.idle) _gifRecorder.cancel();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
  }

  // ── GIF recording ──────────────────────────────────────────────────────────

  void _onRawFrame(RawFrameData frame) {
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
    if (state == GifRecordingState.idle || state == GifRecordingState.encoding) {
      return;
    }

    _recordingTick?.cancel();
    _recordingTick = null;

    // Stop accepting new frames immediately — before dialog is shown.
    if (_gifRecorder.state == GifRecordingState.recording) {
      _gifRecorder.pause();
    }

    if (_gifRecorder.frameCount == 0) {
      _gifRecorder.cancel();
      setState(() {});
      return;
    }

    final export = await showGifExportDialog(context);
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
        } catch (_) {}
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
    if (_savingScreenshot) return;
    setState(() => _savingScreenshot = true);
    try {
      final png = await _session.capturePng();
      if (png == null || !mounted) return;
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
    if (_savingScreenshot) return;
    setState(() => _savingScreenshot = true);
    try {
      final png = await _session.capturePng();
      if (png == null || !mounted) return;
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
                                  RemoteActionRow(
                                    isVertical: isVertical,
                                    gifState: _gifRecorder.state,
                                    gifElapsedMs: _gifRecorder.elapsedMs,
                                    isLocked: _session.isLocked,
                                    savingScreenshot: _savingScreenshot,
                                    onCopy: _copyScreenshot,
                                    onSave: _saveScreenshot,
                                    onUnlock: _session.isLocked
                                        ? _session.unlock
                                        : null,
                                    onStartGif: _startGifRecording,
                                    onPauseResumeGif: _togglePauseGifRecording,
                                    onStopGif: _stopGifRecording,
                                    onCancelGif: _cancelGifRecording,
                                  ),
                                  const SizedBox(height: 6),
                                  Expanded(
                                    child: RemoteControlView(
                                      frameListenable: _session.frameListenable,
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
}
