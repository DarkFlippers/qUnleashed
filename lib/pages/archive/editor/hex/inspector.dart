import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../components/notification.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../style.dart';
import 'document.dart';
import 'style.dart';

/// Reads the bytes at the cursor as every common number type, and sums up the
/// selection.
class HexInspector extends StatefulWidget {
  const HexInspector({super.key, required this.document, this.onClose});

  final HexDocument document;
  final VoidCallback? onClose;

  @override
  State<HexInspector> createState() => _HexInspectorState();
}

class _HexInspectorState extends State<HexInspector> {
  Endian _endian = Endian.little;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: widget.document,
      builder: (context, _) {
        final document = widget.document;
        final offset = min(document.cursor, max(0, document.length - 1));
        final available = max(0, document.length - offset);
        final window = Uint8List(8);
        for (var i = 0; i < 8 && offset + i < document.length; i++) {
          window[i] = document.byteAt(offset + i);
        }
        final data = ByteData.sublistView(window);
        final selection = document.selection;
        return Container(
          color: colors.card,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            children: [
              _header(colors),
              const SizedBox(height: 6),
              if (document.length == 0)
                _row(colors, 'file', l10n.hexEmptyFile)
              else ...[
                _row(
                  colors,
                  l10n.hexOffset,
                  '$offset · 0x${hexOffsetText(offset, 2)}',
                ),
                _row(colors, l10n.hexBits, _bits(window[0])),
                _row(colors, l10n.hexChar, _char(window[0])),
                const SizedBox(height: 8),
                _row(colors, 'int8', '${data.getInt8(0)}'),
                _row(colors, 'uint8', '${data.getUint8(0)}'),
                _row(
                  colors,
                  'int16',
                  available >= 2 ? '${data.getInt16(0, _endian)}' : '—',
                ),
                _row(
                  colors,
                  'uint16',
                  available >= 2 ? '${data.getUint16(0, _endian)}' : '—',
                ),
                _row(
                  colors,
                  'int32',
                  available >= 4 ? '${data.getInt32(0, _endian)}' : '—',
                ),
                _row(
                  colors,
                  'uint32',
                  available >= 4 ? '${data.getUint32(0, _endian)}' : '—',
                ),
                _row(
                  colors,
                  'int64',
                  available >= 8 ? '${data.getInt64(0, _endian)}' : '—',
                ),
                _row(
                  colors,
                  'uint64',
                  available >= 8 ? '${data.getUint64(0, _endian)}' : '—',
                ),
                _row(
                  colors,
                  'float32',
                  available >= 4 ? _float(data.getFloat32(0, _endian)) : '—',
                ),
                _row(
                  colors,
                  'float64',
                  available >= 8 ? _float(data.getFloat64(0, _endian)) : '—',
                ),
              ],
              const SizedBox(height: 14),
              Text(
                l10n.hexSelection.toUpperCase(),
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              if (selection == null)
                _row(colors, '', l10n.hexNoSelection)
              else
                ..._selectionRows(colors, selection),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _selectionRows(QAppColors colors, HexRange selection) {
    final bytes = widget.document.range(selection.start, selection.end);
    return [
      _row(
        colors,
        l10n.hexRange,
        '0x${hexOffsetText(selection.start, 2)}–0x${hexOffsetText(selection.end - 1, 2)}',
      ),
      _row(
        colors,
        l10n.hexLength,
        '${selection.length} · 0x${hexOffsetText(selection.length, 2)}',
      ),
      _row(
        colors,
        'crc32',
        hexCrc32(bytes).toRadixString(16).toUpperCase().padLeft(8, '0'),
      ),
      if (bytes.length <= 1 << 20) ...[
        _row(colors, 'md5', md5.convert(bytes).toString()),
        _row(colors, 'sha1', sha1.convert(bytes).toString()),
      ],
      _row(colors, l10n.hexTextPreview, _preview(bytes)),
    ];
  }

  Widget _header(QAppColors colors) {
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.hexInspector,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _endianButton(colors, Endian.little, 'LE'),
        const SizedBox(width: 4),
        _endianButton(colors, Endian.big, 'BE'),
        if (widget.onClose != null)
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: colors.textSecondary,
            tooltip: l10n.commonClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          ),
      ],
    );
  }

  Widget _endianButton(QAppColors colors, Endian endian, String label) {
    final selected = _endian == endian;
    return InkWell(
      onTap: () => setState(() => _endian = endian),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 34,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: selected ? colors.accent : colors.background,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.onAccent : colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _row(QAppColors colors, String label, String value) {
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (!mounted) return;
        if (context.mounted) {
          context.showNotification(
            l10n.hexCopied,
            type: QNotificationType.good,
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 62,
              child: Text(
                label,
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontFamily: kEditorFontFamily,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _bits(int byte) {
    final bits = byte.toRadixString(2).padLeft(8, '0');
    return '${bits.substring(0, 4)} ${bits.substring(4)}';
  }

  static String _char(int byte) =>
      hexIsPrintable(byte) ? "'${String.fromCharCode(byte)}'" : '—';

  static String _float(double value) {
    if (value.isNaN) return 'NaN';
    if (value.isInfinite) return value.isNegative ? '-inf' : 'inf';
    return value.toStringAsPrecision(9);
  }

  static String _preview(Uint8List bytes) {
    final head = bytes.length > 96 ? bytes.sublist(0, 96) : bytes;
    final text = utf8.decode(head, allowMalformed: true).replaceAll('\n', '⏎');
    return bytes.length > head.length ? '$text…' : text;
  }
}

List<int>? _crcCache;

int hexCrc32(List<int> bytes) {
  var table = _crcCache;
  if (table == null) {
    table = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var value = i;
      for (var bit = 0; bit < 8; bit++) {
        value = (value & 1) == 1 ? 0xedb88320 ^ (value >> 1) : value >> 1;
      }
      table[i] = value;
    }
    _crcCache = table;
  }
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = table[(crc ^ byte) & 0xff] ^ (crc >> 8);
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
