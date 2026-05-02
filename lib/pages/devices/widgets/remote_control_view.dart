import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../remote_control_models.dart';

class RemoteControlView extends StatelessWidget {
  const RemoteControlView({
    super.key,
    required this.image,
    required this.queue,
    required this.orientation,
    required this.isLocked,
    required this.isSavingScreenshot,
    required this.onCopyScreenshot,
    required this.onSaveScreenshot,
    required this.onUnlock,
    required this.onTapButton,
    required this.onHoldButtonStart,
    required this.onHoldButtonEnd,
    required this.onClose,
    required this.onKeyEvent,
  });

  final ui.Image? image;
  final List<QueuedButton> queue;
  final StreamOrientation orientation;
  final bool isLocked;
  final bool isSavingScreenshot;
  final VoidCallback onCopyScreenshot;
  final VoidCallback onSaveScreenshot;
  final VoidCallback onUnlock;
  final Future<void> Function(RemoteButton) onTapButton;
  final Future<void> Function(RemoteButton) onHoldButtonStart;
  final Future<void> Function(RemoteButton) onHoldButtonEnd;
  final Future<void> Function() onClose;
  final KeyEventResult Function(KeyEvent) onKeyEvent;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final topInset = MediaQuery.paddingOf(context).top;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => onClose(),
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => onKeyEvent(event),
        child: Scaffold(
          backgroundColor: colors.background,
          body: Column(
            children: [
              // ── App bar ──────────────────────────────────────────────
              Container(
                color: colors.accent,
                padding: EdgeInsets.only(top: topInset),
                child: SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: onClose,
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
              ),

              // ── Screen + controls ────────────────────────────────────
              Expanded(
                child: Column(
                  children: [
                    // Screen section expands to fill remaining space.
                    // SafeArea bottom: false so we control bottom inset below.
                    Expanded(
                      child: SafeArea(
                        top: false,
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
                          child: _ScreenWithOptions(
                            colors: colors,
                            image: image,
                            queue: queue,
                            orientation: orientation,
                            isLocked: isLocked,
                            isSavingScreenshot: isSavingScreenshot,
                            onCopyScreenshot: onCopyScreenshot,
                            onSaveScreenshot: onSaveScreenshot,
                            onUnlock: onUnlock,
                          ),
                        ),
                      ),
                    ),

                    // Controls get their own SafeArea so the D-pad
                    // is not cut off by the home indicator.
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _DPad(
                              colors: colors,
                              onTapButton: onTapButton,
                              onHoldStart: onHoldButtonStart,
                              onHoldEnd: onHoldButtonEnd,
                            ),
                            const SizedBox(width: 30),
                            // Back button uses the same callbacks as D-pad.
                            _BackButton(
                              colors: colors,
                              onTap: () => onTapButton(RemoteButton.back),
                              onHoldStart: (_) => onHoldButtonStart(RemoteButton.back),
                              onHoldEnd: (_) => onHoldButtonEnd(RemoteButton.back),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen section: option row + queue + live frame + logo
// ─────────────────────────────────────────────────────────────────────────────

class _ScreenWithOptions extends StatelessWidget {
  const _ScreenWithOptions({
    required this.colors,
    required this.image,
    required this.queue,
    required this.orientation,
    required this.isLocked,
    required this.isSavingScreenshot,
    required this.onCopyScreenshot,
    required this.onSaveScreenshot,
    required this.onUnlock,
  });

  final QAppColors colors;
  final ui.Image? image;
  final List<QueuedButton> queue;
  final StreamOrientation orientation;
  final bool isLocked;
  final bool isSavingScreenshot;
  final VoidCallback onCopyScreenshot;
  final VoidCallback onSaveScreenshot;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Width of the screen widget so its 2:1 aspect fits the available height.
        final screenWidth =
            ((constraints.maxHeight - 74 - 85) * 2).clamp(0.0, constraints.maxWidth);

        return Column(
          children: [
            // ── Option buttons ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _OptionButton(
                    colors: colors,
                    icon: Icons.copy_rounded,
                    label: isSavingScreenshot ? 'Saving...' : 'Copy',
                    onTap: onCopyScreenshot,
                  ),
                  _OptionButton(
                    colors: colors,
                    icon: Icons.download_rounded,
                    label: isSavingScreenshot ? 'Saving...' : 'Save',
                    onTap: onSaveScreenshot,
                  ),
                  // Lock: always tappable when locked — no loading state.
                  _OptionButton(
                    colors: colors,
                    asset: isLocked
                        ? 'assets/flipper_svg/screenstreaming/ic_unlock.svg'
                        : 'assets/flipper_svg/screenstreaming/ic_lock.svg',
                    label: isLocked ? 'Unlock Flipper' : 'Already unlocked',
                    onTap: isLocked ? onUnlock : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── Live frame ─────────────────────────────────────────
            Expanded(
              child: Center(
                child: SizedBox(
                  width: screenWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Input queue icons
                      SizedBox(
                        height: 28,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: queue.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 4),
                            itemBuilder: (_, i) => _QueueIcon(
                              key: ValueKey(queue[i].id),
                              colors: colors,
                              asset: queue[i].asset,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Screen border
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.screenBorder, width: 3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: colors.screenBorder, width: 2),
                            borderRadius: BorderRadius.circular(12),
                            color: colors.screenBackground,
                          ),
                          padding: const EdgeInsets.all(8),
                          child: _LiveFrame(
                            colors: colors,
                            image: image,
                            orientation: orientation,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      SvgPicture.asset(
                        'assets/flipper_svg/screenstreaming/ic_flipper_logo.svg',
                        width: 183,
                        height: 22,
                        colorFilter: ColorFilter.mode(colors.accent, BlendMode.srcIn),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live frame
// ─────────────────────────────────────────────────────────────────────────────

class _LiveFrame extends StatelessWidget {
  static const _w = 128;
  static const _h = 64;

  const _LiveFrame({required this.colors, required this.image, required this.orientation});

  final QAppColors colors;
  final ui.Image? image;
  final StreamOrientation orientation;

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return SvgPicture.asset(
        'assets/flipper_svg/screenstreaming/pic_not_connected_light.svg',
        fit: BoxFit.fitWidth,
        colorFilter: ColorFilter.mode(colors.textMuted, BlendMode.srcIn),
      );
    }

    final isVertical =
        orientation == StreamOrientation.vertical || orientation == StreamOrientation.verticalFlip;

    return Center(
      child: AspectRatio(
        aspectRatio: isVertical ? (_h / _w).toDouble() : (_w / _h).toDouble(),
        child: RotatedBox(
          quarterTurns: isVertical ? 1 : 0,
          child: RawImage(image: image, fit: BoxFit.fill, filterQuality: FilterQuality.none),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Queued button icon (animated pop-in)
// ─────────────────────────────────────────────────────────────────────────────

class _QueueIcon extends StatefulWidget {
  const _QueueIcon({super.key, required this.colors, required this.asset});

  final QAppColors colors;
  final String asset;

  @override
  State<_QueueIcon> createState() => _QueueIconState();
}

class _QueueIconState extends State<_QueueIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 180))..forward();
  late final Animation<double> _scale = Tween<double>(begin: 0.86, end: 1).animate(
    CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: SizedBox(
        width: 24,
        height: 24,
        child: SvgPicture.asset(
          widget.asset,
          colorFilter: ColorFilter.mode(widget.colors.accent, BlendMode.srcIn),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Option button (Copy / Save / Unlock)
// ─────────────────────────────────────────────────────────────────────────────

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.colors,
    this.asset,
    this.icon,
    required this.label,
    required this.onTap,
  });

  final QAppColors colors;
  final String? asset;
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.screenOptionBackground,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: asset != null
                ? SvgPicture.asset(
                    asset!,
                    colorFilter: ColorFilter.mode(colors.accent, BlendMode.srcIn),
                  )
                : Icon(icon, color: colors.accent, size: 24),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 14, color: colors.accent)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// D-pad
// ─────────────────────────────────────────────────────────────────────────────

class _DPad extends StatelessWidget {
  const _DPad({
    required this.colors,
    required this.onTapButton,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final QAppColors colors;
  final Future<void> Function(RemoteButton) onTapButton;
  final Future<void> Function(RemoteButton) onHoldStart;
  final Future<void> Function(RemoteButton) onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 162,
      height: 162,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colors.screenBorder, width: 3),
      ),
      padding: const EdgeInsets.all(3),
      child: ClipOval(
        child: Container(
          color: colors.accent,
          child: Column(
            children: [
              Expanded(child: _row(RemoteButton.up, 'ic_control_up')),
              Expanded(
                child: Row(children: [
                  Expanded(child: _btn(RemoteButton.left, 'ic_control_left')),
                  Expanded(child: _btn(RemoteButton.ok, 'ic_control_ok')),
                  Expanded(child: _btn(RemoteButton.right, 'ic_control_right')),
                ]),
              ),
              Expanded(child: _row(RemoteButton.down, 'ic_control_down')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(RemoteButton center, String asset) {
    return Row(children: [
      const Expanded(child: SizedBox.shrink()),
      Expanded(child: _btn(center, asset)),
      const Expanded(child: SizedBox.shrink()),
    ]);
  }

  Widget _btn(RemoteButton button, String iconName) {
    return _PadButton(
      colors: colors,
      button: button,
      asset: 'assets/flipper_svg/screenstreaming/$iconName.svg',
      onTap: onTapButton,
      onHoldStart: onHoldStart,
      onHoldEnd: onHoldEnd,
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.colors,
    required this.button,
    required this.asset,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final QAppColors colors;
  final RemoteButton button;
  final String asset;
  final Future<void> Function(RemoteButton) onTap;
  final Future<void> Function(RemoteButton) onHoldStart;
  final Future<void> Function(RemoteButton) onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(button),
      onLongPressStart: (_) => onHoldStart(button),
      onLongPressEnd: (_) => onHoldEnd(button),
      child: Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: SvgPicture.asset(
              asset,
              colorFilter: ColorFilter.mode(colors.onAccent, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Back button
// ─────────────────────────────────────────────────────────────────────────────

class _BackButton extends StatelessWidget {
  const _BackButton({
    required this.colors,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final QAppColors colors;
  final VoidCallback onTap;
  final void Function(LongPressStartDetails) onHoldStart;
  final void Function(LongPressEndDetails) onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: onHoldStart,
      onLongPressEnd: onHoldEnd,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.screenBorder, width: 3),
        ),
        padding: const EdgeInsets.all(3),
        child: ClipOval(
          child: Container(
            color: colors.accent,
            padding: const EdgeInsets.all(12),
            child: SvgPicture.asset(
              'assets/flipper_svg/screenstreaming/ic_control_back.svg',
              colorFilter: ColorFilter.mode(colors.onAccent, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }
}
