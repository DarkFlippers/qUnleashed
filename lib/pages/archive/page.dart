import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme.dart';
import 'controller.dart';
import 'file_manager/page.dart';
import 'models/category.dart';
import 'models/key.dart';
import 'widgets/empty_view.dart';
import 'widgets/categories_card.dart';
import 'widgets/category_page.dart';
import 'widgets/key_actions_sheet.dart';
import 'widgets/key_card.dart';
import 'widgets/my_flipper_button.dart';
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
  final TextEditingController _searchCtrl = TextEditingController();

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
    _searchCtrl.dispose();
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

  void _openFileManager() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FileManagerPage()),
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
            onRefresh: _ctrl.fullSync,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: _topInset(context))),
                SliverToBoxAdapter(
                  child: MyFlipperButton(
                    onTap: _openFileManager,
                    enabled: _ctrl.isConnected,
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

    if (groups.isEmpty) {
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

    final slivers = <Widget>[];
    for (final entry in groups.entries) {
      slivers.add(SliverToBoxAdapter(
        child: _CategoryHeader(cat: entry.key, count: entry.value.length),
      ));
      slivers.add(_keysSliver(entry.value));
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 96)));
    return slivers;
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
            onTap: () => KeyActionsSheet.show(context, _ctrl, k),
          );
        },
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.cat, required this.count});

  final ArchiveCategory cat;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          SvgPicture.asset(
            cat.asset,
            width: 14,
            height: 14,
            colorFilter: ColorFilter.mode(cat.color, BlendMode.srcIn),
          ),
          const SizedBox(width: 6),
          Text(
            cat.title.toUpperCase(),
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            '$count',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
