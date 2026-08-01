import 'package:flutter/material.dart';

import '../../../../components/codec/fap.dart';
import '../../../../theme/theme.dart';
import '../../data/models/fap_details.dart';

/// Everything a `.fap` tells about itself: the embedded manifest, what the
/// loader would allocate for it and the assets it unpacks onto the SD card.
class FapFactsPanel extends StatelessWidget {
  const FapFactsPanel({
    super.key,
    required this.info,
    this.checked = true,
    this.showVerdict = true,
    this.author,
    this.deviceApi,
    this.deviceTarget,
  });

  final FapInfo? info;
  final bool checked;
  final bool showVerdict;
  final String? author;
  final String? deviceApi;
  final String? deviceTarget;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (!checked) {
      return _Note(
        icon: Icons.sync,
        text: 'Sync the manager to read this app from the device',
        color: colors.textMuted,
        colors: colors,
      );
    }

    final info = this.info;
    final compat = evaluateFap(
      info,
      deviceApi: deviceApi,
      deviceTarget: deviceTarget,
    );

    if (info == null) {
      return _Note(
        icon: Icons.error_outline,
        text: compat.message,
        color: colors.danger,
        colors: colors,
      );
    }

    final manifest = info.manifest;
    final assets = info.assets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showVerdict) ...[
          _Verdict(compat: compat, colors: colors),
          const SizedBox(height: 10),
        ],
        _Facts(
          colors: colors,
          rows: [
            if (author != null && author!.isNotEmpty) ('Author', author!),
            if (manifest != null) ...[
              ('Version', manifest.version),
              ('API', manifest.api),
              ('Target', manifest.target),
              if (!manifest.isPlugin)
                ('Stack', _fmtSize(manifest.stackSize))
              else
                ('Type', 'Plugin'),
            ],
            ('RAM to load', _fmtSize(info.ramTotal)),
            ('Largest block', _fmtSize(info.ramLargestBlock)),
            ('Code', _fmtSize(info.codeSize)),
            ('Const', _fmtSize(info.readOnlyDataSize)),
            ('Data', _fmtSize(info.dataSize)),
            ('BSS', _fmtSize(info.bssSize)),
            ('API imports', '${info.imports.length}'),
            if (assets != null) ('Assets', '${assets.files.length} files'),
            if (assets != null && assets.plugins.isNotEmpty)
              ('Plugins', '${assets.plugins.length} embedded'),
            (
              'Relocations',
              info.hasFastRelocations ? 'fast (fastfap)' : 'standard'
            ),
            ('File', _fmtSize(info.fileSize)),
          ],
        ),
      ],
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.compat, required this.colors});

  final FapCompat compat;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    final blocking = compat.isBlocking;
    final color = blocking
        ? colors.danger
        : (compat.verdict == FapVerdict.ok ? colors.success : colors.textMuted);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            blocking ? Icons.block : Icons.check_circle_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              compat.message,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.rows, required this.colors});

  final List<(String, String)> rows;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 86,
                  child: Text(
                    row.$1,
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.text,
    required this.color,
    required this.colors,
  });

  final IconData icon;
  final String text;
  final Color color;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

String _fmtSize(int bytes) {
  const units = ['B', 'KB', 'MB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(value >= 10 || index == 0 ? 0 : 1)} '
      '${units[index]}';
}
