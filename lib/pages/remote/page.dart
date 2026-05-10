import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'input/keyboard_listener.dart';
import 'models/models.dart';
import 'session.dart';
import 'screenshot_saver.dart';
import 'widgets/action_button.dart';
import 'widgets/controls.dart';
import 'widgets/view.dart';

class RemoteControlPage extends StatefulWidget {
  const RemoteControlPage({super.key});

  @override
  State<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _RemoteControlPageState extends State<RemoteControlPage> {
  late final RemoteSession _session;
  bool _savingScreenshot = false;
  bool _closing = false;
  Object? _shownStartError;

  @override
  void initState() {
    super.initState();
    _session = RemoteSession()..addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final err = _session.startError;
    if (err != null && err != _shownStartError) {
      _shownStartError = err;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Remote control unavailable: $err')),
      );
    }
    setState(() {});
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Screenshot copied to clipboard')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copy failed: $e')),
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
      final path = await saveScreenshotToPictures(png);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Screenshot saved: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingScreenshot = false);
    }
  }

  void _onHoldBegin(RemoteButton b) => unawaited(_session.beginHold(b));
  void _onHoldEnd(RemoteButton b) => unawaited(_session.endHold(b));

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final topInset = MediaQuery.paddingOf(context).top;
    final orientation = _session.orientation;
    final isVertical = orientation == StreamOrientation.vertical ||
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
    final isLocked = _session.isLocked;
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
        ],
      ),
    );
  }
}
