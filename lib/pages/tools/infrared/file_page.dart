import 'dart:convert';

import 'package:flutter/material.dart';

import 'controller.dart';
import 'models.dart';
import 'widgets/ir_file_viewer.dart';

class IrLibFilePage extends StatefulWidget {
  const IrLibFilePage({
    super.key,
    required this.controller,
    required this.entry,
  });

  final IrLibController controller;
  final IrEntry entry;

  @override
  State<IrLibFilePage> createState() => _IrLibFilePageState();
}

class _IrLibFilePageState extends State<IrLibFilePage> {
  bool _loading = true;
  String? _error;
  List<int>? _bytes;
  String _text = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final bytes = await widget.controller.readFileBytes(widget.entry);
    if (!mounted) return;
    if (bytes == null) {
      setState(() {
        _loading = false;
        _error = 'Failed to download file';
      });
      return;
    }
    String text;
    try {
      text = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      text = String.fromCharCodes(bytes);
    }
    setState(() {
      _bytes = bytes;
      _text = text;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return IrFileViewer(
      fileName: widget.entry.name,
      subtitle: widget.entry.path,
      loading: _loading,
      error: _error,
      text: _text,
      bytes: _bytes,
      isConnected: widget.controller.isConnected,
      onSend: ({required bytes, required onProgress}) {
        return widget.controller.sendToFlipper(
          widget.entry,
          bytes,
          onProgress: onProgress,
        );
      },
      onAfterSend: (bytes) async {
        await widget.controller.saveToArchive(widget.entry, bytes);
      },
    );
  }
}
