import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';
import '../controller.dart';
import '../../data/models/key.dart';
import '../widgets/actions_sheet.dart';
import '../widgets/empty_view.dart';
import '../widgets/key_actions_sheet.dart';
import 'columns.dart';
import 'sort.dart';
import 'table.dart';
import 'toolbar.dart';

/// Lists keys deleted remotely but still cached on this device, using the same
/// table design as the per-category pages. Unlike those, every category shares a
/// single table: each row carries its own category icon, and the columns are
/// limited to the fields common to all of them (name/folder, protocol, size,
/// modified).
class DeletedPage extends StatefulWidget {
  const DeletedPage({super.key, required this.controller});

  final ArchiveController controller;

  @override
  State<DeletedPage> createState() => _DeletedPageState();
}

class _DeletedPageState extends State<DeletedPage> {
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
    unawaited(_ctrl.loadMetaForDeleted());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Distinct protocol tokens across all deleted keys, feeding the filter menu.
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

  List<ArchiveKey> _visible(List<ArchiveKey> keys) {
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

  List<ArchiveKey> get _selectedKeys =>
      _ctrl.deletedKeys().where((k) => _selected.contains(_keyId(k))).toList();

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

  Future<void> _bulkRestore() async {
    await _ctrl.restoreKeys(_selectedKeys);
    _exitSelection();
  }

  Future<void> _showBulkActions(BuildContext context) async {
    final keys = _selectedKeys;
    if (keys.isEmpty) return;
    final colors = context.appColors;

    final actions = <ActionItem>[
      if (_ctrl.isConnected)
        ActionItem(icon: Icons.restore, label: 'Restore', onTap: _bulkRestore),
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
          color: colors.accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.delete_outline, color: colors.accent, size: 22),
      ),
      title: '${keys.length} ${keys.length == 1 ? 'file' : 'files'} selected',
      subtitle: 'Deleted',
      actions: actions,
    );
  }

  String _keyId(ArchiveKey k) =>
      '${k.category.flipperDir}/${k.subFolder.isEmpty ? '' : '${k.subFolder}/'}${k.name}.${k.extension}';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final headerColor = colors.adaptCategoryHeader(colors.accent);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final all = _ctrl.deletedKeys();
        final filterOpts = _filterOptions(all);
        if (_filterVal != null && !filterOpts.contains(_filterVal)) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => setState(() => _filterVal = null),
          );
        }
        final filtered = _visible(all);
        final allSelected =
            filtered.isNotEmpty &&
            filtered.every((k) => _selected.contains(_keyId(k)));

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
              titleSpacing: 0,
              title: const _DeletedAppBarTitle(),
              actions: [
                CategoryCountBadge(filtered: filtered.length, total: all.length),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(50),
                child: _selectionMode
                    ? CategorySelectionToolbar(
                        count: _selected.length,
                        allSelected: allSelected,
                        catColor: headerColor,
                        onClose: _exitSelection,
                        onToggleAll: () =>
                            _setAllSelected(filtered, !allSelected),
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
                  filtered,
                );

                return RefreshIndicator(
                  color: headerColor,
                  displacement: 15,
                  onRefresh: _ctrl.refresh,
                  child: filtered.isEmpty
                      ? SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: constraints.maxHeight,
                            child: ArchiveEmptyView(
                              icon: Icons.delete_outline,
                              title: _query.isNotEmpty
                                  ? 'No results for "$_query"'
                                  : _filterVal != null
                                  ? 'No files matching filter'
                                  : 'Nothing here',
                              subtitle:
                                  (_query.isNotEmpty || _filterVal != null)
                                  ? null
                                  : 'Deleted keys are kept on this device '
                                        'until purged',
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
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final key = filtered[i];
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

class _DeletedAppBarTitle extends StatelessWidget {
  const _DeletedAppBarTitle();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.delete_outline, color: Colors.white, size: 18),
        SizedBox(width: 8),
        Text(
          'Deleted',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        )
      ],
    );
  }
}
