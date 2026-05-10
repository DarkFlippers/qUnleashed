import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../../archive/models/category.dart';
import 'controller.dart';
import 'models.dart';

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

  bool _savingLocal = false;
  bool _sending = false;
  double _sendProgress = 0;
  bool _editing = false;
  late final TextEditingController _editCtrl = TextEditingController();
  final ScrollController _viewScroll = ScrollController();
  final ScrollController _editScroll = ScrollController();

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
      _editCtrl.text = text;
      _loading = false;
    });
  }

  Future<void> _saveLocal() async {
    final bytes = _currentBytes();
    if (bytes == null) return;
    setState(() => _savingLocal = true);
    final file = await widget.controller.saveToArchive(widget.entry, bytes);
    if (!mounted) return;
    setState(() => _savingLocal = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          file == null
              ? 'Failed to save'
              : 'Saved to archive Infrared/${widget.entry.name}',
        ),
      ),
    );
  }

  Future<void> _sendToFlipper() async {
    if (!widget.controller.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect a Flipper first')),
      );
      return;
    }
    final bytes = _currentBytes();
    if (bytes == null) return;
    setState(() {
      _sending = true;
      _sendProgress = 0;
    });
    final ok = await widget.controller.sendToFlipper(
      widget.entry,
      bytes,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _sendProgress = p);
      },
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      await widget.controller.saveToArchive(widget.entry, bytes);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Sent to Flipper' : 'Failed to send to Flipper'),
      ),
    );
  }

  List<int>? _currentBytes() {
    if (_editing) {
      return utf8.encode(_editCtrl.text);
    }
    return _bytes;
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    _viewScroll.dispose();
    _editScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final ir = ArchiveCategory.infrared;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        title: Text(widget.entry.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _editing ? 'View' : 'Edit',
            onPressed: _loading || _error != null
                ? null
                : () => setState(() {
                      _editing = !_editing;
                      if (_editing) _editCtrl.text = _text;
                    }),
            icon: Icon(_editing ? Icons.visibility : Icons.edit_note),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: TextStyle(color: colors.danger),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: ir.color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SvgPicture.asset(
                              ir.asset,
                              width: 22,
                              height: 22,
                              colorFilter:
                                  ColorFilter.mode(ir.color, BlendMode.srcIn),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.entry.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  widget.entry.path,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.download,
                              label: _savingLocal ? 'SavingвЂ¦' : 'Save to phone',
                              onTap:
                                  _savingLocal || _sending ? null : _saveLocal,
                              filled: false,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.send,
                              label: _sending
                                  ? 'Sending ${(_sendProgress * 100).toStringAsFixed(0)}%'
                                  : 'Send to Flipper',
                              onTap:
                                  _sending || _savingLocal ? null : _sendToFlipper,
                              filled: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        decoration: BoxDecoration(
                          color: colors.terminalBackground,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colors.divider),
                        ),
                        child: _editing
                            ? Scrollbar(
                                controller: _editScroll,
                                child: TextField(
                                  controller: _editCtrl,
                                  scrollController: _editScroll,
                                  maxLines: null,
                                  expands: true,
                                  textAlignVertical: TextAlignVertical.top,
                                  cursorColor: colors.accent,
                                  style: TextStyle(
                                    color: colors.terminalText,
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isCollapsed: true,
                                    contentPadding: EdgeInsets.fromLTRB(
                                        12, 12, 12, 12),
                                  ),
                                ),
                              )
                            : Scrollbar(
                                controller: _viewScroll,
                                child: SingleChildScrollView(
                                  controller: _viewScroll,
                                  padding: const EdgeInsets.all(12),
                                  child: SelectableText(
                                    _text,
                                    style: TextStyle(
                                      color: colors.terminalText,
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.filled,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final fg = filled ? colors.onAccent : colors.textPrimary;
    final bg = filled ? colors.accent : colors.card;
    final disabled = onTap == null;
    return Material(
      color: bg.withValues(alpha: disabled ? 0.5 : 1.0),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
