import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../../theme.dart';
import 'remote_control_models.dart';
import 'widgets/remote_control_view.dart';

class RemoteControlPage extends StatefulWidget {
  const RemoteControlPage({super.key});

  @override
  State<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _RemoteControlPageState extends State<RemoteControlPage> {
  static const int _screenWidth = 128;
  static const int _screenHeight = 64;
  static const Duration _shortReleaseDelay = Duration(milliseconds: 60);
  static const Duration _longReleaseDelay = Duration(milliseconds: 140);

  final FlipperClient _client = FlipperOneClient().get();

  StreamSubscription<ScreenFrame>? _frameSub;
  StreamSubscription<Status>? _statusSub;
  Future<void> _inputChain = Future<void>.value();

  ui.Image? _frameImage;
  Uint8List? _lastPngBytes;
  final List<QueuedButton> _buttonQueue = [];
  StreamOrientation _orientation = StreamOrientation.horizontal;
  bool _isStreaming = false;
  bool _isLocked = true;
  bool _lockReady = false;
  bool _isSavingScreenshot = false;
  bool _isClosing = false;
  final Set<RemoteButton> _heldButtons = {};
  bool _backHeld = false;
  bool _okHeld = false;

  @override
  void initState() {
    super.initState();
    _frameSub = _client.screenFrameStream().listen(_updateFrame);
    _statusSub = _client.desktopStatusStream().listen(_onStatus);
    _startRemoteSession();
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _statusSub?.cancel();
    _disposeFrame();
    if (!_isClosing) {
      unawaited(_stopRemoteSession());
    }
    super.dispose();
  }

  Future<void> _startRemoteSession() async {
    try {
      await _client.guiStartScreenStream();
      await _client.desktopStatusSubscribe();
      final frames = await _client.desktopIsLocked();
      for (final frame in frames) {
        if (frame.hasDesktopStatus()) {
          _onStatus(frame.desktopStatus);
        }
      }
      if (!mounted) return;
      setState(() => _isStreaming = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Remote control unavailable: $e')),
      );
    }
  }

  Future<void> _stopRemoteSession() async {
    try {
      await _client.guiStopScreenStream();
      await _client.desktopStatusUnsubscribe();
    } catch (_) {}
  }

  Future<void> _closePage() async {
    if (_isClosing) return;
    _isClosing = true;
    await _stopRemoteSession();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _onStatus(Status status) {
    if (!mounted) return;
    setState(() {
      _isLocked = status.locked;
      _lockReady = true;
    });
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
      await Future<void>.delayed(
        type == InputType.LONG ? _longReleaseDelay : _shortReleaseDelay,
      );
      await _sendRawInput(key, InputType.RELEASE);
    });
    await _inputChain;
  }

  Future<void> _startHold(RemoteButton button) async {
    if (!_heldButtons.add(button)) return;
    _showQueuedButton(_queueAssetForButton(button));
    await _sendRawInput(_mapButton(button), InputType.PRESS);
  }

  Future<void> _endHold(RemoteButton button) async {
    if (!_heldButtons.remove(button)) return;
    await _sendRawInput(_mapButton(button), InputType.RELEASE);
  }

  Future<void> _startBackHold() async {
    if (_backHeld) return;
    _backHeld = true;
    _showQueuedButton(_queueAssetForButton(RemoteButton.back));
    await _sendRawInput(InputKey.BACK, InputType.PRESS);
  }

  Future<void> _endBackHold() async {
    if (!_backHeld) return;
    _backHeld = false;
    await _sendRawInput(InputKey.BACK, InputType.RELEASE);
  }

  Future<void> _startOkHold() async {
    if (_okHeld) return;
    _okHeld = true;
    _showQueuedButton(_queueAssetForButton(RemoteButton.ok));
    await _sendRawInput(InputKey.OK, InputType.PRESS);
  }

  Future<void> _endOkHold() async {
    if (!_okHeld) return;
    _okHeld = false;
    await _sendRawInput(InputKey.OK, InputType.RELEASE);
  }

  Future<void> _unlock() async {
    _showQueuedButton('assets/flipper_svg/screenstreaming/ic_anim_unlock_light.svg');
    await _client.desktopUnlock(UnlockRequest());
    try {
      final frames = await _client.desktopIsLocked();
      for (final frame in frames) {
        if (frame.hasDesktopStatus()) {
          _onStatus(frame.desktopStatus);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLocked = false;
        _lockReady = true;
      });
    }
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

  InputKey _mapButton(RemoteButton button) => switch (button) {
        RemoteButton.up => InputKey.UP,
        RemoteButton.down => InputKey.DOWN,
        RemoteButton.left => InputKey.LEFT,
        RemoteButton.right => InputKey.RIGHT,
        RemoteButton.ok => InputKey.OK,
        RemoteButton.back => InputKey.BACK,
      };

  Future<void> _sendRawInput(InputKey key, InputType type) async {
    await _client.guiSendInput(
      SendInputEventRequest(
        key: key,
        type: type,
      ),
    );
  }

  Future<void> _copyScreenshot() async {
    final png = _lastPngBytes;
    if (png == null || _isSavingScreenshot) return;
    setState(() => _isSavingScreenshot = true);
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        throw StateError('Clipboard is not available on this platform');
      }
      final item = DataWriterItem();
      item.add(Formats.png(png));
      await clipboard.write([item]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Screenshot copied to clipboard')),
      );
    } finally {
      if (mounted) setState(() => _isSavingScreenshot = false);
    }
  }

  Future<void> _saveScreenshot() async {
    final png = _lastPngBytes;
    if (png == null || _isSavingScreenshot) return;
    setState(() => _isSavingScreenshot = true);
    try {
      final path = await _saveScreenshotToPictures(png);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Screenshot saved: $path')),
      );
    } finally {
      if (mounted) setState(() => _isSavingScreenshot = false);
    }
  }

  Future<String> _saveScreenshotToPictures(Uint8List png) async {
    final fileName = 'flipper_screenshot_${DateTime.now().millisecondsSinceEpoch}.png';

    if (io.Platform.isAndroid || io.Platform.isIOS) {
      final granted = await _ensureGalleryPermission();
      if (!granted) {
        throw StateError('Gallery permission denied');
      }
      await SaverGallery.saveImage(
        png,
        quality: 100,
        fileName: fileName,
        skipIfExists: false,
        androidRelativePath: 'Pictures/Qunleashed',
      );
      return io.Platform.isAndroid ? 'Pictures/Qunleashed/$fileName' : 'Photos';
    }

    final picturesDir = _systemPicturesDirectory();
    await picturesDir.create(recursive: true);
    final file = io.File(io.Platform.pathSeparator == '\\'
        ? '${picturesDir.path}\\$fileName'
        : '${picturesDir.path}/$fileName');
    await file.writeAsBytes(png, flush: true);
    return file.path;
  }

  Future<bool> _ensureGalleryPermission() async {
    if (io.Platform.isIOS) {
      final status = await Permission.photosAddOnly.request();
      return status.isGranted || status.isLimited;
    }
    if (io.Platform.isAndroid) {
      final photos = await Permission.photos.request();
      if (photos.isGranted || photos.isLimited) return true;
      final storage = await Permission.storage.request();
      return storage.isGranted;
    }
    return true;
  }

  io.Directory _systemPicturesDirectory() {
    final home = io.Platform.environment['HOME'];
    final userProfile = io.Platform.environment['USERPROFILE'];
    final picturesEnv = io.Platform.environment['XDG_PICTURES_DIR'];

    if (picturesEnv != null && picturesEnv.isNotEmpty) {
      return io.Directory(picturesEnv);
    }
    if (io.Platform.isWindows && userProfile != null && userProfile.isNotEmpty) {
      return io.Directory('$userProfile\\Pictures');
    }
    if (home != null && home.isNotEmpty) {
      return io.Directory('$home/Pictures');
    }
    return io.Directory.current;
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    final logical = event.logicalKey;

    if (event is KeyDownEvent) {
      if (logical == LogicalKeyboardKey.keyW ||
          logical == LogicalKeyboardKey.arrowUp) {
        unawaited(_startHold(RemoteButton.up));
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.keyA ||
          logical == LogicalKeyboardKey.arrowLeft) {
        unawaited(_startHold(RemoteButton.left));
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.keyS ||
          logical == LogicalKeyboardKey.arrowDown) {
        unawaited(_startHold(RemoteButton.down));
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.keyD ||
          logical == LogicalKeyboardKey.arrowRight) {
        unawaited(_startHold(RemoteButton.right));
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.space ||
          logical == LogicalKeyboardKey.enter ||
          logical == LogicalKeyboardKey.numpadEnter) {
        unawaited(_startOkHold());
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.escape ||
          logical == LogicalKeyboardKey.backspace) {
        unawaited(_startBackHold());
        return KeyEventResult.handled;
      }
    }

    if (event is KeyUpEvent) {
      if (logical == LogicalKeyboardKey.keyW ||
          logical == LogicalKeyboardKey.arrowUp) {
        unawaited(_endHold(RemoteButton.up));
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.keyA ||
          logical == LogicalKeyboardKey.arrowLeft) {
        unawaited(_endHold(RemoteButton.left));
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.keyS ||
          logical == LogicalKeyboardKey.arrowDown) {
        unawaited(_endHold(RemoteButton.down));
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.keyD ||
          logical == LogicalKeyboardKey.arrowRight) {
        unawaited(_endHold(RemoteButton.right));
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.space ||
          logical == LogicalKeyboardKey.enter ||
          logical == LogicalKeyboardKey.numpadEnter) {
        unawaited(_endOkHold());
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.escape ||
          logical == LogicalKeyboardKey.backspace) {
        unawaited(_endBackHold());
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
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
      onCopyScreenshot: _copyScreenshot,
      onSaveScreenshot: _saveScreenshot,
      onUnlock: _unlock,
      onTapButton: (button) => _sendInput(button, InputType.SHORT),
      onHoldButtonStart: _startHold,
      onHoldButtonEnd: _endHold,
      onTapBack: () => _sendInput(RemoteButton.back, InputType.SHORT),
      onHoldBackStart: _startBackHold,
      onHoldBackEnd: _endBackHold,
      onClose: _closePage,
      onKeyEvent: _handleKeyEvent,
    );
  }
}
