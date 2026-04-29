import 'package:flipperzero/flipperzero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/discovered_device.dart';
import '../services/flipper_protocol.dart';
import '../widgets/device_shell.dart';

enum RemoteButton { up, down, left, right, ok, back }

class RemoteControlScreen extends StatelessWidget {
  const RemoteControlScreen({
    super.key,
    required this.device,
  });

  final ConnectedDevice device;

  Future<void> _sendShort(RemoteButton button) async {
    final req = SendInputEventRequest(
      key: switch (button) {
        RemoteButton.up => InputKey.UP,
        RemoteButton.down => InputKey.DOWN,
        RemoteButton.left => InputKey.LEFT,
        RemoteButton.right => InputKey.RIGHT,
        RemoteButton.ok => InputKey.OK,
        RemoteButton.back => InputKey.BACK,
      },
      type: InputType.SHORT,
    );
    await device.sendBytes(
      FlipperProtocol.encode(
        Main(
          commandId: FlipperProtocol.nextCommandId(),
          guiSendInputEventRequest: req,
        ),
      ),
    );
  }

  Future<void> _sendLong(RemoteButton button) async {
    final req = SendInputEventRequest(
      key: switch (button) {
        RemoteButton.up => InputKey.UP,
        RemoteButton.down => InputKey.DOWN,
        RemoteButton.left => InputKey.LEFT,
        RemoteButton.right => InputKey.RIGHT,
        RemoteButton.ok => InputKey.OK,
        RemoteButton.back => InputKey.BACK,
      },
      type: InputType.LONG,
    );
    await device.sendBytes(
      FlipperProtocol.encode(
        Main(
          commandId: FlipperProtocol.nextCommandId(),
          guiSendInputEventRequest: req,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
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
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'Remote Control',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
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
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 14, 24, 24),
                    child: _RemoteScreenWithOptions(),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 32),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _RemoteDPad(
                              onPress: _sendShort,
                              onLongPress: _sendLong,
                            ),
                            const SizedBox(width: 30),
                            _RemoteBackButton(
                              onPress: () => _sendShort(RemoteButton.back),
                              onLongPress: () => _sendLong(RemoteButton.back),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteScreenWithOptions extends StatelessWidget {
  const _RemoteScreenWithOptions();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 303 / 290,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _RemoteOptionButton(
                asset: 'assets/flipper_svg/screenstreaming/ic_camera.svg',
                label: 'Screenshot',
              ),
              _RemoteOptionButton(
                asset: 'assets/flipper_svg/screenstreaming/ic_unlock.svg',
                label: 'Unlock Flipper',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: FlipperOriginalColors.flipperScreenBorder, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: FlipperOriginalColors.flipperScreenBorder, width: 2),
                      borderRadius: BorderRadius.circular(12),
                      color: FlipperOriginalColors.flipperScreenBackground,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: SvgPicture.asset(
                      'assets/flipper_svg/screenstreaming/pic_not_connected_light.svg',
                      fit: BoxFit.fitWidth,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SvgPicture.asset(
                  'assets/flipper_svg/screenstreaming/ic_flipper_logo.svg',
                  width: 183,
                  height: 22,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteOptionButton extends StatelessWidget {
  const _RemoteOptionButton({
    required this.asset,
    required this.label,
  });

  final String asset;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: FlipperOriginalColors.flipperScreenOptionsBackground,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: SvgPicture.asset(asset),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
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
    required this.onPress,
    required this.onLongPress,
  });

  final Future<void> Function(RemoteButton button) onPress;
  final Future<void> Function(RemoteButton button) onLongPress;

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
                    Expanded(child: SizedBox.shrink()),
                    Expanded(
                      child: _RemotePadButton(
                        button: RemoteButton.up,
                        asset: 'assets/flipper_svg/screenstreaming/ic_control_up.svg',
                        onPress: onPress,
                        onLongPress: onLongPress,
                      ),
                    ),
                    Expanded(child: SizedBox.shrink()),
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
                        onPress: onPress,
                        onLongPress: onLongPress,
                      ),
                    ),
                    Expanded(
                      child: _RemotePadButton(
                        button: RemoteButton.ok,
                        asset: 'assets/flipper_svg/screenstreaming/ic_control_ok.svg',
                        onPress: onPress,
                        onLongPress: onLongPress,
                      ),
                    ),
                    Expanded(
                      child: _RemotePadButton(
                        button: RemoteButton.right,
                        asset: 'assets/flipper_svg/screenstreaming/ic_control_right.svg',
                        onPress: onPress,
                        onLongPress: onLongPress,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: SizedBox.shrink()),
                    Expanded(
                      child: _RemotePadButton(
                        button: RemoteButton.down,
                        asset: 'assets/flipper_svg/screenstreaming/ic_control_down.svg',
                        onPress: onPress,
                        onLongPress: onLongPress,
                      ),
                    ),
                    Expanded(child: SizedBox.shrink()),
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
    required this.onPress,
    required this.onLongPress,
  });

  final RemoteButton button;
  final String asset;
  final Future<void> Function(RemoteButton button) onPress;
  final Future<void> Function(RemoteButton button) onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onPress(button);
      },
      onLongPress: () {
        onLongPress(button);
      },
      child: Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: SvgPicture.asset(asset)),
        ),
      ),
    );
  }
}

class _RemoteBackButton extends StatelessWidget {
  const _RemoteBackButton({
    required this.onPress,
    required this.onLongPress,
  });

  final Future<void> Function() onPress;
  final Future<void> Function() onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        onPress();
      },
      onLongPress: () {
        onLongPress();
      },
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
            child: SvgPicture.asset('assets/flipper_svg/screenstreaming/ic_control_back.svg'),
          ),
        ),
      ),
    );
  }
}
