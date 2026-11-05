import '../../../../services/archive/sort_settings.dart';
import '../../../../services/guarded.dart';
import '../../../../services/localization/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../components/folder_pick.dart';
import '../../../../components/icon.dart';
import '../../../../components/selection.dart';
import '../../../../theme/theme.dart';
import '../../../../components/notification.dart';
import '../../../../components/dialogs/connection.dart';
import '../controller.dart';
import '../rename_key.dart';
import '../../../../components/archive/category.dart';
import '../../../../components/archive/models/key.dart';
import '../../widgets/actions_sheet.dart';
import '../../../../components/filelist/empty_view.dart';
import '../widgets/key_actions_sheet.dart';
import '../../../../components/filelist/sync_progress_bar.dart';
import '../../../../components/filelist/columns.dart';
import 'sort.dart';
import '../../../../components/filelist/key_table.dart';
import '../../../../components/filelist/list_scaffold.dart';
import '../../../../components/filelist/table.dart';
import '../../../../components/filelist/toolbar.dart';
import '../failure_toast.dart';
import 'bulk_save.dart';
import '../../widgets/drag_source.dart';

class CategoryPage extends StatefulWidget {
  const CategoryPage({
    super.key,
    required this.controller,
    required this.sortSettings,
    required this.category,
  });

  final ArchiveController controller;

  /// Shared with every other archive table and owned by `AppShell`, so a sort
  /// picked here is the one they all open in - and the rail's other mounted
  /// tables follow it without being rebuilt by hand.
  final ArchiveSortSettings sortSettings;

  final ArchiveCategory category;

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage>
    with ListSelection<CategoryPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  String _query = '';
  String? _filterVal;
  bool _starredOnly = false;

  ArchiveController get _ctrl => widget.controller;
  ArchiveCategory get _cat => widget.category;

  /// Rebuilds on either the archive's own changes or a sort picked on another
  /// mounted table. Built once rather than per build, so the `AnimatedBuilder`
  /// is not resubscribing to a fresh `Listenable` every frame.
  late final Listenable _repaint = Listenable.merge([
    _ctrl,
    widget.sortSettings,
  ]);

  List<SortOption> get _sortOpts => sortOptionsFor(columnsFor(_cat));

  /// The stored sort, held to the keys this category's columns offer.
  ({String key, bool asc}) get _sort =>
      widget.sortSettings.resolve(_sortOpts.map((o) => o.key));

  @override
  void initState() {
    super.initState();
    unawaited(
      guarded(
        '[Archive] load category meta',
        () => _ctrl.loadMetaForCategory(_cat),
      ),
    );
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
    final sort = _sort;
    return sortArchiveKeys(keys, sort.key, sort.asc);
  }

  List<ArchiveKey> get _selectedKeys =>
      _allKeys.where((k) => isSelected(k.id)).toList();

  Future<void> _bulkSetFavorite(bool favorite) async {
    await _ctrl.setKeysFavorite(_selectedKeys, favorite);
    exitSelection();
  }

  void _onSort(String key) {
    unawaited(
      guarded(
        '[ArchiveSort] storing the picked sort',
        () =>
            widget.sortSettings.pick(key, offered: _sortOpts.map((o) => o.key)),
      ),
    );
  }

  Future<void> _showKeyActions(BuildContext context, ArchiveKey key) {
    return KeyActionsSheet.show(
      context,
      _ctrl,
      key,
      onRename: () => _showRenameDialog(context, key),
      onDuplicate: () async {
        await _ctrl.duplicateKey(key);
        if (!context.mounted) return;
        reportArchiveFailure(
          context,
          _ctrl.lastFailure,
          context.l10n.archiveDuplicateFailed,
        );
      },
      onToggleFavorite: () => _ctrl.toggleFavorite(key),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, ArchiveKey key) =>
      promptRenameKey(context, controller: _ctrl, key: key);

  bool get _hasFilter =>
      _starredOnly || _filterVal != null || _query.isNotEmpty;

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

  IconData _emptyIcon() {
    if (_hasFilter) return Icons.search_off;
    if (!_ctrl.isConnected) return Icons.link_off;
    return Icons.folder_open;
  }

  String _emptyActionLabel() {
    if (_hasFilter) return context.l10n.commonClear;
    if (!_ctrl.isConnected) return context.l10n.commonConnect;
    return context.l10n.commonSync;
  }

  void _onEmptyAction() {
    if (_hasFilter) {
      _clearFilters();
      return;
    }
    if (!_ctrl.isConnected) {
      unawaited(
        guarded(
          '[Archive] open the picker',
          () => promptConnectDevice(context),
        ),
      );
      return;
    }
    unawaited(
      guarded('[Archive] sync category', () => _ctrl.syncCategory(_cat)),
    );
  }

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _filterVal = null;
      _starredOnly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final catColor = colors.adaptCategoryHeader(_cat.color);

    return AnimatedBuilder(
      animation: _repaint,
      builder: (context, _) {
        final filtered = _filtered;
        final total = _allKeys.length;
        final filterOpts = _filterOptions;
        if (_filterVal != null && !filterOpts.contains(_filterVal)) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => setState(() => _filterVal = null),
          );
        }

        // One record for the toolbar and the table both: two would be two
        // chances to disagree about what a second tap on a column means. The
        // getter behind it resolves the sort against this page's own columns,
        // which allocates both lists, so it is read once here.
        final resolved = _sort;
        final sort = (
          key: resolved.key,
          asc: resolved.asc,
          opts: _sortOpts,
          onSort: _onSort,
        );

        return ArchiveListScaffold(
          headerColor: catColor,
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
          selection: selectionControl(
            filtered.map((k) => k.id),
            onActions: () => _showBulkActions(context),
          ),
          toolbar: CategoryToolbar(
            searchCtrl: _searchCtrl,
            query: _query,
            filterVal: _filterVal,
            filterOpts: filterOpts,
            sort: sort,
            starredOnly: _starredOnly,
            catColor: catColor,
            colors: colors,
            onQueryChanged: (v) => setState(() => _query = v),
            onFilterChanged: (v) => setState(() => _filterVal = v),
            onStarredToggle: () => setState(() => _starredOnly = !_starredOnly),
          ),
          topBar: _ctrl.syncing ? _syncBar(catColor) : null,
          body: ArchiveKeyTable(
            columns: (width) => visibleColumns(_cat, width, filtered),
            sort: sort,
            selectionMode: selectionMode,
            accent: catColor,
            onRefresh: () => guarded(
              '[Archive] pull to sync',
              () => _ctrl.syncCategory(_cat),
            ),
            empty: () => ArchiveEmptyView(
              icon: _emptyIcon(),
              title: _emptyTitle(),
              subtitle: _ctrl.lastError,
              actionLabel: _emptyActionLabel(),
              onAction: _onEmptyAction,
            ),
            itemCount: filtered.length,
            itemBuilder: (i, cols) => _keyRow(filtered[i], cols, colors),
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

  /// One row. Built against the page's `context`, never a row's: the actions
  /// sheet keeps the context it is given across its awaits and tests `mounted`
  /// on it, and a row that leaves the list - which a failed delete or a rename
  /// does - would take the failure report with it. #110.
  Widget _keyRow(ArchiveKey key, List<SizedColumn> cols, QAppColors colors) {
    final id = key.id;
    final selected = isSelected(id);
    return ArchiveKeyDragSource(
      key: ValueKey(id),
      archiveKey: key,
      selected: selected,
      selection: () => _selectedKeys,
      onDropped: exitSelection,
      child: ArchiveTableRow(
        flipperKey: key,
        cols: cols,
        colors: colors,
        cat: _cat,
        progress: _ctrl.progressForKey(key),
        selectionMode: selectionMode,
        selected: selected,
        onTap: () =>
            selectionMode ? toggleSelect(id) : _showKeyActions(context, key),
        onLongPress: () =>
            selectionMode ? toggleSelect(id) : enterSelection(id),
      ),
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
        onDone: exitSelection,
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

    // Read before the pick, not inside it: a plural selector that threw would
    // otherwise be reported as the system picker failing, at a level that
    // never alerts.
    final title = context.l10n.archiveSaveFiles(keys.length);
    // [pickFolder] catches for itself, which is what this site needs rather
    // than a `try` of its own: it is reached from a bulk-actions sheet entry
    // whose `onTap` is a `VoidCallback`, so a rejection here has no listener
    // at all and lands in the zone as a fatal uncaught error - the mechanism
    // of QUNLEASHED-K, which killed the app from the file browser's *file*
    // pick. A refused pick on Android and iOS used to answer a bare null that
    // read as a cancellation; #353.
    final dir = await pickFolder(
      context,
      what: '[Archive] the folder pick',
      dialogTitle: title,
    );
    if (dir == null) return;

    final saved = await saveKeysInto(keys, dir);
    // Below the guard, not above it. `ListSelection.exitSelection` is safe
    // either way, but reading it above a `mounted` check invites someone to
    // add a second guard here instead of trusting the one in the mixin.
    if (!context.mounted) return;
    exitSelection();
    context.showNotification(
      saved == keys.length
          ? context.l10n.archiveSavedFiles(saved)
          : context.l10n.archiveSavedPartial(saved, keys.length),
      type: saved == keys.length
          ? QNotificationType.good
          : QNotificationType.warning,
    );
  }
}
