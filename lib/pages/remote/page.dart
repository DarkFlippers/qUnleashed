import 'dart:async';
import 'dart:math' as math;
import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../../theme.dart';
import 'models/models.dart';
import 'widgets/action_button.dart';
import 'widgets/controls.dart';
import 'widgets/view.dart';

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

  // All button inputs are serialized through this chain so PRESS/SHORT/RELEASE
  // sequences from concurrent taps never interleave on the device.
  Future<void> _inputChain = Future<void>.value();

  ui.Image? _frameImage;
  Uint8List? _lastPngBytes;
  final List<QueuedButton> _buttonQueue = [];
  StreamOrientation _orientation = StreamOrientation.horizontal;
  bool _isLocked = true;
  bool _isSavingScreenshot = false;
  bool _isClosing = false;

  // Tracks which buttons are currently held via touch long-press so that
  // a second finger on the same button does not re-send PRESS.
  final Set<RemoteButton> _heldButtons = {};

  // ──────────────────────────── lifecycle ────────────────────────────

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
    if (!_isClosing) unawaited(_stopRemoteSession());
    super.dispose();
  }

  // ──────────────────────────── session ──────────────────────────────

  Future<void> _startRemoteSession() async {
    try {
      await _client.guiStartScreenStream();
      await _client.desktopStatusSubscribe();
      final frames = await _client.desktopIsLocked();
      for (final frame in frames) {
        if (frame.hasDesktopStatus()) _onStatus(frame.desktopStatus);
      }
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
    if (mounted) Navigator.of(context).pop();
  }

  // ──────────────────────────── status ───────────────────────────────

  void _onStatus(Status status) {
    if (!mounted) return;
    setState(() => _isLocked = status.locked);
  }

  // ──────────────────────────── frame decoding ───────────────────────

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
    final bg = FlipperOriginalColors.flipperScreenBackground.toARGB32();
    final fg = FlipperOriginalColors.flipperScreenBorder.toARGB32();

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
          StreamOrientation.horizontalFlip || StreamOrientation.verticalFlip =>
            _screenWidth - x - 1,
          _ => x,
        };
        final bitmapY = switch (orientation) {
          StreamOrientation.horizontalFlip || StreamOrientation.verticalFlip =>
            _screenHeight - y - 1,
          _ => y,
        };

        final pi = ((bitmapY * _screenWidth) + bitmapX) * 4;
        final color = isSet ? fg : bg;
        pixels[pi] = (color >> 16) & 0xFF;
        pixels[pi + 1] = (color >> 8) & 0xFF;
        pixels[pi + 2] = color & 0xFF;
        pixels[pi + 3] = (color >> 24) & 0xFF;
      }
    }

    final image = await _imageFromPixels(pixels, width: _screenWidth, height: _screenHeight);
    final pngBytes =
        (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    return DecodedFrame(image: image, pngBytes: pngBytes, orientation: orientation);
  }

  Future<ui.Image> _imageFromPixels(Uint8List pixels, {required int width, required int height}) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  void _disposeFrame() {
    _frameImage?.dispose();
    _frameImage = null;
  }

  // ──────────────────────────── input ────────────────────────────────

  InputKey _mapButton(RemoteButton button) => switch (button) {
        RemoteButton.up => InputKey.UP,
        RemoteButton.down => InputKey.DOWN,
        RemoteButton.left => InputKey.LEFT,
        RemoteButton.right => InputKey.RIGHT,
        RemoteButton.ok => InputKey.OK,
        RemoteButton.back => InputKey.BACK,
      };

  String _queueAsset(RemoteButton button) => switch (button) {
        RemoteButton.up =>
          'assets/flipper_svg/screenstreaming/ic_anim_up_button_light.svg',
        RemoteButton.down =>
          'assets/flipper_svg/screenstreaming/ic_anim_down_button_light.svg',
        RemoteButton.left =>
          'assets/flipper_svg/screenstreaming/ic_anim_left_button_light.svg',
        RemoteButton.right =>
          'assets/flipper_svg/screenstreaming/ic_anim_right_button_light.svg',
        RemoteButton.ok =>
          'assets/flipper_svg/screenstreaming/ic_anim_ok_button_light.svg',
        RemoteButton.back =>
          'assets/flipper_svg/screenstreaming/ic_anim_back_button_light.svg',
      };

  // Single entry point for all tap/keyboard inputs.
  // Serializes PRESS → type → RELEASE through _inputChain so sequences
  // from rapid taps never interleave.
  Future<void> _sendInput(RemoteButton button, InputType type) async {
    _showQueuedButton(_queueAsset(button));
    final key = _mapButton(button);
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

  // Used only for touch long-press (hold) gestures on the D-pad.
  Future<void> _startHold(RemoteButton button) async {
    if (!_heldButtons.add(button)) return;
    _showQueuedButton(_queueAsset(button));
    await _sendRawInput(_mapButton(button), InputType.PRESS);
  }

  Future<void> _endHold(RemoteButton button) async {
    if (!_heldButtons.remove(button)) return;
    await _sendRawInput(_mapButton(button), InputType.RELEASE);
  }

  Future<void> _sendRawInput(InputKey key, InputType type) async {
    await _client.guiSendInput(SendInputEventRequest(key: key, type: type));
  }

  // ──────────────────────────── unlock ───────────────────────────────

  Future<void> _unlock() async {
    _showQueuedButton('assets/flipper_svg/screenstreaming/ic_anim_unlock_light.svg');
    await _client.desktopUnlock(UnlockRequest());
    try {
      final frames = await _client.desktopIsLocked();
      for (final frame in frames) {
        if (frame.hasDesktopStatus()) _onStatus(frame.desktopStatus);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLocked = false);
    }
  }

  // ──────────────────────────── queue UI ─────────────────────────────

  void _showQueuedButton(String asset) {
    final item = QueuedButton(asset: asset);
    setState(() => _buttonQueue.add(item));
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() => _buttonQueue.removeWhere((e) => e.id == item.id));
    });
  }

  // ──────────────────────────── keyboard ─────────────────────────────

  // Keyboard uses the same SHORT path as button taps so the device receives a
  // valid PRESS → SHORT → RELEASE sequence. KeyRepeatEvent allows holding a
  // key for continuous navigation.
  static final _keyToButton = <LogicalKeyboardKey, RemoteButton>{
    LogicalKeyboardKey.keyW: RemoteButton.up,
    LogicalKeyboardKey.arrowUp: RemoteButton.up,
    LogicalKeyboardKey.keyA: RemoteButton.left,
    LogicalKeyboardKey.arrowLeft: RemoteButton.left,
    LogicalKeyboardKey.keyS: RemoteButton.down,
    LogicalKeyboardKey.arrowDown: RemoteButton.down,
    LogicalKeyboardKey.keyD: RemoteButton.right,
    LogicalKeyboardKey.arrowRight: RemoteButton.right,
    LogicalKeyboardKey.space: RemoteButton.ok,
    LogicalKeyboardKey.enter: RemoteButton.ok,
    LogicalKeyboardKey.numpadEnter: RemoteButton.ok,
    LogicalKeyboardKey.escape: RemoteButton.back,
    LogicalKeyboardKey.backspace: RemoteButton.back,
  };

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    final button = _keyToButton[event.logicalKey];
    if (button == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      unawaited(_sendInput(button, InputType.SHORT));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ──────────────────────────── screenshot ───────────────────────────

  Future<void> _copyScreenshot() async {
    final png = _lastPngBytes;
    if (png == null || _isSavingScreenshot) return;
    setState(() => _isSavingScreenshot = true);
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) throw StateError('Clipboard not available');
      final item = DataWriterItem()..add(Formats.png(png));
      await clipboard.write([item]);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Screenshot copied to clipboard')));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Screenshot saved: $path')));
    } finally {
      if (mounted) setState(() => _isSavingScreenshot = false);
    }
  }

  Future<String> _saveScreenshotToPictures(Uint8List png) async {
    final fileName = 'flipper_screenshot_${DateTime.now().millisecondsSinceEpoch}.png';

    if (io.Platform.isAndroid || io.Platform.isIOS) {
      if (!await _ensureGalleryPermission()) throw StateError('Gallery permission denied');
      await SaverGallery.saveImage(
        png,
        quality: 100,
        fileName: fileName,
        skipIfExists: false,
        androidRelativePath: 'Pictures/Qunleashed',
      );
      return io.Platform.isAndroid ? 'Pictures/Qunleashed/$fileName' : 'Photos';
    }

    final dir = _systemPicturesDirectory();
    await dir.create(recursive: true);
    final sep = io.Platform.pathSeparator;
    final file = io.File('${dir.path}$sep$fileName');
    await file.writeAsBytes(png, flush: true);
    return file.path;
  }

  Future<bool> _ensureGalleryPermission() async {
    if (io.Platform.isIOS) {
      final s = await Permission.photosAddOnly.request();
      return s.isGranted || s.isLimited;
    }
    if (io.Platform.isAndroid) {
      final photos = await Permission.photos.request();
      if (photos.isGranted || photos.isLimited) return true;
      return (await Permission.storage.request()).isGranted;
    }
    return true;
  }

  io.Directory _systemPicturesDirectory() {
    final picturesEnv = io.Platform.environment['XDG_PICTURES_DIR'];
    if (picturesEnv != null && picturesEnv.isNotEmpty) return io.Directory(picturesEnv);
    final userProfile = io.Platform.environment['USERPROFILE'];
    if (io.Platform.isWindows && userProfile != null && userProfile.isNotEmpty) {
      return io.Directory('$userProfile\\Pictures');
    }
    final home = io.Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) return io.Directory('$home/Pictures');
    return io.Directory.current;
  }

  // ──────────────────────────── build ────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final topInset = MediaQuery.paddingOf(context).top;
    final isVertical =
        _orientation == StreamOrientation.vertical || _orientation == StreamOrientation.verticalFlip;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => _closePage(),
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => _handleKeyEvent(event),
        child: Scaffold(
          backgroundColor: colors.background,
          body: Column(
            children: [
              Container(
                color: colors.accent,
                padding: EdgeInsets.only(top: topInset),
                child: SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _closePage,
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
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final controlsHeight = isVertical
                        ? math.min(150.0, constraints.maxHeight * 0.28)
                        : math.min(174.0, constraints.maxHeight * 0.32);
                    final horizontalPadding = isVertical ? 12.0 : 24.0;

                    return Column(
                      children: [
                        Expanded(
                          child: SafeArea(
                            top: false,
                            bottom: false,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                horizontalPadding,
                                14,
                                horizontalPadding,
                                8,
                              ),
                              child: Column(
                                children: [
                                  Padding(
                                    padding: EdgeInsets.symmetric(horizontal: isVertical ? 0 : 12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Center(
                                            child: RemoteControlActionButton(
                                              icon: Icons.copy_rounded,
                                              label: _isSavingScreenshot ? 'Saving' : 'Copy',
                                              onTap: _copyScreenshot,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Center(
                                            child: RemoteControlActionButton(
                                              icon: Icons.download_rounded,
                                              label: _isSavingScreenshot ? 'Saving' : 'Save',
                                              onTap: _saveScreenshot,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Center(
                                            child: RemoteControlActionButton(
                                              asset: _isLocked
                                                  ? 'assets/flipper_svg/screenstreaming/ic_unlock.svg'
                                                  : 'assets/flipper_svg/screenstreaming/ic_lock.svg',
                                              label: _isLocked ? 'Unlock' : 'Unlocked',
                                              onTap: _isLocked ? _unlock : null,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Expanded(
                                    child: RemoteControlView(
                                      image: _frameImage,
                                      queue: _buttonQueue,
                                      orientation: _orientation,
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
                                onTapButton: (button) => _sendInput(button, InputType.SHORT),
                                onHoldButtonStart: _startHold,
                                onHoldButtonEnd: _endHold,
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
}
