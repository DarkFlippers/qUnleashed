import 'package:flutter/material.dart';

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
    if (device == null) {
      return 'Catalog: showing every app, connect a Flipper to filter it by '
          'the firmware API';
    }
    switch (mode) {
      case CatalogMode.sourceBuild:
        return 'Source builds: the catalog has no builds for firmware API '
            '$device, so apps are compiled from source for it';
      case CatalogMode.nearestApi:
        return 'Nearest API: the catalog has no builds for firmware API '
            '$device, installing builds made for API ${catalogApi ?? '?'}';
      default:
        return 'Catalog: firmware API $device is served by the catalog';
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
