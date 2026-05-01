import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    required this.lockReady,
    required this.isSavingScreenshot,
    required this.isStreaming,
    required this.onCopyScreenshot,
    required this.onSaveScreenshot,
    required this.onUnlock,
    required this.onTapButton,
    required this.onHoldButtonStart,
    required this.onHoldButtonEnd,
    required this.onTapBack,
    required this.onHoldBackStart,
    required this.onHoldBackEnd,
    required this.onClose,
    required this.onKeyEvent,
  });

  final ui.Image? image;
  final List<QueuedButton> queue;
  final StreamOrientation orientation;
  final bool isLocked;
  final bool lockReady;
  final bool isSavingScreenshot;
  final bool isStreaming;
  final VoidCallback onCopyScreenshot;
  final VoidCallback onSaveScreenshot;
  final VoidCallback onUnlock;
  final Future<void> Function(RemoteButton button) onTapButton;
  final Future<void> Function(RemoteButton button) onHoldButtonStart;
  final Future<void> Function(RemoteButton button) onHoldButtonEnd;
  final Future<void> Function() onTapBack;
  final Future<void> Function() onHoldBackStart;
  final Future<void> Function() onHoldBackEnd;
  final Future<void> Function() onClose;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return WillPopScope(
      onWillPop: () async {
        await onClose();
        return false;
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => onKeyEvent(event),
        child: Scaffold(
          backgroundColor: FlipperOriginalColors.background,
          body: Column(
            children: [
              Container(
                color: FlipperOriginalColors.accent,
                padding: EdgeInsets.only(top: topInset),
                child: SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: onClose,
                        icon: Icon(Icons.arrow_back, color: FlipperOriginalColors.onAccent),
                      ),
                      Expanded(
                        child: Text(
                          'Remote Control',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: FlipperOriginalColors.onAccent,
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
              Expanded(
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
                          child: _RemoteScreenWithOptions(
                            image: image,
                            queue: queue,
                            orientation: orientation,
                            isLocked: isLocked,
                            lockReady: lockReady,
                            isSavingScreenshot: isSavingScreenshot,
                            onCopyScreenshot: onCopyScreenshot,
                            onSaveScreenshot: onSaveScreenshot,
                            onUnlock: onUnlock,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _RemoteDPad(
                              onTapButton: onTapButton,
                              onHoldStart: onHoldButtonStart,
                              onHoldEnd: onHoldButtonEnd,
                            ),
                            const SizedBox(width: 30),
                            _RemoteBackButton(
                              onTap: onTapBack,
                              onHoldStart: onHoldBackStart,
                              onHoldEnd: onHoldBackEnd,
                            ),
                          ],
                        ),
                      ),
                      if (isStreaming) const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteScreenWithOptions extends StatelessWidget {
  const _RemoteScreenWithOptions({
    required this.image,
    required this.queue,
    required this.orientation,
    required this.isLocked,
    required this.lockReady,
    required this.isSavingScreenshot,
    required this.onCopyScreenshot,
    required this.onSaveScreenshot,
    required this.onUnlock,
  });

  final ui.Image? image;
  final List<QueuedButton> queue;
  final StreamOrientation orientation;
  final bool isLocked;
  final bool lockReady;
  final bool isSavingScreenshot;
  final VoidCallback onCopyScreenshot;
  final VoidCallback onSaveScreenshot;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeightForCenter = constraints.maxHeight - 74;
        final screenWidth =
            ((availableHeightForCenter - 85) * 2).clamp(0.0, constraints.maxWidth).toDouble();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RemoteOptionButton(
                    icon: Icons.copy_rounded,
                    label: isSavingScreenshot ? 'Saving...' : 'Copy',
                    onTap: onCopyScreenshot,
                  ),
                  _RemoteOptionButton(
                    icon: Icons.download_rounded,
                    label: isSavingScreenshot ? 'Saving...' : 'Save',
                    onTap: onSaveScreenshot,
                  ),
                  _RemoteOptionButton(
                    asset: isLocked
                        ? 'assets/flipper_svg/screenstreaming/ic_unlock.svg'
                        : 'assets/flipper_svg/screenstreaming/ic_lock.svg',
                    label: !lockReady
                        ? 'Loading...'
                        : isLocked
                            ? 'Unlock Flipper'
                            : 'Already unlocked',
                    onTap: lockReady && isLocked ? onUnlock : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: screenWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 28,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: queue.length,
                            shrinkWrap: true,
                            separatorBuilder: (_, _) => const SizedBox(width: 4),
                            itemBuilder: (_, index) => _QueuedButtonIcon(
                              key: ValueKey(queue[index].id),
                              asset: queue[index].asset,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: FlipperOriginalColors.flipperScreenBorder,
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: FlipperOriginalColors.flipperScreenBorder,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: FlipperOriginalColors.flipperScreenBackground,
                          ),
                          padding: const EdgeInsets.all(8),
                          child: _LiveFrame(
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
                        colorFilter: ColorFilter.mode(
                          FlipperOriginalColors.accent,
                          BlendMode.srcIn,
                        ),
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

class _QueuedButtonIcon extends StatefulWidget {
  const _QueuedButtonIcon({
    super.key,
    required this.asset,
  });

  final String asset;

  @override
  State<_QueuedButtonIcon> createState() => _QueuedButtonIconState();
}

class _QueuedButtonIconState extends State<_QueuedButtonIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();
  late final Animation<double> _scale = Tween<double>(begin: 0.86, end: 1).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
  );

  @override
  void dispose() {
    _controller.dispose();
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
          colorFilter: ColorFilter.mode(
            FlipperOriginalColors.accent,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}

class _LiveFrame extends StatelessWidget {
  static const int _screenWidth = 128;
  static const int _screenHeight = 64;

  const _LiveFrame({
    required this.image,
    required this.orientation,
  });

  final ui.Image? image;
  final StreamOrientation orientation;

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return SvgPicture.asset(
        'assets/flipper_svg/screenstreaming/pic_not_connected_light.svg',
        fit: BoxFit.fitWidth,
        colorFilter: ColorFilter.mode(
          FlipperOriginalColors.text30,
          BlendMode.srcIn,
        ),
      );
    }

    final quarterTurns = switch (orientation) {
      StreamOrientation.vertical => 1,
      StreamOrientation.verticalFlip => 1,
      _ => 0,
    };

    final aspectRatio =
        quarterTurns == 0 ? (_screenWidth / _screenHeight) : (_screenHeight / _screenWidth);

    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: RotatedBox(
          quarterTurns: quarterTurns,
          child: RawImage(
            image: image,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.none,
          ),
        ),
      ),
    );
  }
}

class _RemoteOptionButton extends StatelessWidget {
  const _RemoteOptionButton({
    this.asset,
    this.icon,
    required this.label,
    required this.onTap,
  });

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
              color: FlipperOriginalColors.flipperScreenOptionsBackground,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: asset != null
                ? SvgPicture.asset(
                    asset!,
                    colorFilter: ColorFilter.mode(
                      FlipperOriginalColors.accent,
                      BlendMode.srcIn,
                    ),
                  )
                : Icon(
                    icon,
                    color: FlipperOriginalColors.accent,
                    size: 24,
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: FlipperOriginalColors.accent,
          ),
        ),
      ],
    );
  }
}

class _RemoteDPad extends StatelessWidget {
  const _RemoteDPad({
    required this.onTapButton,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final Future<void> Function(RemoteButton button) onTapButton;
  final Future<void> Function(RemoteButton button) onHoldStart;
  final Future<void> Function(RemoteButton button) onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 162,
      height: 162,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: FlipperOriginalColors.flipperScreenBorder, width: 3),
      ),
      padding: const EdgeInsets.all(3),
      child: ClipOval(
        child: Container(
          color: FlipperOriginalColors.accent,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Expanded(child: SizedBox.shrink()),
                    Expanded(
                      child: _RemotePadButton(
                        button: RemoteButton.up,
                        asset: 'assets/flipper_svg/screenstreaming/ic_control_up.svg',
                        onTap: onTapButton,
                        onHoldStart: onHoldStart,
                        onHoldEnd: onHoldEnd,
                      ),
                    ),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _RemotePadButton(
                        button: RemoteButton.left,
                        asset: 'assets/flipper_svg/screenstreaming/ic_control_left.svg',
                        onTap: onTapButton,
                        onHoldStart: onHoldStart,
                        onHoldEnd: onHoldEnd,
                      ),
                    ),
                    Expanded(
                      child: _RemotePadButton(
                        button: RemoteButton.ok,
                        asset: 'assets/flipper_svg/screenstreaming/ic_control_ok.svg',
                        onTap: onTapButton,
                        onHoldStart: onHoldStart,
                        onHoldEnd: onHoldEnd,
                      ),
                    ),
                    Expanded(
                      child: _RemotePadButton(
                        button: RemoteButton.right,
                        asset: 'assets/flipper_svg/screenstreaming/ic_control_right.svg',
                        onTap: onTapButton,
                        onHoldStart: onHoldStart,
                        onHoldEnd: onHoldEnd,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    const Expanded(child: SizedBox.shrink()),
                    Expanded(
                      child: _RemotePadButton(
                        button: RemoteButton.down,
                        asset: 'assets/flipper_svg/screenstreaming/ic_control_down.svg',
                        onTap: onTapButton,
                        onHoldStart: onHoldStart,
                        onHoldEnd: onHoldEnd,
                      ),
                    ),
                    const Expanded(child: SizedBox.shrink()),
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

class _RemotePadButton extends StatelessWidget {
  const _RemotePadButton({
    required this.button,
    required this.asset,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final RemoteButton button;
  final String asset;
  final Future<void> Function(RemoteButton button) onTap;
  final Future<void> Function(RemoteButton button) onHoldStart;
  final Future<void> Function(RemoteButton button) onHoldEnd;

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
              colorFilter: ColorFilter.mode(
                FlipperOriginalColors.onAccent,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteBackButton extends StatelessWidget {
  const _RemoteBackButton({
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final Future<void> Function() onTap;
  final Future<void> Function() onHoldStart;
  final Future<void> Function() onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (_) => onHoldStart(),
      onLongPressEnd: (_) => onHoldEnd(),
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: FlipperOriginalColors.flipperScreenBorder, width: 3),
        ),
        padding: const EdgeInsets.all(3),
        child: ClipOval(
          child: Container(
            color: FlipperOriginalColors.accent,
            padding: const EdgeInsets.all(12),
            child: SvgPicture.asset(
              'assets/flipper_svg/screenstreaming/ic_control_back.svg',
              colorFilter: ColorFilter.mode(
                FlipperOriginalColors.onAccent,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
