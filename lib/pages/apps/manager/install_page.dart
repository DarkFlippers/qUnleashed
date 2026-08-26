import 'dart:async';

import 'package:flutter/material.dart';

import '../../../components/codec/fap/api_version.dart';
import '../../../components/codec/fap/icon.dart';
import '../../../components/filelist/columns.dart';
import '../../../components/filelist/empty_view.dart';
import '../../../components/filelist/progress_fill.dart';
import '../../../components/filelist/table.dart';
import '../../../components/filelist/toolbar.dart';
import '../../../components/codec/fap/info.dart';
import '../../../components/fap_facts.dart';
import '../../../components/format.dart';
import '../../../components/icon.dart';
import '../../../components/navigation.dart';
import '../../../components/notification.dart';
import '../../../theme/theme.dart';
import '../data/apps_backend.dart';
import '../data/atp/atp_index.dart';
import '../data/atp/atp_source.dart';
import '../data/catalog_state.dart';
import '../data/install_engine.dart';
import '../data/models/card.dart';
import 'widgets/app_action.dart';

enum PackAction { install, update, downgrade, none }

class AtpInstallPage extends StatefulWidget {
  const AtpInstallPage({super.key, this.onOpenCatalog, this.onOpenManager});

  final VoidCallback? onOpenCatalog;
  final VoidCallback? onOpenManager;

  @override
  State<AtpInstallPage> createState() => _AtpInstallPageState();
}

class _AtpInstallPageState extends State<AtpInstallPage> {
  final AppsBackend _backend = AppsBackend.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  String _query = '';
  String? _categoryFilter;
  String _sortKey = 'name';
  bool _sortAsc = true;

  AtpSource get _atp => _backend.atp;
  InstallEngine get _engine => _backend.engine;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_prime()));
  }

  Future<void> _prime() async {
    await _backend.ensureIndex();
    await _backend.manifests.ensureFresh();
    await _backend.device.prime();
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    await _atp.downloadLatest();
    await _backend.manifests.refresh(force: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// The loader takes an app when the majors match and its minor is no newer
  /// than the firmware's, so only that case is worth saying out loud — once,
  /// for the whole pack.
  bool get _packUnusable {
    final device = parseApi(_backend.deviceApi);
    final pack = parseApi(_atp.block?.api);
    if (device == null || pack == null) return false;
    return pack.$1 != device.$1 || pack.$2 > device.$2;
  }

  List<String> get _folders {
    final names = <String>{
      for (final entry in _atp.entries)
        if (entry.folder.isNotEmpty) entry.folder,
    }.toList()..sort();
    return names;
  }

  List<AtpEntry> _visible() {
    final query = _query.toLowerCase();
    final out = [
      for (final entry in _atp.entries)
        if (_categoryFilter == null || entry.folder == _categoryFilter)
          if (query.isEmpty ||
              entry.displayName.toLowerCase().contains(query) ||
              entry.appId.toLowerCase().contains(query) ||
              entry.folder.toLowerCase().contains(query))
            entry,
    ];
    out.sort((a, b) {
      final int cmp;
      switch (_sortKey) {
        case 'folder':
          final f = a.folder.toLowerCase().compareTo(b.folder.toLowerCase());
          cmp = f != 0
              ? f
              : a.displayName.toLowerCase().compareTo(
                  b.displayName.toLowerCase(),
                );
        case 'size':
          cmp = a.size.compareTo(b.size);
        case 'version':
          cmp = a.version.compareTo(b.version);
        default:
          cmp = a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
      }
      return _sortAsc ? cmp : -cmp;
    });
    return out;
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

  List<SizedColumn> _columns(double avail) {
    const versionW = 70.0;
    const sizeW = 64.0;
    const folderW = 118.0;
    final showFolder = avail > 460;
    final showVersion = avail > 360;
    final fixed =
        sizeW + (showFolder ? folderW : 0) + (showVersion ? versionW : 0);
    final nameW = (avail - fixed - 24)
        .clamp(kNameMinWidth, double.infinity)
        .toDouble();
    return [
      (
        col: const ArchiveCol('Name / Folder', 0, sortKey: 'name'),
        width: nameW,
      ),
      if (showFolder)
        (
          col: const ArchiveCol('Folder', folderW, sortKey: 'folder'),
          width: folderW,
        ),
      if (showVersion)
        (
          col: const ArchiveCol(
            'Version',
            versionW,
            sortKey: 'version',
            right: true,
          ),
          width: versionW,
        ),
      (
        col: const ArchiveCol('Size', sizeW, sortKey: 'size', right: true),
        width: sizeW,
      ),
    ];
  }

  CatalogAppState _stateFor(AppCard card) => catalogAppState(
    card: card,
    manifest: _backend.manifests.byAlias(card.alias),
    targetSdk: _backend.targetSdk,
  );

  /// What installing this entry would do to the app already on the device: the
  /// pack can carry a newer build, the same one, or an older one — the last is
  /// still installable, it just walks the version back.
  PackAction _actionFor(AtpEntry entry) {
    final card = AppCard.fromAtp(entry, api: _atp.block?.api ?? '');
    if (_backend.manifests.byAlias(entry.appId) == null) {
      return PackAction.install;
    }
    final installed = parseApi(
      _backend.device.infoFor(entry.appId)?.manifest?.version,
    );
    final pack = parseApi(entry.version);
    if (installed != null && pack != null) {
      final cmp = compareApi(pack, installed);
      if (cmp > 0) return PackAction.update;
      if (cmp < 0) return PackAction.downgrade;
    }
    return _stateFor(card) == CatalogAppState.update
        ? PackAction.update
        : PackAction.none;
  }

  Future<FapInfo?> _readFap(AtpEntry entry) async {
    try {
      final file = await AtpArchive.instance.fapFile(entry, _atp.tag);
      if (!await file.exists()) return null;
      return FapInfo.parse(await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  Future<void> _showActions(AtpEntry entry) async {
    final colors = context.appColors;
    final card = AppCard.fromAtp(entry, api: _atp.block?.api ?? '');
    final action = _actionFor(entry);
    final busy = _engine.actions.containsKey(entry.appId);
    final fap = await _readFap(entry);
    if (!mounted) return;
    await AppActionSheet.show(
      context,
      icon: _EntryIcon(appId: entry.appId, size: 26, color: colors.accent),
      title: entry.displayName,
      subtitle: entry.installPath,
      details: FapFactsPanel(
        info: fap,
        checked: fap != null,
        showVerdict: false,
        pendingNote: 'Install the app to read its manifest',
      ),
      actions: (ctx) => [
        if (busy)
          AppActionEntry(
            label: 'Cancel',
            icon: Icons.close,
            color: colors.danger,
            filled: true,
            onTap: () => _engine.cancel(entry.appId),
          )
        else if (action == PackAction.install)
          AppActionEntry(
            label: 'Install',
            icon: Icons.download,
            color: colors.accent,
            filled: true,
            onTap: () => _engine.installOrUpdate(card),
          )
        else ...[
          if (action == PackAction.update)
            AppActionEntry(
              label: 'Update',
              icon: Icons.arrow_upward,
              color: colors.success,
              filled: true,
              onTap: () => _engine.installOrUpdate(card),
            )
          else if (action == PackAction.downgrade)
            AppActionEntry(
              label: 'Downgrade',
              icon: Icons.arrow_downward,
              color: colors.danger,
              filled: true,
              onTap: () => _engine.installOrUpdate(card),
            ),
          AppActionEntry(
            label: 'Open',
            icon: Icons.play_arrow_rounded,
            color: colors.accent,
            filled: action == PackAction.none,
            half: true,
            onTap: () => unawaited(_launch(entry)),
          ),
          AppActionEntry(
            label: 'Uninstall',
            icon: Icons.delete_outline,
            color: colors.danger,
            half: true,
            onTap: () => unawaited(
              _engine.deleteInstalled(
                alias: entry.appId,
                fapPath: entry.installPath,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _launch(AtpEntry entry) async {
    final path =
        _backend.manifests.byAlias(entry.appId)?.path ?? entry.installPath;
    try {
      await _engine.launchPath(path);
      if (mounted) openRoute(context, AppRoute.remoteControl);
    } catch (e) {
      if (mounted) {
        context.showNotification(
          'Open failed: $e',
          type: QNotificationType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final header = colors.accent;

    return AnimatedBuilder(
      animation: Listenable.merge([_atp, _engine, _backend.manifests]),
      builder: (context, _) {
        final visible = _visible();
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: header,
            foregroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 16,
            title: Row(
              children: [
                const Icon(Icons.extension, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'All-the-plugins',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _packUnusable
                        ? '${_atp.tag} · API ${_atp.block?.api} '
                              'vs ${_backend.deviceApi}'
                        : _atp.tag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _packUnusable
                          ? colors.danger
                          : Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.manage_search, color: Colors.white),
                tooltip: 'Manage apps on device',
                onPressed: widget.onOpenManager,
              ),
              IconButton(
                icon: const Icon(
                  Icons.storefront_outlined,
                  color: Colors.white,
                ),
                tooltip: 'Catalog',
                onPressed: widget.onOpenCatalog,
              ),
              CategorySyncButton(
                syncing: _atp.loading,
                enabled: !_atp.loading,
                catColor: header,
                onTap: () => unawaited(_refresh()),
              ),
              CategoryCountBadge(
                filtered: visible.length,
                total: _atp.entries.length,
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: CategoryToolbar(
                searchCtrl: _searchCtrl,
                query: _query,
                filterVal: _categoryFilter,
                filterOpts: _folders,
                starredOnly: false,
                catColor: header,
                colors: colors,
                showStar: false,
                onQueryChanged: (v) => setState(() => _query = v),
                onFilterChanged: (v) => setState(() => _categoryFilter = v),
                onStarredToggle: () {},
              ),
            ),
          ),
          body: _buildBody(context, visible, header),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<AtpEntry> visible,
    Color header,
  ) {
    final colors = context.appColors;
    if (_atp.entries.isEmpty) {
      return ArchiveEmptyView(
        icon: Icons.extension_off,
        title: _atp.loading ? 'Loading the index…' : 'No apps in the release',
        subtitle: _atp.loading ? null : 'Sync to fetch the latest pack',
      );
    }
    if (visible.isEmpty) {
      return const ArchiveEmptyView(
        icon: Icons.search_off,
        title: 'Nothing matches',
      );
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cols = _columns(constraints.maxWidth);
        return Column(
          children: [
            ArchiveColumnHeader(
              cols: cols,
              sortKey: _sortKey,
              sortAsc: _sortAsc,
              onSort: _onSort,
              colors: colors,
            ),
            Expanded(
              child: RefreshIndicator(
                color: header,
                onRefresh: _refresh,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final entry = visible[i];
                    return _EntryRow(
                      key: ValueKey(entry.appId),
                      entry: entry,
                      cols: cols,
                      colors: colors,
                      header: header,
                      packAction: _actionFor(entry),
                      action: _engine.actions[entry.appId],
                      onTap: () => unawaited(_showActions(entry)),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EntryIcon extends StatelessWidget {
  const _EntryIcon({
    required this.appId,
    required this.size,
    required this.color,
  });

  final String appId;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bits = AtpSource.instance.iconFor(appId);
    if (bits == null) {
      return Icon(Icons.extension_outlined, size: size, color: color);
    }
    return QIcon.xbm(
      bytes: bits,
      width: fapIconWidth,
      height: fapIconHeight,
      cacheKey: 'atp:$appId',
      color: color,
      size: size,
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.entry,
    required this.cols,
    required this.colors,
    required this.header,
    required this.packAction,
    required this.action,
    required this.onTap,
  });

  final AtpEntry entry;
  final List<SizedColumn> cols;
  final QAppColors colors;
  final Color header;
  final PackAction packAction;
  final AppAction? action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.card,
      child: Stack(
        children: [
          ProgressFill(progress: action?.progress),
          InkWell(
            onTap: onTap,
            splashColor: header.withValues(alpha: 0.06),
            highlightColor: header.withValues(alpha: 0.04),
            child: Container(
              height: kRowHeight,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colors.divider.withValues(alpha: 0.6),
                  ),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  for (final e in cols)
                    SizedBox(
                      width: e.width,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _cell(context, e.col),
                      ),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, ArchiveCol col) {
    switch (col.sortKey) {
      case 'size':
        return Align(
          alignment: Alignment.centerRight,
          child: Text(
            formatBytesScaled(entry.size, maxUnit: 2),
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        );
      case 'version':
        return Align(
          alignment: Alignment.centerRight,
          child: Text(
            entry.version,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: switch (packAction) {
                PackAction.update => colors.success,
                PackAction.downgrade => colors.danger,
                _ => colors.textSecondary,
              },
              fontSize: 12,
              fontWeight:
                  packAction == PackAction.update ||
                      packAction == PackAction.downgrade
                  ? FontWeight.w700
                  : FontWeight.w400,
            ),
          ),
        );
      case 'folder':
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(
            entry.folder,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        );
      default:
        final style = QIconBadgeStyle.of(context, header, darkOpacity: 0.14);
        return Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: BorderRadius.circular(7),
              ),
              child: _EntryIcon(
                appId: entry.appId,
                size: 16,
                color: style.foreground,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    packAction == PackAction.install
                        ? entry.appId
                        : '${entry.appId} · installed',
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
  }
}
