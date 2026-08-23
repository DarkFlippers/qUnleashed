import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../../theme/colors/display.dart';
import '../../../../../theme/theme.dart';
import '../layout.dart';
import '../models/models.dart';

const Color _kFlipperOrange = Color(0xFFFF8200);

class _AccentColorMapper extends ColorMapper {
  const _AccentColorMapper(this.accent);
  final Color accent;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    return color == _kFlipperOrange ? accent : color;
  }
}

class RemoteControls extends StatelessWidget {
  const RemoteControls({
    super.key,
    required this.size,
    required this.arrangement,
    required this.onHoldBegin,
    required this.onHoldEnd,
  });

  final Size size;
  final RemoteControlsArrangement arrangement;
  final void Function(RemoteButton) onHoldBegin;
  final void Function(RemoteButton) onHoldEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final device = arrangement == RemoteControlsArrangement.device;
    final dpad = _DPad(
      colors: colors,
      size: device
          ? RemoteControlsGeometry.deviceDpad
          : RemoteControlsGeometry.dpad,
      onHoldBegin: onHoldBegin,
      onHoldEnd: onHoldEnd,
    );
    final back = _BackButton(
      colors: colors,
      size: device
          ? RemoteControlsGeometry.deviceBack
          : RemoteControlsGeometry.back,
      onHoldBegin: () => onHoldBegin(RemoteButton.back),
      onHoldEnd: () => onHoldEnd(RemoteButton.back),
    );

    return SizedBox.fromSize(
      size: size,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox.fromSize(
          size: RemoteControlsGeometry.design(arrangement),
          child: arrangement == RemoteControlsArrangement.inline
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    dpad,
                    const SizedBox(width: RemoteControlsGeometry.inlineGap),
                    back,
                  ],
                )
              : Stack(
                  children: [
                    Positioned(left: 0, top: 0, child: dpad),
                    Positioned(right: 0, bottom: 0, child: back),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DPad extends StatelessWidget {
  const _DPad({
    required this.colors,
    required this.size,
    required this.onHoldBegin,
    required this.onHoldEnd,
  });

  final QAppColors colors;
  final double size;
  final void Function(RemoteButton) onHoldBegin;
  final void Function(RemoteButton) onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: DisplayColors.forColors(colors).border,
          width: 3,
        ),
      ),
      padding: const EdgeInsets.all(3),
      child: ClipOval(
        child: ColoredBox(
          color: colors.accent,
          child: Column(
            children: [
              Expanded(child: _row(RemoteButton.up, 'up')),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _btn(RemoteButton.left, 'left')),
                    Expanded(child: _btn(RemoteButton.ok, 'ok')),
                    Expanded(child: _btn(RemoteButton.right, 'right')),
                  ],
                ),
              ),
              Expanded(child: _row(RemoteButton.down, 'down')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(RemoteButton center, String asset) {
    return Row(
      children: [
        const Expanded(child: SizedBox.shrink()),
        Expanded(child: _btn(center, asset)),
        const Expanded(child: SizedBox.shrink()),
      ],
    );
  }

  Widget _btn(RemoteButton button, String iconName) {
    return _HoldButton(
      onHoldBegin: () => onHoldBegin(button),
      onHoldEnd: () => onHoldEnd(button),
      child: Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: SvgPicture.asset(
              'assets/ic/control/$iconName.svg',
              colorMapper: _AccentColorMapper(colors.accent),
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
    required this.size,
    required this.onHoldBegin,
    required this.onHoldEnd,
  });

  final QAppColors colors;
  final double size;
  final VoidCallback onHoldBegin;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return _HoldButton(
      onHoldBegin: onHoldBegin,
      onHoldEnd: onHoldEnd,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: DisplayColors.forColors(colors).border,
            width: 3,
          ),
        ),
        padding: const EdgeInsets.all(3),
        child: ClipOval(
          child: Container(
            color: colors.accent,
            padding: const EdgeInsets.all(12),
            child: SvgPicture.asset('assets/ic/control/back.svg'),
          ),
        ),
      ),
    );
  }
}

class _HoldButton extends StatefulWidget {
  const _HoldButton({
    required this.onHoldBegin,
    required this.onHoldEnd,
    required this.child,
  });

  final VoidCallback onHoldBegin;
  final VoidCallback onHoldEnd;
  final Widget child;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  int? _activePointer;

  @override
  void dispose() {
    if (_activePointer != null) {
      _activePointer = null;
      widget.onHoldEnd();
    }
    super.dispose();
  }

  void _down(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    HapticFeedback.selectionClick();
    widget.onHoldBegin();
  }

  void _release(int pointer) {
    if (_activePointer != pointer) return;
    _activePointer = null;
    widget.onHoldEnd();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: (e) => _release(e.pointer),
      onPointerCancel: (e) => _release(e.pointer),
      child: widget.child,
    );
  }
}
