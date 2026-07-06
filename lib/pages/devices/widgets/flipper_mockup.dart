import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../components/codec/bm.dart';
import '../../../theme/theme.dart';
import '../models/device_info.dart';

class FlipperMockupWidget extends StatelessWidget {
  const FlipperMockupWidget({
    super.key,
    required this.active,
    this.dfu = false,
  });

  static const _templateWidth = 238.0;
  static const _templateHeight = 100.0;
  static const _screenLeft = 60.65;
  static const _screenTop = 10.54;
  static const _screenWidth = 85.32;
  static const _screenHeight = 46.95;

  final bool active;

  final bool dfu;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AspectRatio(
      aspectRatio: _templateWidth / _templateHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(
            fit: StackFit.expand,
            children: [
              SvgPicture.asset(
                colors.isDark
                    ? (active
                          ? 'assets/pic/device/body/black-active.svg'
                          : 'assets/pic/device/body/black-disabled.svg')
                    : (active
                          ? 'assets/pic/device/body/white-active.svg'
                          : 'assets/pic/device/body/white-disabled.svg'),
              ),
              Positioned(
                left: w * (_screenLeft / _templateWidth),
                top: h * (_screenTop / _templateHeight),
                width: w * (_screenWidth / _templateWidth),
                height: h * (_screenHeight / _templateHeight),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(w * (3.4 / 238)),
                  child: RepaintBoundary(
                    child: dfu
                        ? const _MockupRecoveryScreen()
                        : const _MockupInnerScreen(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class FlipperMockupHero extends StatelessWidget {
  const FlipperMockupHero({
    super.key,
    required this.active,
    required this.title,
    required this.infoEntries,
    required this.deviceInfo,
    required this.connectionLabel,
    required this.connectionIcon,
    this.dfu = false,
  });

  final bool active;
  final bool dfu;
  final String title;
  final List<MapEntry<String, String>> infoEntries;
  final Map<String, String> deviceInfo;
  final String connectionLabel;
  final IconData connectionIcon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final firmwareVersion =
        DeviceInfoReader.str(deviceInfo, const [
          'firmware_version',
          'firmware.version',
          'software_revision',
        ]) ??
        _entryValue(infoEntries, 'Firmware Version');
    final buildDate =
        DeviceInfoReader.str(deviceInfo, const [
          'firmware_build_date',
          'firmware.build.date',
          'build_date',
        ]) ??
        _entryValue(infoEntries, 'Build Date');
    final uid = DeviceInfoReader.str(deviceInfo, const [
      'hardware_uid',
      'hardware.uid',
      'uid',
    ]);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 100,
          child: FlipperMockupWidget(active: active, dfu: dfu),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onAccent,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _HeroPill(icon: connectionIcon, label: connectionLabel),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 2,
                children: [
                  if (firmwareVersion != null)
                    _HeroMetaText('fw $firmwareVersion'),
                  if (buildDate != null) _HeroMetaText('built $buildDate'),
                ],
              ),
              if (uid != null) ...[
                const SizedBox(height: 6),
                Text(
                  'UID $uid',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onAccent.withValues(alpha: .72),
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.onAccent.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.onAccent.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.onAccent),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: colors.onAccent,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetaText extends StatelessWidget {
  const _HeroMetaText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Text(
      text,
      style: TextStyle(
        color: colors.onAccent.withValues(alpha: .78),
        fontSize: 12,
      ),
    );
  }
}

String? _entryValue(List<MapEntry<String, String>> entries, String key) {
  for (final entry in entries) {
    if (entry.key == key &&
        entry.value.trim().isNotEmpty &&
        entry.value != '-') {
      return entry.value;
    }
  }
  return null;
}

class _MockupInnerScreen extends StatefulWidget {
  const _MockupInnerScreen();

  @override
  State<_MockupInnerScreen> createState() => _MockupInnerScreenState();
}

class _MockupInnerScreenState extends State<_MockupInnerScreen> {
  static const _animDir = 'assets/anim/L3_Fireplace_128x64';
  static const _statusBarAsset = 'assets/anim/Background_128x11.png';
  static const _statusBarHeight = 11;
  static const _screenBg = Color(0xFFFF8200);
  static const _screenFg = Color(0xFF000000);

  List<ui.Image> _frames = const [];
  ui.Image? _statusBar;
  Timer? _timer;
  int _cursor = 0;
  int _delayMs = 333;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fg = _screenFg.toARGB32();
    final bg = _screenBg.toARGB32();
    final anim = await _MockupAnimation.load(_animDir);
    final frames =
        anim == null ? <ui.Image>[] : await anim.loadFrames(fg: fg, bg: bg);
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

    if (!mounted) {
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
    return ColoredBox(
      color: _screenBg,
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
    );
  }
}

class _MockupAnimation {
  _MockupAnimation._({
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

  static Future<_MockupAnimation?> load(String assetDir) async {
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

    return _MockupAnimation._(
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

class _MockupRecoveryScreen extends StatelessWidget {
  const _MockupRecoveryScreen();

  static const _screenColor = Color(0xFFFF8200);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _screenColor,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: SvgPicture.asset(
          'assets/pic/device/screen/recovery.svg',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
