import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

class _RasterIconCache {
  _RasterIconCache._();
  static final _RasterIconCache instance = _RasterIconCache._();

  static const int _maxEntries = 256;

  final Map<String, ui.Image> _ready = <String, ui.Image>{};
  final Map<String, Future<ui.Image>> _pending = <String, Future<ui.Image>>{};

  static String keyFor(String asset, Color color, int pixelSize) =>
      '$asset|${color.toARGB32()}|$pixelSize';

  ui.Image? ready(String key) => _ready[key];

  Future<ui.Image> resolve({
    required String key,
    required String asset,
    required Color color,
    required int pixelSize,
  }) {
    final existing = _ready[key];
    if (existing != null) return Future<ui.Image>.value(existing);

    return _pending.putIfAbsent(key, () async {
      try {
        final image = await _rasterize(
          asset: asset,
          color: color,
          pixelSize: pixelSize,
        );
        _store(key, image);
        return image;
      } finally {
        _pending.remove(key);
      }
    });
  }

  void _store(String key, ui.Image image) {
    if (_ready.length >= _maxEntries) {
      final oldestKey = _ready.keys.first;
      _ready.remove(oldestKey)?.dispose();
    }
    _ready[key] = image;
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
}

class QIcon extends StatefulWidget {
  const QIcon({super.key, required this.asset, required this.color, this.size});

  final String asset;
  final Color color;
  final double? size;

  @override
  State<QIcon> createState() => _QIconState();
}

class _QIconState extends State<QIcon> {
  String? _key;
  ui.Image? _image;

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    if (size == null) {
      return SvgPicture.asset(
        widget.asset,
        colorFilter: ColorFilter.mode(widget.color, BlendMode.srcIn),
      );
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final pixelSize = (size * dpr).ceil();
    final key = _RasterIconCache.keyFor(widget.asset, widget.color, pixelSize);

    if (key != _key) {
      _key = key;
      final cached = _RasterIconCache.instance.ready(key);
      if (cached != null) {
        _image = cached;
      } else {
        _image = null;
        _RasterIconCache.instance
            .resolve(
              key: key,
              asset: widget.asset,
              color: widget.color,
              pixelSize: pixelSize,
            )
            .then((image) {
              if (mounted && _key == key) setState(() => _image = image);
            });
      }
    }

    final image = _image;
    if (image == null) {
      return SizedBox(width: size, height: size);
    }
    return RawImage(
      image: image,
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
  });

  final String asset;
  final Color color;
  final double size;
  final double iconSize;
  final double backgroundOpacity;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: backgroundOpacity),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: QIcon(asset: asset, color: color, size: iconSize),
    );
  }
}
