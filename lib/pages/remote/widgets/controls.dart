import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../models/models.dart';

class RemoteControlControls extends StatelessWidget {
  static const double _layoutWidth = 246;
  static const double _layoutHeight = 162;

  const RemoteControlControls({
    super.key,
    required this.onTapButton,
    required this.onHoldButtonStart,
    required this.onHoldButtonEnd,
  });

  final Future<void> Function(RemoteButton) onTapButton;
  final Future<void> Function(RemoteButton) onHoldButtonStart;
  final Future<void> Function(RemoteButton) onHoldButtonEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: _layoutWidth,
        height: _layoutHeight,
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
            _BackButton(
              colors: colors,
              onTap: () => onTapButton(RemoteButton.back),
              onHoldStart: (_) => onHoldButtonStart(RemoteButton.back),
              onHoldEnd: (_) => onHoldButtonEnd(RemoteButton.back),
            ),
          ],
        ),
      ),
    );
  }
}

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
