import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../../../widgets/notification.dart';
import '../../archive/overview/category/columns.dart';
import '../../archive/overview/category/table.dart';
import '../../archive/overview/category/toolbar.dart';
import '../../archive/overview/widgets/empty_view.dart';
import '../../archive/overview/widgets/progress_fill.dart';
import '../../tools/remote/desktop/page.dart';
import '../data/apps_backend.dart';
import '../data/device_source.dart';
import '../data/install_engine.dart';
import '../data/models/installed_app.dart';
import '../data/update_registry.dart';
import '../icons/app_icon.dart';
import 'app_action_sheet.dart';

class AppsManagerPage extends StatefulWidget {
  const AppsManagerPage({super.key, this.onOpenCatalog});

  final VoidCallback? onOpenCatalog;

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
          .where((a) =>
              a.name.toLowerCase().contains(q) ||
              a.alias.toLowerCase().contains(q) ||
              a.folder.toLowerCase().contains(q))
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
          cmp = f != 0 ? f : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'size':
          cmp = a.size.compareTo(b.size);
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RemoteControlPage()),
    );
  }

  Future<void> _launch(InstalledApp app) async {
    try {
      await _device.launch(app);
      _onLaunched();
    } catch (e) {
      if (mounted) {
        context.showNotification('Open failed: $e',
            type: QNotificationType.error);
      }
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = ctx.appColors;
        return AlertDialog(
          backgroundColor: colors.dialogBackground,
          title: Text(title, style: TextStyle(color: colors.dialogText)),
          content: Text(body, style: TextStyle(color: colors.dialogText)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: colors.dialogMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('OK', style: TextStyle(color: colors.danger)),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  Future<void> _deleteLocal(InstalledApp app) async {
    if (await _confirm('Delete local copy?',
        'Remove the downloaded "${app.name}.fap" from this computer? The app stays on the Flipper.')) {
      await _device.deleteLocal(app);
    }
  }

  Future<void> _uninstall(InstalledApp app) async {
    if (await _confirm('Uninstall from device?',
        'Delete "${app.name}" from the Flipper (the local backup is removed too).')) {
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
    AppActionSheet.show(
      context,
      app: app,
      initialCard: _updates.cardForUid(app.uid),
      fetchCard: () => _backend.api.fetchAppCard(app.alias),
      categoryNameFor: (id) => _categoryNames[id],
      isUpdatable: _updates.updatableAliases.contains(app.alias),
      onUpdate: () => _update(app),
      onOpen: () => _launch(app),
      onRestore: () => _restore(app),
      onDeleteCopy: () => _deleteLocal(app),
      onUninstall: () => _uninstall(app),
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
                Text('Apps manager',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600)),
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
                icon: const Icon(Icons.storefront_outlined, color: Colors.white),
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
    if (!_backend.isReady) {
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
            color: header,
            colors: colors,
          ),
        Expanded(
          child: visible.isEmpty
              ? (_device.scanning
                  ? const SizedBox.shrink()
                  : RefreshIndicator(
                      color: header,
                      onRefresh: _device.prime,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: ArchiveEmptyView(
                              icon: Icons.apps,
                              title: _query.isNotEmpty || _folderFilter != null
                                  ? 'Nothing matches'
                                  : 'No apps yet',
                              subtitle: _query.isNotEmpty || _folderFilter != null
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
                            onRefresh: _device.prime,
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
    const folderW = 118.0;
    final showFolder = avail > 420;
    final fixed = sizeW + (showFolder ? folderW : 0);
    final nameW =
        (avail - fixed - 24).clamp(kNameMinWidth, double.infinity).toDouble();
    return [
      (col: const ArchiveCol('Name / Folder', 0, sortKey: 'name'), width: nameW),
      if (showFolder)
        (col: const ArchiveCol('Folder', folderW, sortKey: 'folder'),
            width: folderW),
      (
        col: const ArchiveCol('Size', sizeW, sortKey: 'size', right: true),
        width: sizeW
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
    required this.action,
    required this.onTap,
  });

  final InstalledApp app;
  final List<SizedColumn> cols;
  final QAppColors colors;
  final Color header;
  final bool updatable;
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
                  bottom: BorderSide(color: colors.divider.withValues(alpha: 0.6)),
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
            if (updatable) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.success.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'UPDATE',
                  style: TextStyle(
                    color: colors.success,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ],
        );
    }
  }

  String _fmtSize(int bytes) {
    const units = ['B', 'KB', 'MB'];
    var b = bytes.toDouble();
    var i = 0;
    while (b >= 1024 && i < units.length - 1) {
      b /= 1024;
      i++;
    }
    return '${b.toStringAsFixed(b >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
  }
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
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
      ),
      child: AppIcon(
        alias: app.alias,
        size: iconSize,
        color: color,
        manifest: app.manifest,
      ),
    );
  }
}

class _ScanProgress extends StatelessWidget {
  const _ScanProgress({
    required this.folder,
    required this.progress,
    required this.color,
    required this.colors,
  });

  final String? folder;
  final double progress;
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
              if (progress > 0)
                Text('${(progress * 100).round()}%',
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

