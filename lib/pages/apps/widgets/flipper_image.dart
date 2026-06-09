import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';

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
  late final Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch(widget.url);
  }

  static Future<Uint8List?> _fetch(String url) async {
    try {
      final client = io.HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.getUrl(Uri.parse(url));
        req.headers.set(io.HttpHeaders.acceptHeader, 'image/svg+xml,*/*');
        final res = await req.close();
        if (res.statusCode < 200 || res.statusCode >= 300) return null;
        final bytes = await res.expand((c) => c).toList();
        return Uint8List.fromList(bytes);
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback =
        widget.placeholder ?? SizedBox(width: widget.width, height: widget.height);
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
    this.placeholderAsset = 'assets/apps/app_placeholder.svg',
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
