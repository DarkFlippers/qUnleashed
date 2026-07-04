import 'dart:io' as io;

import 'package:flutter/material.dart';
import '../../../theme/theme.dart';
import '../../../widgets/notification.dart';
import '../../tools/remote/desktop/page.dart';
import '../сommander/page.dart';
import '../сommander/widgets/storage_card.dart';
import 'category/category_page.dart';
import 'category/deleted_page.dart';
import 'controller.dart';
import '../category.dart';
import '../models/fap.dart';
import '../models/key.dart';
import 'widgets/empty_view.dart';
import 'widgets/categories_card.dart';
import 'widgets/fap_favorite_card.dart';
import 'widgets/key_actions_sheet.dart';
import 'widgets/key_card.dart';
import 'widgets/section_title.dart';
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DeletedPage(controller: _ctrl)),
    );
  }

  void _openFileManager(String initialPath) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FileManagerPage(initialPath: initialPath)),
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
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RemoteControlPage()),
      );
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
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Rename')),
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: StorageUsageCards(
                      enabled: _ctrl.isConnected,
                      onOpenInternal: () => _openFileManager('/int'),
                      onOpenExternal: () => _openFileManager('/ext'),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: CategoriesCard(
                    controller: _ctrl,
                    onOpenCategory: _openCategory,
                    onOpenDeleted: _openDeleted,
                  ),
                ),
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

    final allKeys = groups.values.expand((keys) => keys).toList();
    return [
      const SliverToBoxAdapter(child: SectionTitle(text: 'FAVORITES')),
      if (allKeys.isNotEmpty) _keysSliver(allKeys),
      if (fapFavorites.isNotEmpty) _fapSliver(fapFavorites),
      const SliverToBoxAdapter(child: SizedBox(height: 96)),
    ];
  }

  Widget _fapSliver(List<FapFavorite> favorites) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      sliver: SliverList.separated(
        itemCount: favorites.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => Padding(
          padding: EdgeInsets.only(top: i == 0 ? 8 : 0),
          child: FapFavoriteCard(
            favorite: favorites[i],
            onTap: () => _launchFap(favorites[i]),
            onRemove: () => _ctrl.removeFapFavorite(favorites[i]),
          ),
        ),
      ),
    );
  }

  Widget _keysSliver(List<ArchiveKey> keys) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.separated(
        itemCount: keys.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final k = keys[i];
          return KeyCard(
            flipperKey: k,
            onTap: () => _showKeyActions(context, k),
            onToggleStar: () => _ctrl.toggleFavorite(k),
          );
        },
      ),
    );
  }
}
