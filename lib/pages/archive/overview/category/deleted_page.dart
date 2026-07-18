import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';
import '../controller.dart';
import '../../data/models/key.dart';
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

        return Scaffold(
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
              child: CategoryToolbar(
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
                constraints.maxWidth,
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
                            subtitle: (_query.isNotEmpty || _filterVal != null)
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
                                  onTap: () => KeyActionsSheet.show(
                                    context,
                                    _ctrl,
                                    key,
                                  ),
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
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Cached after remote delete',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0x80FFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
