import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'codec/bm.dart';

class FlipperScreenAnimation extends StatefulWidget {
  const FlipperScreenAnimation({
    super.key,
    required this.active,
    required this.fg,
    required this.bg,
    this.deadZonePx = 0,
  });

  final bool active;
  final Color fg;
  final Color bg;
  final int deadZonePx;

  @override
  State<FlipperScreenAnimation> createState() => _FlipperScreenAnimationState();
}

class _FlipperScreenAnimationState extends State<FlipperScreenAnimation> {
  static const _animDir = 'assets/anim/L3_Fireplace_128x64';
  static const _statusBarAsset = 'assets/anim/Background_128x11.png';
  static const _statusBarHeight = 11;

  List<ui.Image> _frames = const [];
  ui.Image? _statusBar;
  Timer? _timer;
  int _cursor = 0;
  int _delayMs = 333;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(FlipperScreenAnimation old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _load();
    } else if (!widget.active && old.active) {
      _clear();
    }
  }

  void _clear() {
    _timer?.cancel();
    _timer = null;
    _disposeFrames(_frames);
    _statusBar?.dispose();
    setState(() {
      _frames = const [];
      _statusBar = null;
      _cursor = 0;
    });
  }

  Future<void> _load() async {
    final fg = widget.fg.toARGB32();
    final bg = widget.bg.toARGB32();
    final anim = await _ScreenAnimation.load(_animDir);
    final frames = anim == null
        ? <ui.Image>[]
        : await anim.loadFrames(fg: fg, bg: bg);
    ui.Image? statusBar;
    try {
      final png = await rootBundle.load(_statusBarAsset);
      statusBar = await BmCodec.statusBarPngToImage(
        png.buffer.asUint8List(),
        fg: fg,
        bg: bg,
      );
    } catch (_) {
      statusBar = null;
    }

    if (!mounted || !widget.active) {
      _disposeFrames(frames);
      statusBar?.dispose();
      return;
    }

    _timer?.cancel();
    _disposeFrames(_frames);
    _statusBar?.dispose();
    setState(() {
      _frames = frames;
      _statusBar = statusBar;
      _cursor = 0;
      _delayMs = (anim?.frameDelayMs ?? 333).clamp(33, 2000);
    });
    if (frames.length > 1) {
      _timer = Timer.periodic(Duration(milliseconds: _delayMs), (_) {
        if (!mounted) return;
        setState(() => _cursor = (_cursor + 1) % _frames.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _disposeFrames(_frames);
    _statusBar?.dispose();
    super.dispose();
  }

  static void _disposeFrames(List<ui.Image> frames) {
    final seen = <ui.Image>{};
    for (final img in frames) {
      if (seen.add(img)) img.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.expand();
    final dead = widget.deadZonePx;
    return ColoredBox(
      color: widget.bg,
      child: Center(
        child: FractionallySizedBox(
          widthFactor: (kBmWidth - dead * 2) / kBmWidth,
          heightFactor: (kBmHeight - dead * 2) / kBmHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_frames.isNotEmpty)
                RawImage(
                  image: _frames[_cursor % _frames.length],
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.none,
                ),
              if (_statusBar != null)
                Align(
                  alignment: Alignment.topCenter,
                  child: FractionallySizedBox(
                    widthFactor: 1,
                    heightFactor: _statusBarHeight / kBmHeight,
                    child: RawImage(
                      image: _statusBar,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.none,
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

class _ScreenAnimation {
  _ScreenAnimation._({
    required this.assetDir,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.order,
  });

  final String assetDir;
  final int width;
  final int height;
  final int frameRate;
  final List<int> order;

  int get frameDelayMs => frameRate > 0 ? (1000 / frameRate).round() : 500;

  static Future<_ScreenAnimation?> load(String assetDir) async {
    final String text;
    try {
      text = await rootBundle.loadString('$assetDir/meta.txt');
    } catch (_) {
      return null;
    }

    final passive = BmCodec.parseDolphinInt(text, 'Passive frames') ?? 0;
    final active = BmCodec.parseDolphinInt(text, 'Active frames') ?? 0;

    final orderMatch = RegExp(
      r'^Frames order: (.+)$',
      multiLine: true,
    ).firstMatch(text);
    final order = <int>[];
    final orderStr = orderMatch?.group(1)?.trim() ?? '';
    if (orderStr.isNotEmpty) {
      for (final s in orderStr.split(RegExp(r'\s+'))) {
        final n = int.tryParse(s);
        if (n != null) order.add(n);
      }
    }
    if (order.isEmpty) {
      final count = passive > 0 ? passive : (passive + active);
      for (int i = 0; i < count; i++) {
        order.add(i);
      }
    }
    if (order.isEmpty) return null;

    final passiveOrder = passive > 0 ? order.take(passive).toList() : order;

    return _ScreenAnimation._(
      assetDir: assetDir,
      width: BmCodec.parseDolphinInt(text, 'Width') ?? kBmWidth,
      height: BmCodec.parseDolphinInt(text, 'Height') ?? kBmHeight,
      frameRate: BmCodec.parseDolphinInt(text, 'Frame rate') ?? 2,
      order: passiveOrder,
    );
  }

  Future<Uint8List?> _loadFramePixels(int fileIndex) async {
    try {
      final bytes = await rootBundle.load('$assetDir/frame_$fileIndex.bm');
      final xbm = BmCodec.decodeBmFile(bytes.buffer.asUint8List());
      if (xbm == null || xbm.length < 16) return null;
      return BmCodec.xbmToPixels(xbm, srcWidth: width, srcHeight: height);
    } catch (_) {
      return null;
    }
  }

  Future<List<ui.Image>> loadFrames({int? fg, int? bg}) async {
    final cache = <int, ui.Image>{};
    final frames = <ui.Image>[];
    for (final idx in order) {
      final cached = cache[idx];
      if (cached != null) {
        frames.add(cached);
        continue;
      }
      final pixels = await _loadFramePixels(idx);
      if (pixels == null) continue;
      final img = await BmCodec.frameToImage(pixels, fg: fg, bg: bg);
      cache[idx] = img;
      frames.add(img);
    }
    return frames;
  }
}
