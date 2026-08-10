import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../components/icon.dart';
import '../../../services/storage/fap_icons.dart';
import '../../../components/codec/fap/icon.dart';
import '../data/models/manifest.dart';
import 'icon_resolver.dart';

class AppIcon extends StatefulWidget {
  const AppIcon({
    super.key,
    required this.alias,
    required this.size,
    this.color,
    this.manifest,
  });

  final String alias;
  final double size;
  final Color? color;
  final AppManifest? manifest;

  @override
  State<AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<AppIcon> {
  Uint8List? _bits;

  @override
  void initState() {
    super.initState();
    fapIconRevision.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(AppIcon old) {
    super.didUpdateWidget(old);
    if (old.alias != widget.alias) _load();
  }

  @override
  void dispose() {
    fapIconRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final alias = widget.alias;
    if (alias.isEmpty) return;
    var bytes = await readFapIcon(alias);
    if (bytes == null && widget.manifest != null) {
      if (await IconResolver.instance.ensureFromManifest(
        alias,
        widget.manifest!,
      )) {
        bytes = await readFapIcon(alias);
      }
    }
    if (mounted && widget.alias == alias) setState(() => _bits = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Colors.black;
    final bits = _bits;
    if (bits != null) {
      return QIcon.xbm(
        bytes: bits,
        width: fapIconWidth,
        height: fapIconHeight,
        cacheKey: 'repo:${widget.alias}',
        color: color,
        size: widget.size,
      );
    }
    return Icon(Icons.extension_outlined, color: color, size: widget.size);
  }
}
