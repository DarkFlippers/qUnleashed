import '../../../../services/localization/l10n.dart';
import 'dart:async';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../components/icon.dart';
import '../../../../theme/theme.dart';
import '../../../../components/notification.dart';
import '../controller.dart';
import '../../../../components/archive/category.dart';
import '../../../../components/archive/models/key.dart';
import '../../widgets/actions_sheet.dart';
import '../../../../components/filelist/empty_view.dart';
import '../widgets/key_actions_sheet.dart';
import '../../../../components/filelist/sync_progress_bar.dart';
import '../../../../components/filelist/columns.dart';
import 'sort.dart';
import '../../../../components/filelist/table.dart';
import '../../../../components/filelist/toolbar.dart';
import '../../../../services/logging.dart';

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

  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

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

  List<ArchiveKey> get _allKeys => _ctrl.keysFor(_cat);

  List<String> get _filterOptions {
    final opts = <String>{};
    for (final k in _allKeys) {
      opts.addAll(_filterTokens(k));
    }
    return opts.toList()..sort();
  }

  List<String> _filterTokens(ArchiveKey k) {
    final raw = _filterValue(k);
    if (raw == null || raw.isEmpty) return const [];
    return [
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
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
      keys = keys.where((k) => _filterTokens(k).contains(_filterVal)).toList();
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

  List<ArchiveKey> get _selectedKeys =>
      _allKeys.where((k) => _selected.contains(_keyId(k))).toList();

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

  Future<void> _bulkSetFavorite(bool favorite) async {
    await _ctrl.setKeysFavorite(_selectedKeys, favorite);
    _exitSelection();
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
        title: Text(context.l10n.fmRename, style: TextStyle(color: colors.dialogText)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: colors.dialogText),
          decoration: InputDecoration(
            hintText: context.l10n.archiveFileName,
            hintStyle: TextStyle(color: colors.textMuted),
          ),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: Text(context.l10n.fmRename),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newName != null && newName.isNotEmpty && newName != key.name) {
      await _ctrl.renameKey(key, newName);
    }
  }

  String _emptyTitle() {
    final noun = _cat.itemNounPlural;
    if (_starredOnly) return l10n.archiveEmptyStarred(_cat.title, noun);
    if (_filterVal != null) return l10n.archiveEmptyFilter(noun);
    if (_query.isNotEmpty) return l10n.archiveEmptyQuery(_query);
    if (!_ctrl.isConnected) {
      return l10n.archiveEmptyConnect(_cat.title, noun);
    }
    return l10n.archiveEmptySync(_cat.title, noun);
  }

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
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => setState(() => _filterVal = null),
          );
        }

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
              backgroundColor: catColor,
              foregroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              titleSpacing: categoryTitleSpacing(context),
              title: CategoryAppBarTitle(cat: _cat),
              actions: [
                CategorySyncButton(
                  syncing: _ctrl.syncing,
                  enabled: _ctrl.isConnected,
                  catColor: catColor,
                  onTap: () => _ctrl.syncCategory(_cat),
                ),
                CategoryCountBadge(filtered: filtered.length, total: total),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(50),
                child: _selectionMode
                    ? CategorySelectionToolbar(
                        count: _selected.length,
                        allSelected: allSelected,
                        catColor: catColor,
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
                        starredOnly: _starredOnly,
                        catColor: catColor,
                        colors: colors,
                        onQueryChanged: (v) => setState(() => _query = v),
                        onFilterChanged: (v) => setState(() => _filterVal = v),
                        onStarredToggle: () =>
                            setState(() => _starredOnly = !_starredOnly),
                      ),
              ),
            ),
            body: Column(
              children: [
                if (_ctrl.syncing) _syncBar(catColor),
                Expanded(child: _buildTable(catColor, colors, filtered)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _syncBar(Color catColor) {
    final p = _ctrl.syncProgress;
    final checking = p?.phase == SyncPhase.checking;
    return SyncProgressBar(
      icon: checking ? Icons.sync_rounded : Icons.download_rounded,
      label: p == null
          ? context.l10n.archiveSyncing
          : '${checking ? context.l10n.archiveSyncingLabel : context.l10n.archiveDownloading}'
                ' ${p.current}/${p.total} · ${p.fileName}',
      progress: (p == null || p.total == 0) ? 0 : p.current / p.total,
      fileProgress: p?.fileProgress,
      color: catColor,
    );
  }

  Widget _buildTable(
    Color catColor,
    QAppColors colors,
    List<ArchiveKey> filtered,
  ) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final visibleCols = visibleColumns(
          _cat,
          constraints.maxWidth -
              (_selectionMode ? kSelectionIndicatorWidth : 0),
          filtered,
        );

        return RefreshIndicator(
          color: catColor,
          displacement: 15,
          onRefresh: () async => unawaited(_ctrl.syncCategory(_cat)),
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
                            cols: visibleCols,
                            colors: colors,
                            cat: _cat,
                            progress: _ctrl.progressForKey(key),
                            selectionMode: _selectionMode,
                            selected: _selected.contains(_keyId(key)),
                            onTap: () => _selectionMode
                                ? _toggleSelect(key)
                                : _showKeyActions(context, key),
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
    );
  }

  Future<void> _showBulkActions(BuildContext context) async {
    final keys = _selectedKeys;
    if (keys.isEmpty) return;
    final anyUnstarred = keys.any((k) => !k.favorite);
    final anyLocal = keys.any(
      (k) => k.inLocal && (k.localPath?.isNotEmpty ?? false),
    );

    final actions = <ActionItem>[
      ActionItem(
        icon: anyUnstarred ? Icons.star_rounded : Icons.star_outline_rounded,
        label: anyUnstarred
            ? context.l10n.archiveStar
            : context.l10n.archiveUnstar,
        onTap: () => _bulkSetFavorite(anyUnstarred),
      ),
      if (anyLocal)
        ActionItem(
          icon: Icons.download_outlined,
          label: context.l10n.fmDownload,
          onTap: () => _bulkDownload(context),
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
      leading: QIconBadge(asset: _cat.asset, color: _cat.color, iconSize: 22),
      title: context.l10n.archiveFilesSelected(keys.length),
      subtitle: _cat.remoteDir,
      actions: actions,
    );
  }

  Future<void> _bulkDownload(BuildContext context) async {
    final keys = _selectedKeys
        .where((k) => k.inLocal && (k.localPath?.isNotEmpty ?? false))
        .toList();
    if (keys.isEmpty) {
      context.showNotification(
        context.l10n.archiveNoLocalFiles,
        type: QNotificationType.warning,
      );
      return;
    }

    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: context.l10n.archiveSaveFiles(keys.length),
    );
    if (dir == null) return;

    final sep = io.Platform.pathSeparator;
    var saved = 0;
    for (final k in keys) {
      try {
        final bytes = await io.File(k.localPath!).readAsBytes();
        await io.File('$dir$sep${k.fileName}').writeAsBytes(bytes, flush: true);
        saved++;
      } catch (e) {
        LogService.log('[Archive] bulk download ${k.fileName} failed: $e');
      }
    }
    _exitSelection();
    if (!context.mounted) return;
    context.showNotification(
      saved == keys.length
          ? context.l10n.archiveSavedFiles(saved)
          : context.l10n.archiveSavedPartial(saved, keys.length),
      type: saved == keys.length
          ? QNotificationType.good
          : QNotificationType.warning,
    );
  }

  String _keyId(ArchiveKey k) =>
      '${k.flipperDir}/${k.subFolder.isEmpty ? '' : '${k.subFolder}/'}${k.name}.${k.extension}';
}
