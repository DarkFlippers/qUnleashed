import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';
import '../controller.dart';
import '../../../../components/archive/category.dart';
import '../../../../components/archive/models/fap.dart';
import '../../../../components/archive/models/key.dart';
import '../../../../components/codec/fap/icon.dart';
import '../../../../components/icon.dart';
import '../../../../components/navigation.dart';
import '../../../../components/notification.dart';
import '../../widgets/actions_sheet.dart';
import '../../../../components/filelist/empty_view.dart';
import '../widgets/key_actions_sheet.dart';
import '../../../../components/filelist/columns.dart';
import 'sort.dart';
import '../../../../components/filelist/table.dart';
import '../../../../components/filelist/toolbar.dart';

/// Lists everything starred — keys of every category plus the favorite apps
/// read off the device — in the unified table used by the deleted page. Key
/// rows carry their category icon and the columns common to all categories;
/// app rows have no key metadata, so they trail the keys and leave those
/// columns blank.
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key, required this.controller});

  final ArchiveController controller;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  static const Color _starColor = Color(0xFFFFC107);

  final TextEditingController _searchCtrl = TextEditingController();

  String _query = '';
  String? _filterVal;
  String _sortKey = 'name';
  bool _sortAsc = true;

  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  ArchiveController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_ctrl.loadMetaForFavorites());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Starred keys of every category, in the category order of the rail.
  List<ArchiveKey> _starredKeys() => [
    for (final cat in ArchiveCategory.values)
      ..._ctrl.keysFor(cat).where((k) => k.favorite),
  ];

  /// Distinct protocol tokens across the starred keys, feeding the filter menu.
  /// A key's protocol may itself be a comma-joined list (e.g. infrared remotes),
  /// so it is split into individual tokens.
  List<String> _filterOptions(List<ArchiveKey> keys) {
    final opts = <String>{};
    for (final k in keys) {
      opts.addAll(_protocolTokens(k));
    }
    return opts.toList()..sort();
  }

  List<String> _protocolTokens(ArchiveKey k) {
    final raw = k.protocol;
    if (raw == null || raw.isEmpty) return const [];
    return [
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  List<ArchiveKey> _visibleKeys(List<ArchiveKey> keys) {
    var out = keys;
    if (_filterVal != null) {
      out = out.where((k) => _protocolTokens(k).contains(_filterVal)).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      out = out.where((k) {
        if (k.name.toLowerCase().contains(q)) return true;
        if (k.subFolder.toLowerCase().contains(q)) return true;
        if (k.category.title.toLowerCase().contains(q)) return true;
        if (k.protocol?.toLowerCase().contains(q) ?? false) return true;
        if (k.meta?.values.any((v) => v.toLowerCase().contains(q)) ?? false) {
          return true;
        }
        return false;
      }).toList();
    }
    return sortArchiveKeys(out, _sortKey, _sortAsc);
  }

  /// Apps have no protocol, so an active protocol filter hides them all. They
  /// only ever sort by name, following the name column's direction.
  List<FapFavorite> _visibleFaps(List<FapFavorite> faps) {
    if (_filterVal != null) return const [];
    var out = faps;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      out = out.where((f) {
        if (f.name.toLowerCase().contains(q)) return true;
        if (f.subFolder.toLowerCase().contains(q)) return true;
        return false;
      }).toList();
    }
    out = [...out]..sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    if (_sortKey == 'name' && !_sortAsc) return out.reversed.toList();
    return out;
  }

  List<ArchiveKey> get _selectedKeys =>
      _starredKeys().where((k) => _selected.contains(_keyId(k))).toList();

  void _enterSelection(ArchiveKey key) {
    setState(() {
      _selectionMode = true;
      _selected.add(_keyId(key));
    });
  }

  void _toggleSelect(ArchiveKey key) {
    final id = _keyId(key);
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _setAllSelected(List<ArchiveKey> filtered, bool selected) {
    setState(() {
      if (selected) {
        _selected.addAll(filtered.map(_keyId));
      } else {
        _selected.removeAll(filtered.map(_keyId));
        if (_selected.isEmpty) _selectionMode = false;
      }
    });
  }

  void _onSort(String key) {
    setState(() {
      if (_sortKey == key) {
        _sortAsc = !_sortAsc;
      } else {
        _sortKey = key;
        _sortAsc = true;
      }
    });
  }

  Future<void> _bulkUnstar() async {
    await _ctrl.setKeysFavorite(_selectedKeys, false);
    _exitSelection();
  }

  Future<void> _showBulkActions(BuildContext context) async {
    final keys = _selectedKeys;
    if (keys.isEmpty) return;

    final actions = <ActionItem>[
      ActionItem(
        icon: Icons.star_outline_rounded,
        label: 'Unstar',
        onTap: _bulkUnstar,
      ),
      ...KeyActionsSheet.deleteActions(
        context,
        _ctrl,
        keys,
        onDone: _exitSelection,
      ),
    ];

    await ActionsSheet.show(
      context,
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _starColor.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.star_rounded, color: _starColor, size: 22),
      ),
      title: '${keys.length} ${keys.length == 1 ? 'file' : 'files'} selected',
      subtitle: 'Favorites',
      actions: actions,
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
      openRoute(context, AppRoute.remoteControl);
    } else {
      context.showNotification(
        'Failed to launch ${fav.name}',
        type: QNotificationType.error,
      );
    }
  }

  Future<void> _showFapActions(BuildContext context, FapFavorite fav) {
    final colors = context.appColors;
    final icon = fav.icon;
    return ActionsSheet.show(
      context,
      leading: icon != null
          ? QIconBadge.xbm(
              bytes: icon,
              width: fapIconWidth,
              height: fapIconHeight,
              cacheKey: fav.remotePath,
              color: colors.accent,
              iconSize: 22,
            )
          : QIconBadge(
              asset: 'assets/ic/app/apps.svg',
              color: colors.accent,
              iconSize: 22,
            ),
      title: fav.name,
      subtitle: fav.remotePath,
      actions: [
        ActionItem(
          icon: Icons.play_arrow_rounded,
          label: 'Launch',
          onTap: () => _launchFap(fav),
        ),
        ActionItem(
          icon: Icons.star_outline_rounded,
          label: 'Unstar',
          onTap: () => _ctrl.removeFapFavorite(fav),
        ),
      ],
    );
  }

  String _keyId(ArchiveKey k) =>
      '${k.flipperDir}/${k.subFolder.isEmpty ? '' : '${k.subFolder}/'}${k.name}.${k.extension}';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final headerColor = colors.adaptCategoryHeader(_starColor);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final allKeys = _starredKeys();
        final allFaps = _ctrl.fapFavorites;
        final filterOpts = _filterOptions(allKeys);
        if (_filterVal != null && !filterOpts.contains(_filterVal)) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => setState(() => _filterVal = null),
          );
        }
        final keys = _visibleKeys(allKeys);
        final faps = _visibleFaps(allFaps);
        final allSelected =
            keys.isNotEmpty && keys.every((k) => _selected.contains(_keyId(k)));

        return PopScope(
          canPop: !_selectionMode,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _selectionMode) _exitSelection();
          },
          child: Scaffold(
            backgroundColor: colors.background,
            appBar: AppBar(
              backgroundColor: headerColor,
              foregroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              titleSpacing: categoryTitleSpacing(context),
              title: const _FavoritesAppBarTitle(),
              actions: [
                CategoryCountBadge(
                  filtered: keys.length + faps.length,
                  total: allKeys.length + allFaps.length,
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(50),
                child: _selectionMode
                    ? CategorySelectionToolbar(
                        count: _selected.length,
                        allSelected: allSelected,
                        catColor: headerColor,
                        onClose: _exitSelection,
                        onToggleAll: () => _setAllSelected(keys, !allSelected),
                        onActions: () => _showBulkActions(context),
                      )
                    : CategoryToolbar(
                        searchCtrl: _searchCtrl,
                        query: _query,
                        filterVal: _filterVal,
                        filterOpts: filterOpts,
                        starredOnly: false,
                        catColor: headerColor,
                        colors: colors,
                        showStar: false,
                        onQueryChanged: (v) => setState(() => _query = v),
                        onFilterChanged: (v) => setState(() => _filterVal = v),
                        onStarredToggle: () {},
                      ),
              ),
            ),
            body: LayoutBuilder(
              builder: (ctx, constraints) {
                final cols = layoutColumns(
                  deletedColumns(),
                  constraints.maxWidth -
                      (_selectionMode ? kSelectionIndicatorWidth : 0),
                  keys,
                );

                return RefreshIndicator(
                  color: headerColor,
                  displacement: 15,
                  onRefresh: _ctrl.refresh,
                  child: keys.isEmpty && faps.isEmpty
                      ? SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: constraints.maxHeight,
                            child: ArchiveEmptyView(
                              icon: Icons.star_outline_rounded,
                              title: _query.isNotEmpty
                                  ? 'No results for "$_query"'
                                  : _filterVal != null
                                  ? 'No files matching filter'
                                  : _ctrl.loading
                                  ? 'Loading…'
                                  : 'No starred keys yet',
                              subtitle:
                                  (_query.isNotEmpty || _filterVal != null)
                                  ? null
                                  : 'Open a category and star files to see '
                                        'them here',
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            ArchiveColumnHeader(
                              cols: cols,
                              sortKey: _sortKey,
                              sortAsc: _sortAsc,
                              onSort: _onSort,
                              colors: colors,
                              selectionMode: _selectionMode,
                            ),
                            Expanded(
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: ClampingScrollPhysics(),
                                ),
                                itemCount: keys.length + faps.length,
                                itemBuilder: (_, i) {
                                  if (i >= keys.length) {
                                    final fap = faps[i - keys.length];
                                    return _FapTableRow(
                                      key: ValueKey(fap.remotePath),
                                      favorite: fap,
                                      cols: cols,
                                      colors: colors,
                                      selectionMode: _selectionMode,
                                      onTap: () => _launchFap(fap),
                                      onLongPress: () =>
                                          _showFapActions(context, fap),
                                    );
                                  }
                                  final key = keys[i];
                                  return ArchiveTableRow(
                                    key: ValueKey(_keyId(key)),
                                    flipperKey: key,
                                    cols: cols,
                                    colors: colors,
                                    cat: key.category,
                                    showCategoryIcon: true,
                                    progress: _ctrl.progressForKey(key),
                                    selectionMode: _selectionMode,
                                    selected: _selected.contains(_keyId(key)),
                                    onTap: () => _selectionMode
                                        ? _toggleSelect(key)
                                        : KeyActionsSheet.show(
                                            context,
                                            _ctrl,
                                            key,
                                            onToggleFavorite: () =>
                                                _ctrl.toggleFavorite(key),
                                          ),
                                    onLongPress: () => _selectionMode
                                        ? _toggleSelect(key)
                                        : _enterSelection(key),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Favorite app row. Mirrors [ArchiveTableRow]'s geometry so both kinds of rows
/// line up under the same header, with the key-only columns left blank.
class _FapTableRow extends StatelessWidget {
  const _FapTableRow({
    super.key,
    required this.favorite,
    required this.cols,
    required this.colors,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  final FapFavorite favorite;
  final List<SizedColumn> cols;
  final QAppColors colors;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.card,
      child: InkWell(
        onTap: selectionMode ? null : onTap,
        onLongPress: selectionMode ? null : onLongPress,
        splashColor: colors.accent.withValues(alpha: 0.06),
        highlightColor: colors.accent.withValues(alpha: 0.04),
        child: Container(
          height: kRowHeight,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.divider.withValues(alpha: 0.6)),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              if (selectionMode) const SizedBox(width: kSelectionIndicatorWidth),
              for (final e in cols)
                SizedBox(
                  width: e.width,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: e.col.width == 0
                        ? _nameCell()
                        : _emptyCell(right: e.col.right),
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nameCell() {
    final icon = favorite.icon;
    final sub = favorite.subFolder;
    return Row(
      children: [
        if (icon != null)
          QIconBadge.xbm(
            bytes: icon,
            width: fapIconWidth,
            height: fapIconHeight,
            cacheKey: favorite.remotePath,
            color: colors.accent,
            size: 28,
            iconSize: 16,
            backgroundOpacity: 0.14,
            borderRadius: 7,
          )
        else
          QIconBadge(
            asset: 'assets/ic/app/apps.svg',
            color: colors.accent,
            size: 28,
            iconSize: 16,
            backgroundOpacity: 0.14,
            borderRadius: 7,
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                favorite.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                sub.isEmpty ? '/apps/' : '/apps/$sub/',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textMuted, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyCell({required bool right}) {
    return Align(
      alignment: right ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        '—',
        style: TextStyle(color: colors.textMuted, fontSize: 12),
      ),
    );
  }
}

class _FavoritesAppBarTitle extends StatelessWidget {
  const _FavoritesAppBarTitle();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.star_rounded, color: Colors.white, size: 18),
        SizedBox(width: 8),
        Text(
          'Favorites',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
