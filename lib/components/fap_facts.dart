import 'package:flutter/material.dart';

import '../services/localization/l10n.dart';
import 'format.dart';
import '../theme/theme.dart';
import 'codec/fap/details.dart';
import 'codec/fap/info.dart';

/// Everything a `.fap` tells about itself: the embedded manifest, what the
/// loader would allocate for it and the assets it unpacks onto the SD card.
class FapFactsPanel extends StatelessWidget {
  const FapFactsPanel({
    super.key,
    required this.info,
    this.checked = true,
    this.showVerdict = true,
    this.pendingNote,
    this.author,
    this.deviceApi,
    this.deviceTarget,
  });

  final FapInfo? info;
  final bool checked;
  final bool showVerdict;
  final String? pendingNote;
  final String? author;
  final String? deviceApi;
  final String? deviceTarget;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final strings = context.l10n;

    if (!checked) {
      return _Note(
        icon: Icons.sync,
        text: pendingNote ?? strings.fapPendingNote,
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
        if (showVerdict && compat.isBlocking) ...[
          _Verdict(compat: compat, colors: colors),
          const SizedBox(height: 10),
        ],
        _Facts(
          colors: colors,
          rows: [
            if (author != null && author!.isNotEmpty)
              (strings.factAuthor, author!),
            if (manifest != null) ...[
              (strings.factVersion, manifest.version),
              ('API', manifest.api),
              (strings.factTarget, manifest.target),
              if (!manifest.isPlugin)
                (strings.factStack, _fmtSize(manifest.stackSize))
              else
                (strings.factType, strings.factTypePlugin),
            ],
            (strings.factRamToLoad, _fmtSize(info.ramTotal)),
            (strings.factLargestBlock, _fmtSize(info.ramLargestBlock)),
            (strings.factCode, _fmtSize(info.codeSize)),
            (strings.factConst, _fmtSize(info.readOnlyDataSize)),
            (strings.factData, _fmtSize(info.dataSize)),
            ('BSS', _fmtSize(info.bssSize)),
            (strings.factApiImports, '${info.imports.length}'),
            if (assets != null)
              (strings.factAssets, strings.factAssetsFiles(assets.files.length)),
            if (assets != null && assets.plugins.isNotEmpty)
              (
                strings.factPlugins,
                strings.factPluginsEmbedded(assets.plugins.length),
              ),
            (
              strings.factRelocations,
              info.hasFastRelocations
                  ? strings.factRelocationsFast
                  : strings.factRelocationsStandard,
            ),
            (strings.factFile, _fmtSize(info.fileSize)),
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
          child: Text(text, style: TextStyle(color: color, fontSize: 12)),
        ),
      ],
    );
  }
}

String _fmtSize(int bytes) => formatBytesScaled(bytes, maxUnit: 2);
