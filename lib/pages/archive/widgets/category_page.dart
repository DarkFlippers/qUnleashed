import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../controller.dart';
import '../models/category.dart';
import '../models/key.dart';
import 'empty_view.dart';
import 'key_actions_sheet.dart';
import 'key_card.dart';
import 'sync_progress_view.dart';

class CategoryPage extends StatefulWidget {
  const CategoryPage({
    super.key,
    required this.controller,
    required this.category,
  });

  final ArchiveController controller;
  final ArchiveCategory category;

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String? _protocolFilter;
  bool _starredOnly = false;

  ArchiveController get _ctrl => widget.controller;
  ArchiveCategory get _cat => widget.category;

  @override
  void initState() {
    super.initState();
    unawaited(_ctrl.loadMetaForCategory(_cat));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ArchiveKey> get _filteredKeys {
    var keys = _ctrl.keysFor(_cat);
    if (_starredOnly) {
      keys = keys.where((k) => k.favorite).toList();
    }
    if (_protocolFilter != null) {
      keys = keys.where((k) => k.protocol == _protocolFilter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      keys = keys.where((k) {
        if (k.name.toLowerCase().contains(q)) return true;
        if (k.protocol?.toLowerCase().contains(q) ?? false) return true;
        if (k.extra?.toLowerCase().contains(q) ?? false) return true;
        return false;
      }).toList();
    }
    return keys;
  }

  List<String> get _allProtocols {
    final protocols = <String>{};
    for (final k in _ctrl.keysFor(_cat)) {
      if (k.protocol != null && k.protocol!.isNotEmpty) {
        protocols.add(k.protocol!);
      }
    }
    return protocols.toList()..sort();
  }

  void _clearProtocolFilter() {
    if (_protocolFilter != null) {
      setState(() => _protocolFilter = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final catColor = _cat.color;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final protocols = _allProtocols;
        final filtered = _filteredKeys;
        final total = _ctrl.keysFor(_cat).length;

        // If selected protocol no longer exists, clear it
        if (_protocolFilter != null && !protocols.contains(_protocolFilter)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _clearProtocolFilter());
        }

        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: catColor,
            foregroundColor: Colors.white,
            elevation: 0,
            titleSpacing: 0,
            title: Row(
              children: [
                SvgPicture.asset(
                  _cat.asset,
                  width: 18,
                  height: 18,
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
                const SizedBox(width: 8),
                Text(
                  _cat.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _cat.remoteDir,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _query.isNotEmpty || _protocolFilter != null || _starredOnly
                          ? '${filtered.length}/$total'
                          : '$total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              if (_ctrl.syncing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: _SearchFilterBar(
                searchCtrl: _searchCtrl,
                query: _query,
                protocolFilter: _protocolFilter,
                protocols: protocols,
                starredOnly: _starredOnly,
                catColor: catColor,
                onQueryChanged: (v) => setState(() => _query = v),
                onProtocolChanged: (v) => setState(() => _protocolFilter = v),
                onStarredToggle: () => setState(() => _starredOnly = !_starredOnly),
              ),
            ),
          ),
          body: RefreshIndicator(
            color: catColor,
            onRefresh: () => _ctrl.syncCategory(_cat),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (_ctrl.syncing)
                  SliverToBoxAdapter(
                    child: SyncProgressView(progress: _ctrl.syncProgress),
                  ),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ArchiveEmptyView(
                      icon: Icons.folder_open,
                      title: _emptyTitle(),
                      subtitle: _ctrl.lastError,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    sliver: SliverList.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _CategoryKeyCard(
                        flipperKey: filtered[i],
                        onTap: () => KeyActionsSheet.show(context, _ctrl, filtered[i]),
                        onToggleFavorite: () => _ctrl.toggleFavorite(filtered[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _emptyTitle() {
    if (_starredOnly) return 'No starred ${_cat.title} keys';
    if (_protocolFilter != null) return 'No keys with protocol "$_protocolFilter"';
    if (_query.isNotEmpty) return 'No results for "$_query"';
    if (!_ctrl.isConnected) {
      return 'No ${_cat.title} keys\nConnect a Flipper to sync';
    }
    return 'No ${_cat.title} keys\nPull down to sync';
  }
}

class _SearchFilterBar extends StatelessWidget {
  const _SearchFilterBar({
    required this.searchCtrl,
    required this.query,
    required this.protocolFilter,
    required this.protocols,
    required this.starredOnly,
    required this.catColor,
    required this.onQueryChanged,
    required this.onProtocolChanged,
    required this.onStarredToggle,
  });

  final TextEditingController searchCtrl;
  final String query;
  final String? protocolFilter;
  final List<String> protocols;
  final bool starredOnly;
  final Color catColor;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onProtocolChanged;
  final VoidCallback onStarredToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: catColor,
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchCtrl,
              onChanged: onQueryChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search…',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 18,
                ),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.7), size: 16),
                        onPressed: () {
                          searchCtrl.clear();
                          onQueryChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.15),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.4), width: 1),
                ),
                isDense: true,
              ),
            ),
          ),
          if (protocols.isNotEmpty) ...[
            const SizedBox(width: 6),
            _ProtocolFilterButton(
              selected: protocolFilter,
              protocols: protocols,
              catColor: catColor,
              onChanged: onProtocolChanged,
            ),
          ],
          const SizedBox(width: 2),
          _StarToggle(active: starredOnly, onToggle: onStarredToggle),
        ],
      ),
    );
  }
}

class _ProtocolFilterButton extends StatelessWidget {
  const _ProtocolFilterButton({
    required this.selected,
    required this.protocols,
    required this.catColor,
    required this.onChanged,
  });

  final String? selected;
  final List<String> protocols;
  final Color catColor;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isActive = selected != null;
    return GestureDetector(
      onTap: () => _showSheet(context),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 15,
              color: isActive ? catColor : Colors.white.withValues(alpha: 0.85),
            ),
            if (isActive) ...[
              const SizedBox(width: 4),
              Text(
                selected!,
                style: TextStyle(
                  color: catColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSheet(BuildContext context) {
    final colors = context.appColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Filter by protocol',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Divider(height: 1, color: colors.divider),
            ListTile(
              title: Text('All protocols',
                  style: TextStyle(color: colors.textPrimary)),
              trailing: selected == null
                  ? Icon(Icons.check_rounded, color: catColor)
                  : null,
              onTap: () {
                Navigator.pop(context);
                onChanged(null);
              },
            ),
            for (final p in protocols)
              ListTile(
                title: Text(p, style: TextStyle(color: colors.textPrimary)),
                trailing: selected == p
                    ? Icon(Icons.check_rounded, color: catColor)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  onChanged(p);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _StarToggle extends StatelessWidget {
  const _StarToggle({required this.active, required this.onToggle});

  final bool active;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          active ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 18,
          color: active ? Colors.amber.shade700 : Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

class _CategoryKeyCard extends StatelessWidget {
  const _CategoryKeyCard({
    required this.flipperKey,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final ArchiveKey flipperKey;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final k = flipperKey;
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: k.category.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SvgPicture.asset(
                  k.category.asset,
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(
                    k.category.color,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            k.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (k.protocol != null && k.protocol!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: k.category.color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              k.protocol!,
                              style: TextStyle(
                                color: k.category.color,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (k.extra != null || k.subFolder.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      _SecondaryRow(
                        extra: k.extra,
                        subFolder: k.subFolder.isNotEmpty ? k.subFolder : null,
                        muted: colors.textMuted,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _StateBadge(state: k.state, colors: colors),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggleFavorite,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    k.favorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: k.favorite
                        ? Colors.amber.shade600
                        : colors.textMuted,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryRow extends StatelessWidget {
  const _SecondaryRow({this.extra, this.subFolder, required this.muted});

  final String? extra;
  final String? subFolder;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: muted, fontSize: 12);
    if (extra != null && subFolder != null) {
      return Row(
        children: [
          Flexible(child: Text(extra!, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('·', style: style),
          ),
          Flexible(child: Text(subFolder!, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      );
    }
    return Text(
      extra ?? subFolder ?? '',
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state, required this.colors});

  final ArchiveKeyState state;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color tint;
    switch (state) {
      case ArchiveKeyState.synced:
        icon = Icons.cloud_done_outlined;
        tint = colors.success;
        break;
      case ArchiveKeyState.local:
        icon = Icons.sd_storage_outlined;
        tint = colors.textMuted;
        break;
      case ArchiveKeyState.deleted:
        icon = Icons.delete_outline;
        tint = colors.danger;
        break;
    }
    return Icon(icon, color: tint, size: 20);
  }
}

// ---------------------------------------------------------------------------

class DeletedPage extends StatelessWidget {
  const DeletedPage({super.key, required this.controller});

  final ArchiveController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final keys = controller.deletedKeys();
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            title: const Text('Deleted'),
          ),
          body: keys.isEmpty
              ? const ArchiveEmptyView(
                  icon: Icons.delete_outline,
                  title: 'Nothing here',
                  subtitle:
                      'Deleted keys are kept on this device until purged',
                )
              : RefreshIndicator(
                  color: colors.accent,
                  onRefresh: controller.refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: keys.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => KeyCard(
                      flipperKey: keys[i],
                      onTap: () => KeyActionsSheet.show(context, controller, keys[i]),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
