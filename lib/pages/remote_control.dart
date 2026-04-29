import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flipperzero/flipperzero.dart' hide DateTime, File;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/discovered_device.dart';
import '../services/flipper_protocol.dart';
import '../widgets/device_shell.dart';

enum RemoteButton { up, down, left, right, ok, back }

enum _StreamOrientation {
  horizontal,
  horizontalFlip,
  vertical,
  verticalFlip,
}

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({
    super.key,
    required this.device,
  });

  final ConnectedDevice device;

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  static const int _screenWidth = 128;
  static const int _screenHeight = 64;
  static const int _backgroundColor = 0xFFFF8C29;
  static const Duration _shortReleaseDelay = Duration(milliseconds: 60);
  static const Duration _longReleaseDelay = Duration(milliseconds: 140);

  StreamSubscription<List<int>>? _dataSub;
  final _buffer = FlipperFrameBuffer();
  Future<void> _inputChain = Future<void>.value();

  ui.Image? _frameImage;
  Uint8List? _lastPngBytes;
  final List<_QueuedButton> _buttonQueue = [];
  _StreamOrientation _orientation = _StreamOrientation.horizontal;
  bool _isStreaming = false;
  bool _isLocked = true;
  bool _lockReady = false;
  bool _isSavingScreenshot = false;

  @override
  void initState() {
    super.initState();
    _dataSub = widget.device.dataStream.listen(_onData);
    _startRemoteSession();
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _disposeFrame();
    _stopRemoteSession();
    super.dispose();
  }

  Future<void> _startRemoteSession() async {
    await widget.device.sendBytes(
      FlipperProtocol.encode(
        Main(
          commandId: FlipperProtocol.nextCommandId(),
          guiStartScreenStreamRequest: StartScreenStreamRequest(),
        ),
      ),
    );
    await widget.device.sendBytes(
      FlipperProtocol.encode(
        Main(
          commandId: FlipperProtocol.nextCommandId(),
          desktopStatusSubscribeRequest: StatusSubscribeRequest(),
        ),
      ),
    );
    await widget.device.sendBytes(
      FlipperProtocol.encode(
        Main(
          commandId: FlipperProtocol.nextCommandId(),
          desktopIsLockedRequest: IsLockedRequest(),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _isStreaming = true);
  }

  Future<void> _stopRemoteSession() async {
    await widget.device.sendBytes(
      FlipperProtocol.encode(
        Main(
          commandId: FlipperProtocol.nextCommandId(),
          guiStopScreenStreamRequest: StopScreenStreamRequest(),
        ),
      ),
    );
    await widget.device.sendBytes(
      FlipperProtocol.encode(
        Main(
          commandId: FlipperProtocol.nextCommandId(),
          desktopStatusUnsubscribeRequest: StatusUnsubscribeRequest(),
        ),
      ),
    );
  }

  void _onData(List<int> raw) {
    final messages = _buffer.push(raw);
    for (final msg in messages) {
      _handleMessage(msg);
    }
  }

  void _handleMessage(Main msg) {
    switch (msg.whichContent()) {
      case Main_Content.guiScreenFrame:
        _updateFrame(msg.guiScreenFrame);
        break;
      case Main_Content.desktopStatus:
        if (!mounted) return;
        setState(() {
          _isLocked = msg.desktopStatus.locked;
          _lockReady = true;
        });
        break;
      default:
        break;
    }
  }

  Future<void> _updateFrame(ScreenFrame frame) async {
    final decoded = await _decodeFrame(frame);
    if (!mounted) {
      decoded.image.dispose();
      return;
    }
    final previous = _frameImage;
    setState(() {
      _frameImage = decoded.image;
      _lastPngBytes = decoded.pngBytes;
      _orientation = decoded.orientation;
    });
    previous?.dispose();
  }

  Future<_DecodedFrame> _decodeFrame(ScreenFrame frame) async {
    final pixels = Uint8List(_screenWidth * _screenHeight * 4);
    final raw = frame.data;

    final orientation = switch (frame.orientation) {
      ScreenOrientation.HORIZONTAL => _StreamOrientation.horizontal,
      ScreenOrientation.HORIZONTAL_FLIP => _StreamOrientation.horizontalFlip,
      ScreenOrientation.VERTICAL => _StreamOrientation.vertical,
      ScreenOrientation.VERTICAL_FLIP => _StreamOrientation.verticalFlip,
      _ => _StreamOrientation.horizontal,
    };

    for (var x = 0; x < _screenWidth; x++) {
      for (var y = 0; y < _screenHeight; y++) {
        final idx = ((y ~/ 8) * _screenWidth) + x;
        final bit = 1 << (y & 7);
        final isSet = idx < raw.length && (raw[idx] & bit) != 0;

        final bitmapX = switch (orientation) {
          _StreamOrientation.horizontalFlip => _screenWidth - x - 1,
          _StreamOrientation.verticalFlip => _screenWidth - x - 1,
          _ => x,
        };
        final bitmapY = switch (orientation) {
          _StreamOrientation.horizontalFlip => _screenHeight - y - 1,
          _StreamOrientation.verticalFlip => _screenHeight - y - 1,
          _ => y,
        };

        final pixelIndex = ((bitmapY * _screenWidth) + bitmapX) * 4;
        final color = isSet ? 0xFF000000 : _backgroundColor;
        pixels[pixelIndex] = (color >> 16) & 0xFF;
        pixels[pixelIndex + 1] = (color >> 8) & 0xFF;
        pixels[pixelIndex + 2] = color & 0xFF;
        pixels[pixelIndex + 3] = (color >> 24) & 0xFF;
      }
    }

    final image = await _imageFromPixels(
      pixels,
      width: _screenWidth,
      height: _screenHeight,
    );
    final pngBytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    return _DecodedFrame(
      image: image,
      pngBytes: pngBytes,
      orientation: orientation,
    );
  }

  Future<ui.Image> _imageFromPixels(
    Uint8List pixels, {
    required int width,
    required int height,
  }) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Future<void> _sendInput(RemoteButton button, InputType type) async {
    _showQueuedButton(_queueAssetForButton(button));
    final key = switch (button) {
      RemoteButton.up => InputKey.UP,
      RemoteButton.down => InputKey.DOWN,
      RemoteButton.left => InputKey.LEFT,
      RemoteButton.right => InputKey.RIGHT,
      RemoteButton.ok => InputKey.OK,
      RemoteButton.back => InputKey.BACK,
    };
    _inputChain = _inputChain.then((_) async {
      await _sendRawInput(key, InputType.PRESS);
      await _sendRawInput(key, type);
      await Future<void>.delayed(type == InputType.LONG ? _longReleaseDelay : _shortReleaseDelay);
      await _sendRawInput(key, InputType.RELEASE);
    });
    await _inputChain;
  }

  Future<void> _unlock() async {
    _showQueuedButton('assets/flipper_svg/screenstreaming/ic_anim_unlock_light.svg');
    await widget.device.sendBytes(
      FlipperProtocol.encode(
        Main(
          commandId: FlipperProtocol.nextCommandId(),
          desktopUnlockRequest: UnlockRequest(),
        ),
      ),
    );
  }

  void _showQueuedButton(String asset) {
    final item = _QueuedButton(asset: asset);
    setState(() => _buttonQueue.add(item));
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() => _buttonQueue.removeWhere((element) => element.id == item.id));
    });
  }

  String _queueAssetForButton(RemoteButton button) => switch (button) {
        RemoteButton.up => 'assets/flipper_svg/screenstreaming/ic_anim_up_button_light.svg',
        RemoteButton.down => 'assets/flipper_svg/screenstreaming/ic_anim_down_button_light.svg',
        RemoteButton.left => 'assets/flipper_svg/screenstreaming/ic_anim_left_button_light.svg',
        RemoteButton.right => 'assets/flipper_svg/screenstreaming/ic_anim_right_button_light.svg',
        RemoteButton.ok => 'assets/flipper_svg/screenstreaming/ic_anim_ok_button_light.svg',
        RemoteButton.back => 'assets/flipper_svg/screenstreaming/ic_anim_back_button_light.svg',
      };

  Future<void> _sendRawInput(InputKey key, InputType type) async {
    final req = SendInputEventRequest(
      key: key,
      type: type,
    );
    await widget.device.sendBytes(
      FlipperProtocol.encode(
        Main(
          commandId: FlipperProtocol.nextCommandId(),
          guiSendInputEventRequest: req,
        ),
      ),
    );
  }

  Future<void> _saveScreenshot() async {
    final png = _lastPngBytes;
    if (png == null || _isSavingScreenshot) return;
    setState(() => _isSavingScreenshot = true);
    try {
      final file = io.File(
        '${io.Directory.systemTemp.path}/flipper_screenshot_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(png, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Screenshot saved: ${file.path}')),
      );
    } finally {
      if (mounted) setState(() => _isSavingScreenshot = false);
    }
  }

  void _disposeFrame() {
    _frameImage?.dispose();
    _frameImage = null;
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
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
                      child: _RemoteScreenWithOptions(
                        image: _frameImage,
                        queue: _buttonQueue,
                        orientation: _orientation,
                        isLocked: _isLocked,
                        lockReady: _lockReady,
                        isSavingScreenshot: _isSavingScreenshot,
                        onTakeScreenshot: _saveScreenshot,
                        onToggleLock: _unlock,
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
                          onPress: (button) => _sendInput(button, InputType.SHORT),
                          onLongPress: (button) => _sendInput(button, InputType.LONG),
                        ),
                        const SizedBox(width: 30),
                        _RemoteBackButton(
                          onPress: () => _sendInput(RemoteButton.back, InputType.SHORT),
                          onLongPress: () => _sendInput(RemoteButton.back, InputType.LONG),
                        ),
                      ],
                    ),
                  ),
                  if (_isStreaming)
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DecodedFrame {
  const _DecodedFrame({
    required this.image,
    required this.pngBytes,
    required this.orientation,
  });

  final ui.Image image;
  final Uint8List pngBytes;
  final _StreamOrientation orientation;
}

class _QueuedButton {
  _QueuedButton({required this.asset}) : id = DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  final String asset;
}

class _RemoteScreenWithOptions extends StatelessWidget {
  const _RemoteScreenWithOptions({
    required this.image,
    required this.queue,
    required this.orientation,
    required this.isLocked,
    required this.lockReady,
    required this.isSavingScreenshot,
    required this.onTakeScreenshot,
    required this.onToggleLock,
  });

  final ui.Image? image;
  final List<_QueuedButton> queue;
  final _StreamOrientation orientation;
  final bool isLocked;
  final bool lockReady;
  final bool isSavingScreenshot;
  final VoidCallback onTakeScreenshot;
  final VoidCallback onToggleLock;

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
                    asset: 'assets/flipper_svg/screenstreaming/ic_camera.svg',
                    label: isSavingScreenshot ? 'Saving...' : 'Screenshot',
                    onTap: onTakeScreenshot,
                  ),
                  _RemoteOptionButton(
                    asset: isLocked
                        ? 'assets/flipper_svg/screenstreaming/ic_unlock.svg'
                        : 'assets/flipper_svg/screenstreaming/ic_lock.svg',
                    label: !lockReady
                        ? 'Loading...'
                        : isLocked
                            ? 'Unlock Flipper'
                            : 'Unlocked',
                    onTap: onToggleLock,
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
        child: SvgPicture.asset(widget.asset),
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
  final _StreamOrientation orientation;

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return SvgPicture.asset(
        'assets/flipper_svg/screenstreaming/pic_not_connected_light.svg',
        fit: BoxFit.fitWidth,
      );
    }

    final quarterTurns = switch (orientation) {
      _StreamOrientation.vertical => 1,
      _StreamOrientation.verticalFlip => 1,
      _ => 0,
    };

    final aspectRatio = quarterTurns == 0 ? (_screenWidth / _screenHeight) : (_screenHeight / _screenWidth);

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
    required this.asset,
    required this.label,
    required this.onTap,
  });

  final String asset;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: FlipperOriginalColors.flipperScreenOptionsBackground,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: SvgPicture.asset(asset),
          ),
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
                    const Expanded(child: SizedBox.shrink()),
                    Expanded(
                      child: _RemotePadButton(
                        button: RemoteButton.up,
                        asset: 'assets/flipper_svg/screenstreaming/ic_control_up.svg',
                        onPress: onPress,
                        onLongPress: onLongPress,
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
                    const Expanded(child: SizedBox.shrink()),
                    Expanded(
                      child: _RemotePadButton(
                        button: RemoteButton.down,
                        asset: 'assets/flipper_svg/screenstreaming/ic_control_down.svg',
                        onPress: onPress,
                        onLongPress: onLongPress,
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
      onTap: () => onPress(button),
      onLongPress: () => onLongPress(button),
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
      onTap: onPress,
      onLongPress: onLongPress,
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
