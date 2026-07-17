import 'dart:async';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../archive/data/category.dart';
import '../../archive/overview/storage.dart';
import 'widgets/ir_file_viewer.dart';

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
  String _deviceName = 'Library';

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
    final name =
        original.toLowerCase().endsWith('.ir') ? original : '$original.ir';
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
          final disconnected = Completer<void>();
          late final StreamSubscription<FlipperConnectionState> sub;
          sub = _client.connectionStream.listen((state) {
            if (!state.connected && !disconnected.isCompleted) {
              disconnected.completeError(StateError('Disconnected'));
            }
          });
          await Future.any<void>([
            _client.storageWriteChunked(
              '/ext/infrared/$fileName',
              bytes,
              onProgress: onProgress,
            ),
            disconnected.future,
          ]).whenComplete(sub.cancel);
          return true;
        } catch (e) {
          LogService.log('[IRBackend] send $fileName failed: $e');
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
        } catch (_) {}
      },
    );
  }
}
