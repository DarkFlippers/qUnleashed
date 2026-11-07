import 'package:flutter/material.dart';

import '../../../../components/icon.dart';
import '../../../../theme/theme.dart';
import '../../data/catalog_api.dart' show CatalogFamily;
import '../../data/models/author.dart';
import 'card.dart';
import 'category_chip.dart';

class AuthorAvatar extends StatelessWidget {
  const AuthorAvatar({super.key, required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = QIconBadgeStyle.of(context, context.appColors.accent);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.background,
        shape: BoxShape.circle,
      ),
      child: Text(
        name.isEmpty ? '@' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: style.foreground,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class AuthorCardView extends StatelessWidget {
  const AuthorCardView({super.key, required this.author, this.onTap});

  static const double height = 64;

  final AuthorSummary author;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final downloads = author.downloads ?? 0;
    final counts = [
      for (final family in CatalogFamily.values)
        if ((author.counts[family.serverName] ?? 0) > 0)
          '${catalogFamilyLabel(context, family)} '
              '${author.counts[family.serverName]}',
    ].join(' · ');
    return CatalogCardFrame(
      onTap: onTap,
      padding: 12,
      child: Row(
        children: [
          AuthorAvatar(name: author.name, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '@${author.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                    height: 1.2,
                  ),
                ),
                if (counts.isNotEmpty || downloads > 0) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          counts,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (downloads > 0) ...[
                        if (counts.isNotEmpty) const SizedBox(width: 8),
                        DownloadsBadge(count: downloads),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AuthorsStrip extends StatelessWidget {
  const AuthorsStrip({
    super.key,
    required this.authors,
    required this.onOpen,
    this.padding = EdgeInsets.zero,
  });

  final List<AuthorSummary> authors;
  final ValueChanged<AuthorSummary> onOpen;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AuthorCardView.height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: authors.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(
          width: 260,
          child: AuthorCardView(
            author: authors[i],
            onTap: () => onOpen(authors[i]),
          ),
        ),
      ),
    );
  }
}
