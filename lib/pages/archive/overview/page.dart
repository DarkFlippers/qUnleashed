import 'dart:io' as io;

import 'package:flutter/material.dart';
import '../../../components/cardlist.dart';
import '../../../components/icon.dart';
import '../../../theme/theme.dart';
import '../../../widgets/notification.dart';
import '../../tools/remote/desktop/page.dart';
import '../browser/page.dart';
import '../browser/widgets/storage_card.dart';
import 'category/category_page.dart';
import 'category/deleted_page.dart';
import 'controller.dart';
import '../data/category.dart';
import '../data/models/fap.dart';
import '../data/models/key.dart';
import 'fap_icon.dart';
import 'widgets/empty_view.dart';
import 'widgets/key_actions_sheet.dart';
import 'widgets/progress_fill.dart';
import 'widgets/sync_progress_view.dart';

class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key, this.controller});

  final ArchiveController? controller;

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  late final ArchiveController _ctrl;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? ArchiveController();
    _ownsController = widget.controller == null;
    if (_ownsController) {
      _ctrl.initialize();
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _ctrl.dispose();
    }
    super.dispose();
  }

  void _openCategory(ArchiveCategory cat) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryPage(controller: _ctrl, category: cat),
      ),
    );
  }

  void _openDeleted() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DeletedPage(controller: _ctrl)));
  }

  Widget _categoriesCard(BuildContext context) {
    final entries = <_CategoryEntry>[
      for (final cat in ArchiveCategory.values)
        _CategoryEntry(
          title: cat.title,
          asset: cat.asset,
          color: cat.color,
          count: _ctrl.countFor(cat),
          onTap: () => _openCategory(cat),
        ),
      _CategoryEntry(
        title: 'Deleted',
        asset: 'assets/ic/action/trash.svg',
        color: const Color(0xFF8D8D8D),
        count: _ctrl.deletedCount,
        onTap: _openDeleted,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: GroupedCardList<_CategoryEntry>(
        items: entries,
        onTap: (e) => e.onTap,
        itemBuilder: _categoryTile,
      ),
    );
  }

  Widget _categoryTile(BuildContext context, _CategoryEntry e) {
    final colors = context.appColors;
    return Row(
      children: [
        QIconBadge(asset: e.asset, color: e.color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            e.title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          '${e.count}',
          style: TextStyle(color: colors.textMuted, fontSize: 14),
        ),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right, color: colors.textMuted),
      ],
    );
  }

  void _openFileManager(String initialPath) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FileManagerPage(initialPath: initialPath),
      ),
    );
  }

  Future<void> _launchFap(FapFavorite fav) async {
    if (!_ctrl.isConnected) {
      context.showNotification(
        'Connect a device to launch apps',
        type: QNotificationType.warning,
      );
      return;
    }
    final ok = await _ctrl.launchFapFavorite(fav);
    if (!mounted) return;
    if (ok) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const RemoteControlPage()));
    } else {
      context.showNotification(
        'Failed to launch ${fav.name}',
        type: QNotificationType.error,
      );
    }
  }

  Future<void> _confirmFullSync() async {
    final colors = context.appColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.dialogBackground,
        title: Text(
          'Sync archive?',
          style: TextStyle(color: colors.dialogText),
        ),
        content: Text(
          'Sync all archive categories and import favorites from device?',
          style: TextStyle(color: colors.dialogMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sync all'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _ctrl.fullSync();
      if (!mounted) return;
      final error = _ctrl.lastError;
      if (error == null) return;
      context.showNotification(
        error,
        type: QNotificationType.error,
        duration: const Duration(seconds: 6),
      );
    }
  }

  Future<void> _showKeyActions(BuildContext context, ArchiveKey key) {
    return KeyActionsSheet.show(
      context,
      _ctrl,
      key,
      onRename: () => _showRenameDialog(context, key),
      onDuplicate: () => _ctrl.duplicateKey(key),
      onToggleFavorite: () => _ctrl.toggleFavorite(key),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, ArchiveKey key) async {
    final colors = context.appColors;
    final ctrl = TextEditingController(text: key.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: colors.dialogBackground,
        title: Text('Rename', style: TextStyle(color: colors.dialogText)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: colors.dialogText),
          decoration: InputDecoration(
            hintText: 'File name',
            hintStyle: TextStyle(color: colors.textMuted),
          ),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newName != null && newName.isNotEmpty && newName != key.name) {
      await _ctrl.renameKey(key, newName);
    }
  }

  double _topInset(BuildContext context) {
    if (io.Platform.isAndroid || io.Platform.isIOS) {
      return MediaQuery.paddingOf(context).top;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: colors.background,
          body: RefreshIndicator(
            color: colors.accent,
            onRefresh: _confirmFullSync,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: _topInset(context))),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 4),
                    child: StorageUsageCards(
                      enabled: _ctrl.isConnected,
                      onOpenInternal: () => _openFileManager('/int'),
                      onOpenExternal: () => _openFileManager('/ext'),
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _categoriesCard(context)),
                if (_ctrl.syncing)
                  SliverToBoxAdapter(
                    child: SyncProgressView(progress: _ctrl.syncProgress),
                  ),
                ..._buildKeysSlivers(context),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildKeysSlivers(BuildContext context) {
    // Group favorites by category (preserve ArchiveCategory order).
    final groups = <ArchiveCategory, List<ArchiveKey>>{};
    for (final cat in ArchiveCategory.values) {
      final starred = _ctrl.keysFor(cat).where((k) => k.favorite).toList();
      if (starred.isNotEmpty) groups[cat] = starred;
    }
    final fapFavorites = _ctrl.fapFavorites;

    if (groups.isEmpty && fapFavorites.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ArchiveEmptyView(
            icon: Icons.star_outline_rounded,
            title: _ctrl.loading ? 'Loading…' : 'No starred keys yet',
            subtitle: 'Open a category and star files to see them here',
          ),
        ),
      ];
    }

    final entries = <_FavEntry>[
      for (final key in groups.values.expand((keys) => keys)) _KeyFav(key),
      for (final fap in fapFavorites) _FapFav(fap),
    ];
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: GroupedCardList<_FavEntry>(
            title: 'Favorites',
            items: entries,
            cardPadding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            onTap: (e) => switch (e) {
              _KeyFav(:final key) => () => _showKeyActions(context, key),
              _FapFav(:final fap) => () => _launchFap(fap),
            },
            backgroundBuilder: (e) => switch (e) {
              _KeyFav(:final key) => ProgressFill(
                progress: _ctrl.progressForKey(key),
              ),
              _FapFav() => null,
            },
            itemBuilder: (context, e) => switch (e) {
              _KeyFav(:final key) => _KeyFavTile(
                flipperKey: key,
                onToggleStar: () => _ctrl.toggleFavorite(key),
              ),
              _FapFav(:final fap) => _FapFavTile(
                favorite: fap,
                onRemove: () => _ctrl.removeFapFavorite(fap),
              ),
            },
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 96)),
    ];
  }
}

class _CategoryEntry {
  const _CategoryEntry({
    required this.title,
    required this.asset,
    required this.color,
    required this.count,
    required this.onTap,
  });

  final String title;
  final String asset;
  final Color color;
  final int count;
  final VoidCallback onTap;
}

sealed class _FavEntry {
  const _FavEntry();
}

class _KeyFav extends _FavEntry {
  const _KeyFav(this.key);

  final ArchiveKey key;
}

class _FapFav extends _FavEntry {
  const _FapFav(this.fap);

  final FapFavorite fap;
}

class _KeyFavTile extends StatelessWidget {
  const _KeyFavTile({required this.flipperKey, required this.onToggleStar});

  final ArchiveKey flipperKey;
  final VoidCallback onToggleStar;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        QIconBadge(
          asset: flipperKey.category.asset,
          color: flipperKey.category.color,
          iconSize: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                flipperKey.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              _KeySubtitle(
                category: flipperKey.category.title,
                subFolder: flipperKey.subFolder,
                muted: colors.textMuted,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _FavStarButton(onTap: onToggleStar),
      ],
    );
  }
}

class _FapFavTile extends StatelessWidget {
  const _FapFavTile({required this.favorite, required this.onRemove});

  final FapFavorite favorite;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final icon = favorite.icon;
    return Row(
      children: [
        if (icon != null)
          QIconBadge.xbm(
            bytes: icon,
            width: fapIconWidth,
            height: fapIconHeight,
            cacheKey: favorite.remotePath,
            color: colors.accent,
            iconSize: 22,
          )
        else
          QIconBadge(
            asset: 'assets/ic/app/apps.svg',
            color: colors.accent,
            iconSize: 22,
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                favorite.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                favorite.subFolder.isEmpty ? 'Apps' : favorite.subFolder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _FavStarButton(onTap: onRemove),
      ],
    );
  }
}

class _FavStarButton extends StatelessWidget {
  const _FavStarButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.star_rounded, size: 18, color: Colors.amber.shade600),
      ),
    );
  }
}

class _KeySubtitle extends StatelessWidget {
  const _KeySubtitle({
    required this.category,
    required this.subFolder,
    required this.muted,
  });

  final String category;
  final String subFolder;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: muted, fontSize: 12);
    if (subFolder.isEmpty) {
      return Text(
        category,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      children: [
        Flexible(
          child: Text(
            category,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            subFolder,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
