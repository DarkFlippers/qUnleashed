import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../theme.dart';
import 'file_manager_controller.dart';

class TextEditorPage extends StatefulWidget {
  const TextEditorPage({
    super.key,
    required this.controller,
    required this.remotePath,
  });

  final FileManagerController controller;
  final String remotePath;

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<TextEditorPage> {
  final TextEditingController _text = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

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
    final bytes = await widget.controller.readBytes(widget.remotePath);
    if (!mounted) return;
    if (bytes == null) {
      setState(() {
        _loading = false;
        _error = 'Failed to read file';
      });
      return;
    }
    try {
      _text.text = utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      _text.text = String.fromCharCodes(bytes);
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await widget.controller.writeBytes(
      widget.remotePath,
      utf8.encode(_text.text),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Saved' : 'Save failed')),
    );
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final name = widget.remotePath.split('/').last;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Save',
            onPressed: _saving || _loading ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: TextStyle(color: colors.danger)),
                )
              : Container(
                  color: colors.terminalBackground,
                  child: Scrollbar(
                    child: TextField(
                      controller: _text,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      cursorColor: colors.accent,
                      style: TextStyle(
                        color: colors.terminalText,
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.4,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 12),
                      ),
                    ),
                  ),
                ),
    );
  }
}
