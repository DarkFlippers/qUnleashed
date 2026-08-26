import 'dart:async';

import 'package:flutter/material.dart';

import 'widgets/app_action.dart';
import '../../../components/dialogs/confirm.dart';
import '../../../components/format.dart';
import '../../../components/icon.dart';
import '../../../components/navigation.dart';
import '../../../theme/theme.dart';
import '../../../components/notification.dart';
import '../../../components/filelist/columns.dart';
import '../../../components/filelist/table.dart';
import '../../../components/filelist/toolbar.dart';
import '../../../components/filelist/empty_view.dart';
import '../../../components/filelist/progress_fill.dart';
import '../data/apps_backend.dart';
import '../data/device_source.dart';
import '../data/install_engine.dart';
import '../../../components/codec/fap/details.dart';
import '../../../components/fap_facts.dart';
import '../data/models/installed_app.dart';
import '../data/update_registry.dart';
import '../icons/app_icon.dart';

class AppsManagerPage extends StatefulWidget {
  const AppsManagerPage({super.key, this.onOpenCatalog, this.onOpenPlugins});

  final VoidCallback? onOpenCatalog;
  final VoidCallback? onOpenPlugins;

  @override
  State<AppsManagerPage> createState() => _AppsManagerPageState();
}

class _AppsManagerPageState extends State<AppsManagerPage> {
  final AppsBackend _backend = AppsBackend.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  String _query = '';
  String? _folderFilter;
  String _sortKey = 'name';
  bool _sortAsc = true;

  final Map<String, String> _categoryNames = {};

  DeviceSource get _device => _backend.device;
  InstallEngine get _engine => _backend.engine;
  UpdateRegistry get _updates => _backend.updates;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_primeAll());
    });
  }

  Future<void> _primeAll() async {
    unawaited(_backend.ensureIndex());
    await _device.prime();
    await _updates.ensureFresh();
    await _loadCategoryNames();
  }

  Future<void> _loadCategoryNames() async {
    if (_categoryNames.isNotEmpty) return;
    try {
      final cats = await _backend.api.fetchCategories();
      if (!mounted) return;
      setState(() {
        for (final c in cats) {
          if (c.id.isNotEmpty) _categoryNames[c.id] = c.name;
        }
      });
    } catch (_) {}
  }

  Future<void> _update(InstalledApp app) async {
    final card = _updates.cardForUid(app.uid);
    if (card == null) return;
    await _engine.installOrUpdate(card);
  }

  void _updateAll() {
    if (_updates.count == 0) return;
    _updates.updateAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<InstalledApp> _visible() {
    var out = _device.apps;
    if (_folderFilter != null) {
      out = out.where((a) => a.folder == _folderFilter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      out = out
          .where(
            (a) =>
                a.name.toLowerCase().contains(q) ||
                a.alias.toLowerCase().contains(q) ||
                a.folder.toLowerCase().contains(q),
          )
          .toList();
    } else {
      out = out.toList();
    }
    final updatable = _updates.updatableAliases;
    out.sort((a, b) {
      final au = updatable.contains(a.alias);
      final bu = updatable.contains(b.alias);
      if (au != bu) return au ? -1 : 1;
      final int cmp;
      switch (_sortKey) {
        case 'folder':
          final f = a.folder.toLowerCase().compareTo(b.folder.toLowerCase());
          cmp = f != 0
              ? f
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'size':
          cmp = a.size.compareTo(b.size);
        case 'version':
          cmp = (a.fap?.manifest?.version ?? '').compareTo(
            b.fap?.manifest?.version ?? '',
          );
        default:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
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

  void _onLaunched() {
    openRoute(context, AppRoute.remoteControl);
  }

  Future<void> _launch(InstalledApp app) async {
    try {
      await _device.launch(app);
      _onLaunched();
    } catch (e) {
      if (mounted) {
        context.showNotification(
          'Open failed: $e',
          type: QNotificationType.error,
        );
      }
    }
  }

  Future<bool> _confirm(String title, String body) {
    return QConfirmDialog.show(context, title: title, message: body);
  }

  Future<void> _deleteLocal(InstalledApp app) async {
    if (await _confirm(
      'Delete local copy?',
      'Remove the downloaded "${app.name}.fap" from this computer? The app stays on the Flipper.',
    )) {
      await _device.deleteLocal(app);
    }
  }

  Future<void> _uninstall(InstalledApp app) async {
    if (await _confirm(
      'Uninstall from device?',
      'Delete "${app.name}" from the Flipper (the local backup is removed too).',
    )) {
      await _device.uninstallFromDevice(app);
    }
  }

  Future<void> _restore(InstalledApp app) async {
    final ok = await _device.restore(app);
    if (!mounted) return;
    context.showNotification(
      ok ? 'Restoring "${app.name}" to the Flipper' : 'No local backup found',
      type: ok ? QNotificationType.good : QNotificationType.warning,
    );
  }

  void _showActions(InstalledApp app, Color header) {
    final colors = context.appColors;
    final card = _updates.cardForUid(app.uid);
    final updatable = _updates.updatableAliases.contains(app.alias);
    final busy = _engine.actions.containsKey(app.alias);
    AppActionSheet.show(
      context,
      icon: AppIcon(
        alias: app.alias,
        size: 26,
        color: colors.accent,
        manifest: app.manifest,
      ),
      title: app.name,
      subtitle: app.path.isNotEmpty ? app.path : '/ext/apps/${app.folder}',
      details: FapFactsPanel(
        info: app.fap,
        checked: app.fapChecked,
        author: card?.author ?? '',
        deviceApi: _backend.deviceApi,
        deviceTarget: _backend.deviceTarget,
      ),
      actions: (ctx) => [
        if (busy)
          AppActionEntry(
            label: 'Cancel',
            icon: Icons.close,
            color: colors.danger,
            filled: true,
            onTap: () => _engine.cancel(app.alias),
          )
        else if (updatable)
          AppActionEntry(
            label: 'Update',
            icon: Icons.system_update_alt,
            color: colors.success,
            filled: true,
            onTap: () => unawaited(_update(app)),
          ),
        AppActionEntry(
          label: 'Open',
          icon: Icons.play_arrow_rounded,
          color: colors.accent,
          filled: !updatable,
          half: true,
          onTap: () => unawaited(_launch(app)),
        ),
        AppActionEntry(
          label: 'Restore',
          icon: Icons.restore,
          color: colors.accent,
          half: true,
          onTap: () => unawaited(_restore(app)),
        ),
        AppActionEntry(
          label: 'Delete copy',
          icon: Icons.sd_card_outlined,
          color: colors.danger,
          half: true,
          onTap: () => unawaited(_deleteLocal(app)),
        ),
        AppActionEntry(
          label: 'Uninstall',
          icon: Icons.delete_outline,
          color: colors.danger,
          filled: true,
          half: true,
          onTap: () => unawaited(_uninstall(app)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final header = colors.accent;

    return AnimatedBuilder(
      animation: Listenable.merge([_device, _engine, _updates]),
      builder: (context, _) {
        final all = _device.apps;
        final folders = _device.groups;
        if (_folderFilter != null && !folders.contains(_folderFilter)) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => setState(() => _folderFilter = null),
          );
        }
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
            title: const Row(
              children: [
                Icon(Icons.manage_search, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'Apps manager',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            actions: [
              if (_updates.count > 0)
                IconButton(
                  icon: Badge(
                    label: Text('${_updates.count}'),
                    child: const Icon(Icons.update, color: Colors.white),
                  ),
                  tooltip: 'Update all',
                  onPressed: _updateAll,
                ),
              IconButton(
                icon: const Icon(Icons.extension, color: Colors.white),
                tooltip: 'All-the-plugins',
                onPressed: widget.onOpenPlugins,
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
                syncing: _device.scanning,
                enabled: _backend.isReady,
                catColor: header,
                onTap: _device.scan,
              ),
              CategoryCountBadge(filtered: visible.length, total: all.length),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: CategoryToolbar(
                searchCtrl: _searchCtrl,
                query: _query,
                filterVal: _folderFilter,
                filterOpts: folders,
                starredOnly: false,
                catColor: header,
                colors: colors,
                showStar: false,
                onQueryChanged: (v) => setState(() => _query = v),
                onFilterChanged: (v) => setState(() => _folderFilter = v),
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
    List<InstalledApp> visible,
    Color header,
  ) {
    final colors = context.appColors;
    if (!_backend.isReady && _device.apps.isEmpty) {
      return const ArchiveEmptyView(
        icon: Icons.usb_off,
        title: 'Connect a device',
        subtitle: 'Apps installed on the Flipper show up here',
      );
    }

    return Column(
      children: [
        if (_device.scanning)
          _ScanProgress(
            folder: _device.scanningFolder,
            progress: _device.scanProgress,
            fileProgress: _device.fileProgress,
            color: header,
            colors: colors,
          ),
        Expanded(
          child: visible.isEmpty
              ? (_device.scanning
                    ? const SizedBox.shrink()
                    : RefreshIndicator(
                        color: header,
                        displacement: 15,
                        onRefresh: () async => unawaited(_device.prime()),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: ArchiveEmptyView(
                                icon: Icons.apps,
                                title:
                                    _query.isNotEmpty || _folderFilter != null
                                    ? 'Nothing matches'
                                    : 'No apps yet',
                                subtitle:
                                    _query.isNotEmpty || _folderFilter != null
                                    ? null
                                    : 'Tap sync to load apps from the Flipper',
                              ),
                            ),
                          ],
                        ),
                      ))
              : LayoutBuilder(
                  builder: (ctx, constraints) {
                    final cols = _columns(constraints.maxWidth);
                    final updatable = _updates.updatableAliases;
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
                            displacement: 15,
                            onRefresh: () async => unawaited(_device.prime()),
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: ClampingScrollPhysics(),
                              ),
                              itemCount: visible.length,
                              itemBuilder: (_, i) {
                                final app = visible[i];
                                return _AppRow(
                                  key: ValueKey(app.path),
                                  app: app,
                                  cols: cols,
                                  colors: colors,
                                  header: header,
                                  updatable: updatable.contains(app.alias),
                                  compat: app.fapChecked
                                      ? evaluateFap(
                                          app.fap,
                                          deviceApi: _backend.deviceApi,
                                          deviceTarget: _backend.deviceTarget,
                                        )
                                      : null,
                                  action: _engine.actions[app.alias],
                                  onTap: () => _showActions(app, header),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<SizedColumn> _columns(double avail) {
    const sizeW = 64.0;
    const versionW = 74.0;
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
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    super.key,
    required this.app,
    required this.cols,
    required this.colors,
    required this.header,
    required this.updatable,
    required this.compat,
    required this.action,
    required this.onTap,
  });

  final InstalledApp app;
  final List<SizedColumn> cols;
  final QAppColors colors;
  final Color header;
  final bool updatable;
  final FapCompat? compat;
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
                        child: _cell(e.col),
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

  Widget _cell(ArchiveCol col) {
    switch (col.sortKey) {
      case 'size':
        return Align(
          alignment: Alignment.centerRight,
          child: Text(
            app.size > 0 ? _fmtSize(app.size) : '—',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        );
      case 'folder':
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(
            app.folder,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        );
      case 'version':
        final manifest = app.fap?.manifest;
        final blocking = compat?.isBlocking ?? false;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              manifest?.version ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: updatable ? colors.success : colors.textSecondary,
                fontSize: 12,
                fontWeight: updatable ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            if (manifest != null)
              Text(
                manifest.api,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: blocking ? colors.danger : colors.textMuted,
                  fontSize: 10,
                ),
              ),
          ],
        );
      default:
        return Row(
          children: [
            _Badge(app: app, color: header, size: 28, iconSize: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    app.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    app.hasManifest ? app.folder : '${app.folder} · sideloaded',
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

  String _fmtSize(int bytes) => formatBytesScaled(bytes, maxUnit: 2);
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.app,
    required this.color,
    required this.size,
    required this.iconSize,
  });

  final InstalledApp app;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final style = QIconBadgeStyle.of(context, color, darkOpacity: 0.14);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: AppIcon(
        alias: app.alias,
        size: iconSize,
        color: style.foreground,
        manifest: app.manifest,
      ),
    );
  }
}

class _ScanProgress extends StatelessWidget {
  const _ScanProgress({
    required this.folder,
    required this.progress,
    required this.fileProgress,
    required this.color,
    required this.colors,
  });

  final String? folder;
  final double progress;
  final double? fileProgress;
  final Color color;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LinearProgressIndicator(
          value: progress > 0 ? progress : null,
          minHeight: 3,
          color: color,
          backgroundColor: color.withValues(alpha: 0.15),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 14, color: colors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  folder == null ? 'Scanning device…' : 'Scanning $folder…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                ),
              ),
              if (progress > 0 || fileProgress != null)
                Text(
                  fileProgress == null
                      ? '${(progress * 100).round()}%'
                      : '${(progress * 100).round()}% / '
                            '${(fileProgress! * 100).round()}%',
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
