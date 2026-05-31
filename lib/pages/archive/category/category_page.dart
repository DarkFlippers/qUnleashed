import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../controller.dart';
import '../models/category.dart';
import '../models/key.dart';
import '../widgets/empty_view.dart';
import '../widgets/key_actions_sheet.dart';
import 'columns.dart';
import 'sort.dart';
import 'table.dart';
import 'toolbar.dart';

/// Sortable, filterable table of all keys in a single [ArchiveCategory].
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
  String? _filterVal;
  bool _starredOnly = false;
  String _sortKey = 'name';
  bool _sortAsc = true;

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

  // ── Data ──────────────────────────────────────────────────────────────────

  List<ArchiveKey> get _allKeys => _ctrl.keysFor(_cat);

  List<String> get _filterOptions {
    final opts = <String>{};
    for (final k in _allKeys) {
      final v = _filterValue(k);
      if (v != null && v.isNotEmpty) opts.add(v);
    }
    return opts.toList()..sort();
  }

  String? _filterValue(ArchiveKey k) {
    switch (_cat) {
      case ArchiveCategory.nfc:
        return k.meta?['device_type'] ?? k.protocol;
      case ArchiveCategory.rfid:
        return k.meta?['key_type'] ?? k.protocol;
      case ArchiveCategory.infrared:
        return k.meta?['protocols'];
      case ArchiveCategory.subghz:
      case ArchiveCategory.wardriving:
        return k.protocol;
      case ArchiveCategory.ibutton:
        return k.meta?['key_type'] ?? k.protocol;
      case ArchiveCategory.badusb:
        return k.meta?['kind'];
      case ArchiveCategory.javascript:
        return null;
    }
  }

  List<ArchiveKey> get _filtered {
    var keys = _allKeys;
    if (_starredOnly) keys = keys.where((k) => k.favorite).toList();
    if (_filterVal != null) {
      keys = keys.where((k) => _filterValue(k) == _filterVal).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      keys = keys.where((k) {
        if (k.name.toLowerCase().contains(q)) return true;
        if (k.protocol?.toLowerCase().contains(q) ?? false) return true;
        if (k.extra?.toLowerCase().contains(q) ?? false) return true;
        if (k.meta?.values.any((v) => v.toLowerCase().contains(q)) ?? false) {
          return true;
        }
        return false;
      }).toList();
    }
    return sortArchiveKeys(keys, _sortKey, _sortAsc);
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

  String _emptyTitle() {
    if (_starredOnly) return 'No starred ${_cat.title} keys';
    if (_filterVal != null) return 'No keys matching filter';
    if (_query.isNotEmpty) return 'No results for "$_query"';
    if (!_ctrl.isConnected) {
      return 'No ${_cat.title} keys\nConnect a Flipper to sync';
    }
    return 'No ${_cat.title} keys\nPull down to sync';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final catColor = colors.adaptCategoryHeader(_cat.color);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final filtered = _filtered;
        final total = _allKeys.length;
        final filterOpts = _filterOptions;
        if (_filterVal != null && !filterOpts.contains(_filterVal)) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => setState(() => _filterVal = null));
        }

        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: catColor,
            foregroundColor: Colors.white,
            elevation: 0,
            titleSpacing: 0,
            title: CategoryAppBarTitle(
              cat: _cat,
              syncFileName: _ctrl.syncing ? _ctrl.syncProgress?.fileName : null,
            ),
            actions: [
              CategoryCountBadge(filtered: filtered.length, total: total),
            ],
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(_ctrl.syncing ? 53 : 50),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CategoryToolbar(
                    searchCtrl: _searchCtrl,
                    query: _query,
                    filterVal: _filterVal,
                    filterOpts: filterOpts,
                    starredOnly: _starredOnly,
                    catColor: catColor,
                    colors: colors,
                    onQueryChanged: (v) => setState(() => _query = v),
                    onFilterChanged: (v) => setState(() => _filterVal = v),
                    onStarredToggle: () =>
                        setState(() => _starredOnly = !_starredOnly),
                  ),
                  if (_ctrl.syncing) ...[
                    const SizedBox(height: 1),
                    LinearProgressIndicator(
                      value: () {
                        final p = _ctrl.syncProgress;
                        return (p == null || p.total == 0)
                            ? null
                            : p.current / p.total;
                      }(),
                      minHeight: 2,
                      color: Colors.white.withValues(alpha: 0.9),
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                    ),
                  ],
                ],
              ),
            ),
          ),
          body: LayoutBuilder(
            builder: (ctx, constraints) {
              final (visibleCols, nameW) =
                  visibleColumns(_cat, constraints.maxWidth);

              return RefreshIndicator(
                color: catColor,
                onRefresh: () => _ctrl.syncCategory(_cat),
                child: filtered.isEmpty
                    ? SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: constraints.maxHeight,
                          child: ArchiveEmptyView(
                            icon: Icons.folder_open,
                            title: _emptyTitle(),
                            subtitle: _ctrl.lastError,
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          ArchiveColumnHeader(
                            cols: visibleCols,
                            nameW: nameW,
                            sortKey: _sortKey,
                            sortAsc: _sortAsc,
                            onSort: _onSort,
                            colors: colors,
                          ),
                          Expanded(
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final key = filtered[i];
                                return ArchiveTableRow(
                                  key: ValueKey(_keyId(key)),
                                  flipperKey: key,
                                  cols: visibleCols,
                                  nameW: nameW,
                                  colors: colors,
                                  cat: _cat,
                                  onTap: () => _showKeyActions(context, key),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              );
            },
          ),
        );
      },
    );
  }

  String _keyId(ArchiveKey k) =>
      '${k.category.flipperDir}/${k.subFolder.isEmpty ? '' : '${k.subFolder}/'}${k.name}.${k.extension}';
}
