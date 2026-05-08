import 'dart:io' as io;

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'archive_controller.dart';
import 'models/archive_category.dart';
import 'widgets/archive_empty_view.dart';
import 'widgets/categories_card.dart';
import 'widgets/category_page.dart';
import 'widgets/key_actions_sheet.dart';
import 'widgets/key_card.dart';
import 'widgets/section_title.dart';
import 'widgets/sync_progress_view.dart';

class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  final ArchiveController _ctrl = ArchiveController();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.initialize();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _ctrl.dispose();
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
            onRefresh: _ctrl.refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: _topInset(context))),
                if (_ctrl.syncing)
                  SliverToBoxAdapter(
                    child: SyncProgressView(progress: _ctrl.syncProgress),
                  ),
                SliverToBoxAdapter(
                  child: CategoriesCard(
                    controller: _ctrl,
                    onOpenCategory: _openCategory,
                    onOpenDeleted: _openDeleted,
                  ),
                ),
                ..._buildKeysSlivers(context),
              ],
            ),
          ),
          floatingActionButton: _ctrl.isConnected
              ? FloatingActionButton(
                  onPressed: _ctrl.syncing ? null : _ctrl.syncAll,
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
                  child: _ctrl.syncing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onAccent,
                          ),
                        )
                      : const Icon(Icons.sync),
                )
              : null,
        );
      },
    );
  }

  List<Widget> _buildKeysSlivers(BuildContext context) {
    final favorites = _ctrl.favoriteKeys();
    final others = _ctrl.nonFavoriteKeys();

    if (favorites.isEmpty && others.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ArchiveEmptyView(
            icon: Icons.folder_open,
            title: _ctrl.loading ? 'Loading…' : _emptyTitle(),
            subtitle: _ctrl.lastError,
          ),
        ),
      ];
    }

    final slivers = <Widget>[];
    if (favorites.isNotEmpty) {
      slivers.add(const SliverToBoxAdapter(
        child: SectionTitle(text: 'FAVORITES'),
      ));
      slivers.add(_keysSliver(favorites));
    }
    if (others.isNotEmpty) {
      slivers.add(const SliverToBoxAdapter(
        child: SectionTitle(text: 'ALL KEYS'),
      ));
      slivers.add(_keysSliver(others));
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 96)));
    return slivers;
  }

  String _emptyTitle() {
    if (!_ctrl.isConnected) {
      return 'Connect a Flipper to load the archive';
    }
    return 'No keys found';
  }

  Widget _keysSliver(List<dynamic> keys) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.separated(
        itemCount: keys.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final k = keys[i];
          return KeyCard(
            flipperKey: k,
            onTap: () => KeyActionsSheet.show(context, _ctrl, k),
          );
        },
      ),
    );
  }
}
