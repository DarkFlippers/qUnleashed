import 'dart:convert';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../../archive/storage.dart';
import '../../archive/models/category.dart';

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
  late final TextEditingController _editCtrl =
      TextEditingController(text: widget.content);
  final ScrollController _viewScroll = ScrollController();
  final ScrollController _editScroll = ScrollController();

  bool _editing = false;
  bool _savingLocal = false;
  bool _sending = false;
  double _sendProgress = 0;

  String _deviceName = 'Library';

  @override
  void initState() {
    super.initState();
    _initDeviceName();
  }

  Future<void> _initDeviceName() async {
    final live =
        ArchiveStorage.normalizeDeviceName(_client.connectedDevice?.name);
    final name = live ?? (await _storage.readLastDeviceName()) ?? 'Library';
    if (!mounted) return;
    setState(() => _deviceName = name);
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    _viewScroll.dispose();
    _editScroll.dispose();
    super.dispose();
  }

  String _safeName(String original) {
    final name = original.toLowerCase().endsWith('.ir')
        ? original
        : '$original.ir';
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  List<int> _currentBytes() => utf8.encode(_editCtrl.text);

  Future<void> _saveLocal() async {
    setState(() => _savingLocal = true);
    io.File? file;
    try {
      file = await _storage.saveBytes(
        _deviceName,
        ArchiveCategory.infrared,
        _safeName(widget.fileName),
        _currentBytes(),
      );
    } catch (_) {
      file = null;
    }
    if (!mounted) return;
    setState(() => _savingLocal = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(file == null
            ? 'Failed to save'
            : 'Saved to archive Infrared/${widget.fileName}'),
      ),
    );
  }

  Future<void> _sendToFlipper() async {
    if (!_client.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect a Flipper first')),
      );
      return;
    }
    setState(() {
      _sending = true;
      _sendProgress = 0;
    });
    final fileName = _safeName(widget.fileName);
    var ok = false;
    try {
      await _client.storageWriteChunked(
        '/ext/infrared/$fileName',
        _currentBytes(),
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _sendProgress = p);
        },
      );
      ok = true;
    } catch (e) {
      LogService.log('[IRBackend] send $fileName failed: $e');
    }
    if (ok) {
      try {
        await _storage.saveBytes(
          _deviceName,
          ArchiveCategory.infrared,
          fileName,
          _currentBytes(),
        );
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Sent to Flipper' : 'Failed to send')),
    );
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
        title: Text(widget.fileName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _editing ? 'View' : 'Edit',
            onPressed: () => setState(() => _editing = !_editing),
            icon: Icon(_editing ? Icons.visibility : Icons.edit_note),
          ),
        ],
      ),
      body: Column(
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
                    colorFilter: ColorFilter.mode(ir.color, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        widget.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: colors.textMuted, fontSize: 12),
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
                    onTap: _savingLocal || _sending ? null : _saveLocal,
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
                    onTap: _sending || _savingLocal ? null : _sendToFlipper,
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
                          contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 12),
                        ),
                      ),
                    )
                  : Scrollbar(
                      controller: _viewScroll,
                      child: SingleChildScrollView(
                        controller: _viewScroll,
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          _editCtrl.text,
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
