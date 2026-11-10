import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../../data/catalog_api.dart' show CatalogFamily;
import '../../data/models/author.dart';
import '../../data/models/card.dart';
import '../controller.dart';
import 'action_button.dart';
import 'animation_preview.dart';
import 'author_card.dart';
import 'card.dart';
import 'layout.dart';
import 'screenshot_frame.dart';
import 'screenshots_viewer.dart';
import 'states.dart';

class CatalogGrid extends StatelessWidget {
  const CatalogGrid({
    super.key,
    required this.controller,
    required this.apps,
    required this.family,
    required this.onOpen,
    this.emptyMessage,
  });

  final AppsCatalogController controller;
  final List<AppCard> apps;
  final CatalogFamily family;
  final ValueChanged<AppCard> onOpen;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (apps.isEmpty) {
      if (controller.appsLoading) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: colors.accent)),
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: CatalogEmptyView(
          failed: controller.lastError != null,
          message: emptyMessage,
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: catalogGutter(context)),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          const cardWidth = 360.0;
          const spacing = 12.0;
          final cross = (constraints.crossAxisExtent / cardWidth).floor().clamp(
            1,
            6,
          );
          final screenCards = family.previewCards;
          final tileWidth =
              (constraints.crossAxisExtent - spacing * (cross - 1)) / cross;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cross,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              mainAxisExtent: screenCards
                  ? ScreenCardView.heightFor(tileWidth)
                  : family.listScreenshots
                  ? 220
                  : AppCardView.compactHeight(context),
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final app = apps[index];
              final cat = controller.categoryFor(app);
              final action = AppActionButton(
                engine: controller.engine,
                state: controller.stateFor(app),
                app: app,
                category: cat,
                family: family,
              );
              if (screenCards) {
                return ScreenCardView(
                  app: app,
                  category: cat,
                  onTap: () => onOpen(app),
                  action: action,
                  preview: family == CatalogFamily.animations
                      ? AnimationPreview(
                          files: controller.animationFiles,
                          versionId: app.currentVersion?.id ?? '',
                          still: true,
                        )
                      : GestureDetector(
                          onTap: app.screenshots.isEmpty
                              ? null
                              : () => ScreenshotsViewer.open(
                                  context,
                                  screenshots: app.screenshots,
                                  initialIndex: 0,
                                  title: app.name,
                                ),
                          child: ScreenshotFrame(
                            url: app.screenshots.isEmpty
                                ? ''
                                : app.screenshots.first,
                          ),
                        ),
                );
              }
              return AppCardView(
                app: app,
                category: cat,
                onTap: () => onOpen(app),
                action: action,
                showScreenshots: family.listScreenshots,
              );
            }, childCount: apps.length),
          );
        },
      ),
    );
  }
}

class AuthorsGrid extends StatelessWidget {
  const AuthorsGrid({super.key, required this.authors, required this.onOpen});

  final List<AuthorSummary> authors;
  final ValueChanged<AuthorSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: catalogGutter(context)),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          const tileWidth = 280.0;
          final cross = (constraints.crossAxisExtent / tileWidth).floor().clamp(
            1,
            6,
          );
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cross,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: AuthorCardView.height,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final author = authors[index];
              return AuthorCardView(
                author: author,
                onTap: () => onOpen(author),
              );
            }, childCount: authors.length),
          );
        },
      ),
    );
  }
}

class CatalogFooter extends StatelessWidget {
  const CatalogFooter({
    super.key,
    required this.controller,
    required this.hasItems,
  });

  final AppsCatalogController controller;
  final bool hasItems;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (controller.appsLoading && hasItems) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator(color: colors.accent)),
      );
    }
    if (controller.reachedEnd && hasItems) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            context.l10n.catalogEnd,
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ),
      );
    }
    return const SizedBox(height: 16);
  }
}
