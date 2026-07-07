import 'dart:collection';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../services/http/app_http.dart';
import '../../../theme/theme.dart';

/// LRU cache of fetched SVG bytes keyed by URL, with in-flight request
/// deduplication so a grid mounting many tiles with the same icon issues a
/// single download.
class _SvgBytesCache {
  static const int _maxEntries = 128;
  static final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  static Future<Uint8List?> fetch(String url) {
    final cached = _cache.remove(url);
    if (cached != null) {
      _cache[url] = cached;
      return Future.value(cached);
    }
    return _inFlight.putIfAbsent(url, () => _download(url));
  }

  static Future<Uint8List?> _download(String url) async {
    try {
      final bytes = await AppHttp.getBytes(
        Uri.parse(url),
        headers: {io.HttpHeaders.acceptHeader: 'image/svg+xml,*/*'},
      );
      _cache[url] = bytes;
      while (_cache.length > _maxEntries) {
        _cache.remove(_cache.keys.first);
      }
      return bytes;
    } catch (_) {
      return null;
    } finally {
      _inFlight.remove(url);
    }
  }
}

/// Fetches an SVG from a URL with proper error handling.
/// Unlike [SvgPicture.network], exceptions (HandshakeException, ClientException)
/// are caught and a [placeholder] is shown instead of propagating as unhandled errors.
class SafeNetworkSvg extends StatefulWidget {
  const SafeNetworkSvg({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.colorFilter,
    this.placeholder,
    this.semanticsLabel,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final ColorFilter? colorFilter;
  final Widget? placeholder;
  final String? semanticsLabel;

  @override
  State<SafeNetworkSvg> createState() => _SafeNetworkSvgState();
}

class _SafeNetworkSvgState extends State<SafeNetworkSvg> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = _SvgBytesCache.fetch(widget.url);
  }

  @override
  void didUpdateWidget(SafeNetworkSvg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _future = _SvgBytesCache.fetch(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback =
        widget.placeholder ??
        SizedBox(width: widget.width, height: widget.height);
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return fallback;
        return SvgPicture.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          colorFilter: widget.colorFilter,
          semanticsLabel: widget.semanticsLabel,
        );
      },
    );
  }
}

class FlipperRemoteImage extends StatelessWidget {
  const FlipperRemoteImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.pixelated = true,
    this.placeholderAsset = 'assets/pic/app/placeholder.svg',
    this.placeholderColor,
  });

  final String url;
  final BoxFit fit;
  final bool pixelated;
  final String placeholderAsset;
  final Color? placeholderColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tint = placeholderColor ?? colors.textMuted;

    if (url.isEmpty) {
      return _placeholder(tint);
    }

    final isSvg = url.toLowerCase().endsWith('.svg');
    if (isSvg) {
      return SafeNetworkSvg(
        url: url,
        fit: fit,
        placeholder: _placeholder(tint),
      );
    }

    return Image.network(
      url,
      fit: fit,
      filterQuality: pixelated ? FilterQuality.none : FilterQuality.medium,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _placeholder(tint);
      },
      errorBuilder: (_, _, _) => _placeholder(tint),
    );
  }

  Widget _placeholder(Color tint) {
    return Center(
      child: SvgPicture.asset(
        placeholderAsset,
        colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
        width: 28,
        height: 28,
      ),
    );
  }
}
