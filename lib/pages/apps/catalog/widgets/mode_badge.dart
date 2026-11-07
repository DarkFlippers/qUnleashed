import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../../data/catalog_mode.dart';

/// Flags a catalog that does not run as usual: source builds, the nearest
/// catalog API, or no device to check against. A plain icon the size of the
/// header actions; nothing at all while the catalog runs as usual.
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

  bool get _usual =>
      deviceApi != null &&
      mode != CatalogMode.sourceBuild &&
      mode != CatalogMode.nearestApi;

  IconData _icon() => switch (mode) {
    _ when deviceApi == null => Icons.link_off_rounded,
    CatalogMode.sourceBuild => Icons.construction_rounded,
    _ => Icons.warning_amber_rounded,
  };

  Color _color(QAppColors colors) => switch (mode) {
    _ when deviceApi == null => colors.textSecondary,
    CatalogMode.sourceBuild => colors.accent,
    _ => Colors.amber.shade600,
  };

  String _message() {
    final device = deviceApi;
    if (device == null) return l10n.catalogBadgeNoDevice;
    switch (mode) {
      case CatalogMode.sourceBuild:
        return l10n.catalogBadgeSourceBuild(device);
      default:
        return l10n.catalogBadgeNearestApi(device, catalogApi ?? '?');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_usual) return const SizedBox.shrink();
    return Tooltip(
      message: _message(),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(_icon(), size: 20, color: _color(context.appColors)),
      ),
    );
  }
}
