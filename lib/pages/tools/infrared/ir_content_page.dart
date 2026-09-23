import '../../../services/localization/l10n.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../components/archive/category.dart';
import '../../../services/archive/storage.dart';
import 'send.dart';
import 'widgets/ir_file_viewer.dart';
import '../../../services/logging.dart';

class IrContentPage extends StatefulWidget {
  const IrContentPage({
    super.key,
    required this.fileName,
    required this.subtitle,
    required this.content,
  });

  final String fileName;
  final String subtitle;
  final String content;

  @override
  State<IrContentPage> createState() => _IrContentPageState();
}

class _IrContentPageState extends State<IrContentPage> {
  final ArchiveStorage _storage = ArchiveStorage();
  final FlipperClient _client = FlipperOneClient().get();
  late String _deviceName = l10n.irLibraryTab;

  @override
  void initState() {
    super.initState();
    _initDeviceName();
  }

  Future<void> _initDeviceName() async {
    final name = _client.getName() ?? '';
    if (!mounted) return;
    setState(() => _deviceName = name);
  }

  String _safeName(String original) {
    final name = original.toLowerCase().endsWith('.ir')
        ? original
        : '$original.ir';
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  @override
  Widget build(BuildContext context) {
    final bytes = utf8.encode(widget.content);
    return IrFileViewer(
      fileName: widget.fileName,
      subtitle: widget.subtitle,
      loading: false,
      error: null,
      text: widget.content,
      bytes: bytes,
      isConnected: _client.isConnected,
      onSend: ({required bytes, required onProgress}) async {
        final fileName = _safeName(widget.fileName);
        try {
          await sendIrFile(_client, fileName, bytes, onProgress: onProgress);
          return true;
        } catch (e) {
          // As the controller's sendToFlipper: the disconnect arrives as the
          // sentence sendIrFile raises, and flipperlib records a link drop
          // only at info.
          LogService.warn('[IRBackend] send $fileName failed: $e');
          return false;
        }
      },
      onAfterSend: (bytes) async {
        try {
          await _storage.saveBytes(
            _deviceName,
            ArchiveCategory.infrared,
            _safeName(widget.fileName),
            bytes,
          );
        } catch (e) {
          // As the controller's saveToArchive, which this was swallowing.
          LogService.warn(
            '[IRBackend] save ${_safeName(widget.fileName)} failed: $e',
          );
        }
      },
    );
  }
}
