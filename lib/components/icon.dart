import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/theme.dart';

class _RasterIconCache {
  _RasterIconCache._();
  static final _RasterIconCache instance = _RasterIconCache._();

  static const int _maxEntries = 256;

  final Map<String, ui.Image> _ready = <String, ui.Image>{};
  final Map<String, Future<ui.Image>> _pending = <String, Future<ui.Image>>{};

  static String keyFor(String asset, Color color, int pixelSize) =>
      '$asset|${color.toARGB32()}|$pixelSize';

  static String xbmKeyFor(
    String cacheKey,
    Uint8List bytes,
    int width,
    int height,
    Color color,
    int pixelSize,
  ) =>
      'xbm:$cacheKey|${Object.hashAll(bytes)}|${width}x$height|'
      '${color.toARGB32()}|$pixelSize';

  ui.Image? ready(String key) => _ready[key];

  Future<ui.Image> resolve({
    required String key,
    required String label,
    required int pixelSize,
    required Future<ui.Image> Function() rasterize,
  }) {
    final existing = _ready[key];
    if (existing != null) return Future<ui.Image>.value(existing);

    var wasAdded = false;
    final pending = _pending.putIfAbsent(key, () async {
      wasAdded = true;
      try {
        final image = await rasterize();
        _store(key, image);
        return image;
      } catch (error) {
        _debugLog('failed', label: label, pixelSize: pixelSize, error: error);
        rethrow;
      } finally {
        _pending.remove(key);
        _debugLog('finished', label: label, pixelSize: pixelSize);
      }
    });

    _debugLog(
      wasAdded ? 'queued' : 'joined',
      label: label,
      pixelSize: pixelSize,
    );
    return pending;
  }

  void _store(String key, ui.Image image) {
    if (_ready.length >= _maxEntries) {
      final oldestKey = _ready.keys.first;
      _ready.remove(oldestKey)?.dispose();
      _debugLog('evicted');
    }
    _ready[key] = image;
  }

  void _debugLog(
    String action, {
    String? label,
    int? pixelSize,
    Object? error,
  }) {
    if (!kDebugMode) return;

    final details = <String>[
      'pending=${_pending.length}',
      'cached=${_ready.length}/$_maxEntries',
      if (label != null) 'asset=$label',
      if (pixelSize != null) 'pixelSize=$pixelSize',
      if (error != null) 'error=$error',
    ];
    debugPrint('[QIconCache] $action; ${details.join('; ')}');
  }

  static Future<ui.Image> _rasterize({
    required String asset,
    required Color color,
    required int pixelSize,
  }) async {
    final info = await vg.loadPicture(SvgAssetLoader(asset), null);
    try {
      final src = info.size;
      final scale = (src.width <= 0 || src.height <= 0)
          ? 1.0
          : pixelSize / (src.width > src.height ? src.width : src.height);
      final dx = (pixelSize - src.width * scale) / 2;
      final dy = (pixelSize - src.height * scale) / 2;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()
        ..colorFilter = ui.ColorFilter.mode(color, ui.BlendMode.srcIn);
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, pixelSize.toDouble(), pixelSize.toDouble()),
        paint,
      );
      canvas.translate(dx, dy);
      canvas.scale(scale);
      canvas.drawPicture(info.picture);
      canvas.restore();

      final picture = recorder.endRecording();
      try {
        return await picture.toImage(pixelSize, pixelSize);
      } finally {
        picture.dispose();
      }
    } finally {
      info.picture.dispose();
    }
  }

  static Future<ui.Image> rasterizeXbm({
    required Uint8List bytes,
    required int width,
    required int height,
    required Color color,
    required int pixelSize,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final scale = pixelSize / (width > height ? width : height);
    final dx = (pixelSize - width * scale) / 2;
    final dy = (pixelSize - height * scale) / 2;
    final rowBytes = (width + 7) >> 3;
    final paint = Paint()..color = color;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final byteIndex = y * rowBytes + (x >> 3);
        if (byteIndex >= bytes.length) continue;
        if ((bytes[byteIndex] & (1 << (x & 7))) == 0) continue;
        canvas.drawRect(
          Rect.fromLTWH(dx + x * scale, dy + y * scale, scale, scale),
          paint,
        );
      }
    }

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(pixelSize, pixelSize);
    } finally {
      picture.dispose();
    }
  }
}

class QIcon extends StatefulWidget {
  const QIcon({
    super.key,
    required String this.asset,
    required this.color,
    this.size,
  }) : xbm = null,
       xbmWidth = null,
       xbmHeight = null,
       cacheKey = null;

  const QIcon.xbm({
    super.key,
    required Uint8List bytes,
    required int width,
    required int height,
    required this.cacheKey,
    required this.color,
    required double this.size,
  }) : asset = null,
       xbm = bytes,
       xbmWidth = width,
       xbmHeight = height;

  final String? asset;
  final Uint8List? xbm;
  final int? xbmWidth;
  final int? xbmHeight;
  final String? cacheKey;
  final Color color;
  final double? size;

  @override
  State<QIcon> createState() => _QIconState();
}

class _QIconState extends State<QIcon> {
  String? _key;
  ui.Image? _image;

  void _adopt(ui.Image? cacheImage) {
    _image?.dispose();
    _image = cacheImage?.clone();
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final asset = widget.asset;
    final xbm = widget.xbm;
    if (size == null) {
      return SvgPicture.asset(
        asset!,
        colorFilter: ColorFilter.mode(widget.color, BlendMode.srcIn),
      );
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final pixelSize = (size * dpr).ceil();
    final key = asset != null
        ? _RasterIconCache.keyFor(asset, widget.color, pixelSize)
        : _RasterIconCache.xbmKeyFor(
            widget.cacheKey!,
            xbm!,
            widget.xbmWidth!,
            widget.xbmHeight!,
            widget.color,
            pixelSize,
          );
    final label = asset ?? 'fap:${widget.cacheKey}';

    if (key != _key) {
      _key = key;
      final cached = _RasterIconCache.instance.ready(key);
      if (cached != null) {
        _adopt(cached);
      } else {
        _adopt(null);
        _RasterIconCache.instance
            .resolve(
              key: key,
              label: label,
              pixelSize: pixelSize,
              rasterize: asset != null
                  ? () => _RasterIconCache._rasterize(
                      asset: asset,
                      color: widget.color,
                      pixelSize: pixelSize,
                    )
                  : () => _RasterIconCache.rasterizeXbm(
                      bytes: xbm!,
                      width: widget.xbmWidth!,
                      height: widget.xbmHeight!,
                      color: widget.color,
                      pixelSize: pixelSize,
                    ),
            )
            .then((image) {
              if (mounted && _key == key) setState(() => _adopt(image));
            });
      }
    }

    final image = _image;
    if (image == null) {
      return SizedBox(width: size, height: size);
    }
    return RawImage(
      image: image.clone(),
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

class QIconBadge extends StatelessWidget {
  const QIconBadge({
    super.key,
    required this.asset,
    required this.color,
    this.size = 36,
    this.iconSize = 24,
    this.backgroundOpacity = 0.18,
    this.borderRadius = 8,
  }) : xbm = null,
       xbmWidth = null,
       xbmHeight = null,
       cacheKey = null;

  const QIconBadge.xbm({
    super.key,
    required Uint8List bytes,
    required int width,
    required int height,
    required this.cacheKey,
    required this.color,
    this.size = 36,
    this.iconSize = 24,
    this.backgroundOpacity = 0.18,
    this.borderRadius = 8,
  }) : asset = null,
       xbm = bytes,
       xbmWidth = width,
       xbmHeight = height;

  final String? asset;
  final Uint8List? xbm;
  final int? xbmWidth;
  final int? xbmHeight;
  final String? cacheKey;
  final Color color;
  final double size;
  final double iconSize;
  final double backgroundOpacity;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final isLight = !context.appColors.isDark;
    final isNearWhite = color.computeLuminance() > 0.9;
    final backgroundColor = isLight
        ? (isNearWhite ? const Color(0xFF9E9E9E) : color)
        : color.withValues(alpha: backgroundOpacity);
    final iconColor = isLight ? const Color(0xFFFFFFFF) : color;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: asset != null
          ? QIcon(asset: asset!, color: iconColor, size: iconSize)
          : QIcon.xbm(
              bytes: xbm!,
              width: xbmWidth!,
              height: xbmHeight!,
              cacheKey: cacheKey!,
              color: iconColor,
              size: iconSize,
            ),
    );
  }
}
