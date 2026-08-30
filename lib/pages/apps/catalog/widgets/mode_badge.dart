import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../../data/catalog_mode.dart';

/// Shows which mode the catalog runs in right now: plain catalog, source
/// builds or the nearest catalog API.
class CatalogModeBadge extends StatelessWidget {
  const CatalogModeBadge({
    super.key,
    required this.mode,
    required this.deviceApi,
    required this.catalogApi,
  });

  final CatalogMode mode;
  final String? deviceApi;
  final String? catalogApi;

  IconData _icon() => switch (mode) {
    CatalogMode.sourceBuild => Icons.construction_rounded,
    CatalogMode.nearestApi => Icons.warning_amber_rounded,
    _ => Icons.check_circle_rounded,
  };

  Color _color(QAppColors colors) => switch (mode) {
    CatalogMode.sourceBuild => colors.accent,
    CatalogMode.nearestApi => Colors.amber.shade600,
    _ => colors.success,
  };

  String _message() {
    final device = deviceApi;
    if (device == null) return l10n.catalogBadgeNoDevice;
    switch (mode) {
      case CatalogMode.sourceBuild:
        return l10n.catalogBadgeSourceBuild(device);
      case CatalogMode.nearestApi:
        return l10n.catalogBadgeNearestApi(device, catalogApi ?? '?');
      default:
        return l10n.catalogBadgeNormal(device);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = _color(colors);
    return Tooltip(
      message: _message(),
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Icon(_icon(), size: 15, color: color),
      ),
    );
  }
}
