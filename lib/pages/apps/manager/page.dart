import '../../../services/localization/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'widgets/app_action.dart';
import 'widgets/apps_table.dart';
import '../../../components/dialogs/confirm.dart';
import '../../../components/filelist/columns.dart';
import '../../../components/filelist/empty_view.dart';
import '../../../components/filelist/toolbar.dart';
import '../../../components/notification.dart';
import '../../../theme/theme.dart';
import '../actions.dart';
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
  final AppsSortState _sort = AppsSortState();

  String _query = '';
  String? _folderFilter;

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

  bool get _filtering => _query.isNotEmpty || _folderFilter != null;

  List<InstalledApp> _visible(List<InstalledApp> all) {
    final query = _query.toLowerCase();
    final out = [
      for (final app in all)
        if (_folderFilter == null || app.folder == _folderFilter)
          if (query.isEmpty ||
              app.name.toLowerCase().contains(query) ||
              app.alias.toLowerCase().contains(query) ||
              app.folder.toLowerCase().contains(query))
            app,
    ];
    final updatable = _updates.updatableAliases;
    out.sort((a, b) {
      final au = updatable.contains(a.alias);
      final bu = updatable.contains(b.alias);
      if (au != bu) return au ? -1 : 1;
      return _sort.compare(_facts(a), _facts(b));
    });
    return out;
  }

  AppsRowFacts _facts(InstalledApp app) => (
    name: app.name,
    folder: app.folder,
    size: app.size,
    version: app.fap?.manifest?.version ?? '',
  );

  void _onSort(String key) => setState(() => _sort.select(key));

  Future<void> _launch(InstalledApp app) =>
      launchApp(context, () => _device.launch(app));

  Future<bool> _confirm(String title, String body) {
    return QConfirmDialog.show(context, title: title, message: body);
  }

  Future<void> _deleteLocal(InstalledApp app) async {
    if (await _confirm(
      context.l10n.appDeleteLocalTitle,
      context.l10n.appDeleteLocalMessage(app.name),
    )) {
      await _device.deleteLocal(app);
    }
  }

  Future<void> _uninstall(InstalledApp app) async {
    if (await _confirm(
      context.l10n.appUninstallTitle,
      context.l10n.appUninstallMessage(app.name),
    )) {
      await _device.uninstallFromDevice(app);
    }
  }

  Future<void> _restore(InstalledApp app) async {
    final ok = await _device.restore(app);
    if (!mounted) return;
    context.showNotification(
      ok ? context.l10n.appRestoring(app.name) : context.l10n.appNoBackup,
      type: ok ? QNotificationType.good : QNotificationType.warning,
    );
  }

  void _showActions(InstalledApp app) {
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
            label: ctx.l10n.commonCancel,
            icon: Icons.close,
            color: colors.danger,
            filled: true,
            onTap: () => _engine.cancel(app.alias),
          )
        else if (updatable)
          AppActionEntry(
            label: ctx.l10n.commonUpdate,
            icon: Icons.system_update_alt,
            color: colors.success,
            filled: true,
            onTap: () => unawaited(_update(app)),
          ),
        AppActionEntry(
          label: ctx.l10n.commonOpen,
          icon: Icons.play_arrow_rounded,
          color: colors.accent,
          filled: !updatable,
          half: true,
          onTap: () => unawaited(_launch(app)),
        ),
        AppActionEntry(
          label: ctx.l10n.appActionRestore,
          icon: Icons.restore,
          color: colors.accent,
          half: true,
          onTap: () => unawaited(_restore(app)),
        ),
        AppActionEntry(
          label: ctx.l10n.appActionDeleteCopy,
          icon: Icons.sd_card_outlined,
          color: colors.danger,
          half: true,
          onTap: () => unawaited(_deleteLocal(app)),
        ),
        AppActionEntry(
          label: ctx.l10n.appActionUninstall,
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
        final folders = <String>{for (final app in all) app.folder}.toList()
          ..sort();
        if (_folderFilter != null && !folders.contains(_folderFilter)) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => setState(() => _folderFilter = null),
          );
        }
        final visible = _visible(all);

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
                const Icon(Icons.manage_search, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  context.l10n.managerTitle,
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
                  tooltip: context.l10n.managerUpdateAll,
                  onPressed: _updateAll,
                ),
              IconButton(
                icon: const Icon(Icons.extension, color: Colors.white),
                tooltip: context.l10n.managerPluginsTooltip,
                onPressed: widget.onOpenPlugins,
              ),
              IconButton(
                icon: const Icon(
                  Icons.storefront_outlined,
                  color: Colors.white,
                ),
                tooltip: context.l10n.atpCatalogTooltip,
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
                catColor: header,
                colors: colors,
                showStar: false,
                onQueryChanged: (v) => setState(() => _query = v),
                onFilterChanged: (v) => setState(() => _folderFilter = v),
              ),
            ),
          ),
          body: _buildBody(context, all, visible, header),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<InstalledApp> all,
    List<InstalledApp> visible,
    Color header,
  ) {
    final colors = context.appColors;
    if (!_backend.isReady && all.isEmpty) {
      return ArchiveEmptyView(
        icon: Icons.usb_off,
        title: context.l10n.managerConnectDevice,
        subtitle: context.l10n.managerConnectHint,
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
        Expanded(child: _buildList(context, visible, header)),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    List<InstalledApp> visible,
    Color header,
  ) {
    if (visible.isEmpty) return _buildEmpty(context, header);

    final updatable = _updates.updatableAliases;
    return AppsTable<InstalledApp>(
      items: visible,
      sort: _sort,
      onSort: _onSort,
      header: header,
      onRefresh: () async => unawaited(_device.prime()),
      rowBuilder: (app, cols) => _AppRow(
        key: ValueKey(app.path),
        app: app,
        cols: cols,
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
        onTap: () => _showActions(app),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, Color header) {
    if (_device.scanning) return const SizedBox.shrink();
    return RefreshIndicator(
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
              title: _filtering
                  ? context.l10n.appsNothingMatches
                  : context.l10n.managerNoApps,
              subtitle: _filtering ? null : context.l10n.managerSyncHint,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    super.key,
    required this.app,
    required this.cols,
    required this.header,
    required this.updatable,
    required this.compat,
    required this.action,
    required this.onTap,
  });

  final InstalledApp app;
  final List<SizedColumn> cols;
  final Color header;
  final bool updatable;
  final FapCompat? compat;
  final AppAction? action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppsTableRow(
      cols: cols,
      header: header,
      progress: action?.progress,
      onTap: onTap,
      cell: _cell,
    );
  }

  Widget _cell(BuildContext context, ArchiveCol col) {
    final colors = context.appColors;
    switch (col.sortKey) {
      case 'size':
        return AppsSizeCell(bytes: app.size);
      case 'folder':
        return AppsFolderCell(folder: app.folder);
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
        return AppsNameCell(
          header: header,
          icon: (foreground) => AppIcon(
            alias: app.alias,
            size: 16,
            color: foreground,
            manifest: app.manifest,
          ),
          title: app.name,
          subtitle: app.hasManifest
              ? app.folder
              : context.l10n.appSideloaded(app.folder),
        );
    }
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
    final scanned = folder;
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
                  scanned == null
                      ? context.l10n.managerScanning
                      : context.l10n.managerScanningFolder(scanned),
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
