import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flipperzero/flipperzero.dart' hide DateTime, File;
import 'package:flutter/material.dart';

import '../../models/discovered_device.dart';
import '../../services/flipper_protocol.dart';
import '../../theme.dart';
import 'remote_control_models.dart';
import 'widgets/remote_control_view.dart';

class RemoteControlPage extends StatefulWidget {
  const RemoteControlPage({
    super.key,
    required this.device,
  });

  final ConnectedDevice device;

  @override
  State<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _RemoteControlPageState extends State<RemoteControlPage> {
  static const int _screenWidth = 128;
  static const int _screenHeight = 64;
  static const Duration _shortReleaseDelay = Duration(milliseconds: 60);
  static const Duration _longReleaseDelay = Duration(milliseconds: 140);

  StreamSubscription<List<int>>? _dataSub;
  final _buffer = FlipperFrameBuffer();
  Future<void> _inputChain = Future<void>.value();

  ui.Image? _frameImage;
  Uint8List? _lastPngBytes;
  final List<QueuedButton> _buttonQueue = [];
  StreamOrientation _orientation = StreamOrientation.horizontal;
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

  Future<DecodedFrame> _decodeFrame(ScreenFrame frame) async {
    final pixels = Uint8List(_screenWidth * _screenHeight * 4);
    final raw = frame.data;
    final backgroundColor = FlipperOriginalColors.flipperScreenBackground.toARGB32();
    final foregroundColor = FlipperOriginalColors.flipperScreenBorder.toARGB32();

    final orientation = switch (frame.orientation) {
      ScreenOrientation.HORIZONTAL => StreamOrientation.horizontal,
      ScreenOrientation.HORIZONTAL_FLIP => StreamOrientation.horizontalFlip,
      ScreenOrientation.VERTICAL => StreamOrientation.vertical,
      ScreenOrientation.VERTICAL_FLIP => StreamOrientation.verticalFlip,
      _ => StreamOrientation.horizontal,
    };

    for (var x = 0; x < _screenWidth; x++) {
      for (var y = 0; y < _screenHeight; y++) {
        final idx = ((y ~/ 8) * _screenWidth) + x;
        final bit = 1 << (y & 7);
        final isSet = idx < raw.length && (raw[idx] & bit) != 0;

        final bitmapX = switch (orientation) {
          StreamOrientation.horizontalFlip => _screenWidth - x - 1,
          StreamOrientation.verticalFlip => _screenWidth - x - 1,
          _ => x,
        };
        final bitmapY = switch (orientation) {
          StreamOrientation.horizontalFlip => _screenHeight - y - 1,
          StreamOrientation.verticalFlip => _screenHeight - y - 1,
          _ => y,
        };

        final pixelIndex = ((bitmapY * _screenWidth) + bitmapX) * 4;
        final color = isSet ? foregroundColor : backgroundColor;
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
    return DecodedFrame(
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
    final item = QueuedButton(asset: asset);
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
    return RemoteControlView(
      image: _frameImage,
      queue: _buttonQueue,
      orientation: _orientation,
      isLocked: _isLocked,
      lockReady: _lockReady,
      isSavingScreenshot: _isSavingScreenshot,
      isStreaming: _isStreaming,
      onTakeScreenshot: _saveScreenshot,
      onToggleLock: _unlock,
      onPressButton: (button) => _sendInput(button, InputType.SHORT),
      onLongPressButton: (button) => _sendInput(button, InputType.LONG),
      onPressBack: () => _sendInput(RemoteButton.back, InputType.SHORT),
      onLongPressBack: () => _sendInput(RemoteButton.back, InputType.LONG),
    );
  }
}
