import 'package:flutter/material.dart';

import '../../../../components/icon.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../../data/catalog_api.dart' show CatalogFamily;
import '../../data/models/category.dart';
import '../../../../components/remote_image.dart';

Color parseHexColor(String hex, {Color fallback = const Color(0xFFEBEBEB)}) {
  var s = hex.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return fallback;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return fallback;
  return Color(v);
}

/// The category's own icon — a bundled asset when there is one, the catalog's
/// SVG otherwise, nothing at all when the category has neither.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon({
    super.key,
    required this.category,
    required this.color,
    required this.size,
    required this.gap,
  });

  final AppCategory category;
  final Color color;
  final double size;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final asset = category.iconAsset;
    final uri = category.iconUri;
    if (asset != null) {
      return Padding(
        padding: EdgeInsets.only(right: gap),
        child: QIcon(asset: asset, color: color, size: size),
      );
    }
    if (uri == null || uri.isEmpty) return const SizedBox.shrink();
    // Until it loads, and if it never does, the chip is just its label: an
    // empty slot the icon's size used to pad a broken icon into the chip.
    return SafeNetworkSvg(
      url: uri,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      placeholder: const SizedBox.shrink(),
      padding: EdgeInsets.only(right: gap),
    );
  }
}

class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.category,
    required this.selected,
    this.onTap,
  });

  final AppCategory category;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final base = parseHexColor(category.color);
    final bg = selected
        ? base
        : Color.alphaBlend(base.withAlpha(70), colors.card);
    const textColor = Colors.black;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CategoryIcon(
                category: category,
                color: textColor,
                size: 14,
                gap: 6,
              ),
              Text(
                category.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String catalogFamilyLabel(BuildContext context, CatalogFamily family) =>
    switch (family) {
      CatalogFamily.apps => context.l10n.navApps,
      CatalogFamily.animations => context.l10n.catalogFamilyAnimations,
      CatalogFamily.menuStyles => context.l10n.catalogFamilyMenuStyles,
      CatalogFamily.cli => context.l10n.catalogFamilyCli,
    };

String catalogFamilyIcon(CatalogFamily family) => switch (family) {
  CatalogFamily.apps => 'assets/ic/app/apps.svg',
  CatalogFamily.animations => 'assets/ic/app/paint.svg',
  CatalogFamily.menuStyles => 'assets/ic/app/settings.svg',
  CatalogFamily.cli => 'assets/ic/app/cli.svg',
};

class SectionChip extends StatelessWidget {
  const SectionChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.asset,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? asset;

  @override
  Widget build(BuildContext context) {
    return CategoryChip(
      category: AppCategory(
        id: label,
        name: label,
        color: context.appColors.accent.toARGB32().toRadixString(16),
        iconAsset: asset,
      ),
      selected: selected,
      onTap: onTap,
    );
  }
}

class FamilyChip extends StatelessWidget {
  const FamilyChip({
    super.key,
    required this.family,
    required this.selected,
    this.count,
    this.onTap,
  });

  final CatalogFamily family;
  final bool selected;
  final int? count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = catalogFamilyLabel(context, family);
    return SectionChip(
      label: count == null ? label : '$label $count',
      selected: selected,
      onTap: onTap,
      asset: catalogFamilyIcon(family),
    );
  }
}
