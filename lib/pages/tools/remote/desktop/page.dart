import '../../../../services/localization/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';
import '../../../../components/notification.dart';
import 'package:qunleashed/components/appbar.dart';
import 'gif_export_dialog.dart';
import 'gif_recorder.dart';
import 'input/keyboard_listener.dart';
import 'layout.dart';
import 'models/models.dart';
import 'screenshot_saver.dart';
import 'session.dart';
import 'widgets/actions.dart';
import 'widgets/controls.dart';
import 'widgets/screen.dart';
import 'widgets/wide_body.dart';

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

  void _syncRecordingFlag() {
    _session.recording = _gifRecorder.state == GifRecordingState.recording;
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
  }

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
    _syncRecordingFlag();
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
    _syncRecordingFlag();
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

    // Stop accepting new frames immediately — before dialog is shown.
    if (_gifRecorder.state == GifRecordingState.recording) {
      _gifRecorder.pause();
    }
    _syncRecordingFlag();

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
        context.l10n.remoteGifSaveFailed('$saveError'),
        type: QNotificationType.error,
      );
    } else if (savedPath != null) {
      context.showNotification(
        context.l10n.remoteGifSaved(savedPath),
        type: QNotificationType.good,
      );
    }
  }

  void _cancelGifRecording() {
    _recordingTick?.cancel();
    _recordingTick = null;
    _gifRecorder.cancel();
    _syncRecordingFlag();
    setState(() {});
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _session.shutdown();
    Navigator.of(context).pop();
  }

  Future<void> _copyScreenshot() async {
    if (_savingScreenshot) return;
    setState(() => _savingScreenshot = true);
    try {
      final png = _session.capturePng();
      if (png == null || !mounted) return;
      await copyScreenshotToClipboard(png);
      if (!mounted) return;
      context.showNotification(
        context.l10n.remoteScreenshotCopied,
        type: QNotificationType.good,
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        context.l10n.remoteCopyFailed('$e'),
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
      final png = _session.capturePng();
      if (png == null || !mounted) return;
      final path = await saveScreenshotToAppStorage(png);
      if (!mounted) return;
      context.showNotification(
        context.l10n.remoteScreenshotSaved(path),
        type: QNotificationType.good,
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        context.l10n.remoteSaveFailed('$e'),
        type: QNotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _savingScreenshot = false);
    }
  }

  void _onHoldBegin(RemoteButton b) => unawaited(_session.beginHold(b));
  void _onHoldEnd(RemoteButton b) => unawaited(_session.endHold(b));

  bool get _streamVertical =>
      _session.orientation == StreamOrientation.vertical ||
      _session.orientation == StreamOrientation.verticalFlip;

  Widget _actions(RemoteLayout layout) {
    return RemoteActions(
      size: layout.actionsSize,
      gifState: _gifRecorder.state,
      gifElapsedMs: _gifRecorder.elapsedMs,
      justUnlocked: _session.justUnlocked,
      savingScreenshot: _savingScreenshot,
      onCopy: _copyScreenshot,
      onSave: _saveScreenshot,
      onUnlock: _session.unlock,
      onStartGif: _startGifRecording,
      onPauseResumeGif: _togglePauseGifRecording,
      onStopGif: _stopGifRecording,
      onCancelGif: _cancelGifRecording,
    );
  }

  Widget _screen(RemoteLayout layout) {
    return RemoteScreen(
      size: layout.screenSize,
      frameListenable: _session.frameListenable,
      queue: _session.queue,
      orientation: _session.orientation,
    );
  }

  Widget _controls(RemoteLayout layout) {
    return RemoteControls(
      size: layout.controlsSize,
      arrangement: layout.controlsArrangement,
      onHoldBegin: _onHoldBegin,
      onHoldEnd: _onHoldEnd,
    );
  }

  Widget _wideBody(RemoteLayout layout) {
    return RemoteWideBody(
      layout: layout,
      frameListenable: _session.frameListenable,
      queue: _session.queue,
      orientation: _session.orientation,
      connected: !_session.isDisconnected,
      gifState: _gifRecorder.state,
      gifElapsedMs: _gifRecorder.elapsedMs,
      justUnlocked: _session.justUnlocked,
      savingScreenshot: _savingScreenshot,
      onBack: _close,
      onCopy: _copyScreenshot,
      onSave: _saveScreenshot,
      onUnlock: _session.unlock,
      onStartGif: _startGifRecording,
      onPauseResumeGif: _togglePauseGifRecording,
      onStopGif: _stopGifRecording,
      onCancelGif: _cancelGifRecording,
      onHoldBegin: _onHoldBegin,
      onHoldEnd: _onHoldEnd,
    );
  }

  Widget _narrowBody(RemoteLayout layout) {
    return Column(
      children: [
        _actions(layout),
        const SizedBox(height: RemoteLayout.actionsSpacing),
        Expanded(child: Center(child: _screen(layout))),
        const SizedBox(height: RemoteLayout.gap),
        _controls(layout),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final wide = RemoteLayout.isWide(MediaQuery.sizeOf(context));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => _close(),
      child: RemoteKeyboardListener(
        onHoldBegin: (b) => unawaited(_session.beginHold(b)),
        onHoldEnd: (b) => unawaited(_session.endHold(b)),
        child: Scaffold(
          backgroundColor: colors.background,
          appBar: wide
              ? null
              : QPageAppBar(
                  title: context.l10n.remoteControlTitle,
                  leading: IconButton(
                    onPressed: _close,
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final layout = RemoteLayout.resolve(
                  constraints.biggest,
                  _streamVertical,
                  wide: wide,
                );
                return layout.wide
                    ? _wideBody(layout)
                    : Padding(
                        padding: layout.padding,
                        child: _narrowBody(layout),
                      );
              },
            ),
          ),
        ),
      ),
    );
  }
}
