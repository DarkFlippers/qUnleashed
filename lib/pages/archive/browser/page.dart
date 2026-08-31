import '../../../services/localization/l10n.dart';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../components/navigation.dart';
import '../../../theme/theme.dart';
import 'package:qunleashed/components/appbar.dart';
import 'package:flipperlib/flipperlib.dart';
import '../../../services/storage/fap_icons.dart' as icon_repo;
import '../../../components/notification.dart';
import '../../../components/codec/fap/icon.dart';
import '../emulate/page.dart';
import '../../../components/archive/category.dart';
import '../../../components/archive/models/key.dart';
import '../editor/open.dart';
import 'share_remote_file.dart';
import 'controller.dart';
import 'columns.dart';
import 'widgets/file_row.dart';
import 'widgets/file_table.dart';
import '../widgets/actions_sheet.dart';
import '../../../components/filelist/sync_progress_bar.dart';
import '../../../components/filelist/empty_view.dart';
import '../../../components/dialogs/connection.dart';

class _ClipEntry {
  _ClipEntry({
    required this.remotePath,
    required this.name,
    required this.isDir,
  });

  final String remotePath;
  final String name;
  final bool isDir;
}

class _Clipboard {
  _Clipboard({required this.items, required this.isCut});

  final List<_ClipEntry> items;
  final bool isCut;

  String get label =>
      items.length == 1 ? items.first.name : l10n.fmItemCount(items.length);
}

class FileManagerPage extends StatefulWidget {
  const FileManagerPage({super.key, this.initialPath = '/ext'});

  final String initialPath;

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  late final FileManagerController _ctrl;
  _Clipboard? _clipboard;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  /// Name of the entry whose row should open in inline rename mode.
  String? _pendingRenameName;

  @override
  void initState() {
    super.initState();
    _ctrl = FileManagerController(initialPath: widget.initialPath);
    _ctrl.refresh();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onEntryTap(RemoteEntry e) {
    if (_selectionMode) {
      _toggleSelect(e);
      return;
    }
    if (e.isDir) {
      _ctrl.open(_ctrl.childPath(e.name));
      return;
    }
    final ext = e.extension;
    if (const {'bin', 'elf', 'fuf'}.contains(ext)) return;
    if (ext == 'fap') {
      _launchFap(_ctrl.childPath(e.name));
      return;
    }
    if (_isPaintFile(e)) {
      _openPaintEditor(_ctrl.childPath(e.name));
      return;
    }
    _openTextEditor(e);
  }

  Future<void> _navigateTo(String path) async {
    _exitSelection();
    await _ctrl.open(path);
  }

  Future<bool> _handleBack() async {
    if (_selectionMode) {
      _exitSelection();
      return false;
    }
    if (_ctrl.isSearching) {
      _stopSearch();
      return false;
    }
    if (_ctrl.canGoUp) {
      await _ctrl.goUp();
      return false;
    }
    return true;
  }

  void _enterSelection(RemoteEntry e) {
    setState(() {
      _selectionMode = true;
      _selected
        ..clear()
        ..add(e.name);
    });
  }

  void _toggleSelect(RemoteEntry e) {
    setState(() {
      if (!_selected.add(e.name)) _selected.remove(e.name);
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() {
    if (!_selectionMode && _selected.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _selectAll() {
    final all = _ctrl.entries.map((e) => e.name).toSet();
    setState(() {
      if (_selected.length == all.length) {
        _selected.clear();
        _selectionMode = false;
      } else {
        _selected
          ..clear()
          ..addAll(all);
      }
    });
  }

  List<RemoteEntry> get _selectedEntries =>
      _ctrl.entries.where((e) => _selected.contains(e.name)).toList();

  void _stopSearch() {
    _searchCtrl.clear();
    _searchFocus.unfocus();
    setState(() => _ctrl.setSearch(''));
  }

  Future<void> _connect() async {
    await promptConnectDevice(context, _ctrl.client);
    if (!mounted || !_ctrl.client.isConnected) return;
    await _ctrl.refresh();
  }

  Future<void> _launchFap(String remotePath) async {
    bool ok;
    try {
      ok = await _ctrl.launchFap(remotePath);
    } on FlipperRpcAppSystemLockedException {
      if (mounted) _openRemoteControlBusy();
      return;
    } on FlipperRpcBusyException {
      if (mounted) _openRemoteControlBusy();
      return;
    }
    if (!mounted) return;
    if (!ok) {
      context.showNotification(
        context.l10n.fmLaunchFailed,
        type: QNotificationType.error,
      );
      return;
    }
    openRoute(context, AppRoute.remoteControl);
  }

  void _openRemoteControlBusy() {
    context.showNotification(
      context.l10n.fmDeviceBusy,
      type: QNotificationType.error,
    );
    openRoute(context, AppRoute.remoteControl);
  }

  Future<void> _openTextEditor(RemoteEntry e) async {
    final remotePath = _ctrl.childPath(e.name);
    await openRemoteFileInEditor(
      context,
      remotePath: remotePath,
      download: () => _ctrl.downloadTo(remotePath, expectedSize: e.size),
      upload: (bytes) => _ctrl.writeBytes(remotePath, bytes),
      onRun: e.extension == 'js'
          ? () => _emulateEntry(e, ArchiveCategory.javascript)
          : null,
    );
    if (!mounted) return;
    await _ctrl.refresh();
  }

  Future<void> _openPaintEditor(String remotePath) async {
    await openRoute(
      context,
      AppRoute.pixelEditor,
      args: PixelEditorArgs(remotePath: remotePath, client: _ctrl.client),
    );
  }

  bool _isPaintFile(RemoteEntry e) =>
      !e.isDir && const {'png', 'gif', 'bm'}.contains(e.extension);

  /// Files we can open in the text editor (everything except binary blobs and
  /// apps, mirroring [_onEntryTap]).
  bool _isEditable(RemoteEntry e) =>
      !e.isDir && !const {'bin', 'elf', 'fuf', 'fap'}.contains(e.extension);

  /// Wraps an on-device file in an [ArchiveKey] (path preserved verbatim) and
  /// opens the shared archive emulation flow.
  void _emulateEntry(RemoteEntry e, ArchiveCategory cat) {
    final remotePath = _ctrl.childPath(e.name);
    final dot = e.name.lastIndexOf('.');
    final name = dot > 0 ? e.name.substring(0, dot) : e.name;
    final key = ArchiveKey(
      name: name,
      category: cat,
      state: ArchiveKeyState.synced,
      extension: e.extension,
      remotePath: remotePath,
    );
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EmulatePage(flipperKey: key)));
  }

  /// Opens the system folder picker and returns the chosen directory, or null
  /// if the user cancels or the platform has no directory picker.
  Future<String?> _pickDestinationDir() async {
    try {
      return await FilePicker.platform.getDirectoryPath(
        dialogTitle: context.l10n.fmChooseDownloadLocation,
      );
    } catch (e) {
      if (mounted) {
        context.showNotification(
          context.l10n.fmFolderPickUnsupported,
          type: QNotificationType.error,
        );
      }
      return null;
    }
  }

  /// Downloads [entries] (files and/or whole directory trees) into a folder the
  /// user picks via the system file picker, recreating folders recursively.
  Future<void> _downloadEntries(List<RemoteEntry> entries) async {
    if (entries.isEmpty) {
      context.showNotification(
        context.l10n.fmNothingToDownload,
        type: QNotificationType.warning,
      );
      return;
    }
    final destDir = await _pickDestinationDir();
    if (!mounted || destDir == null) return;

    // A single file fills its own row inline; batches use the external bar.
    if (entries.length == 1 && !entries.single.isDir) {
      final ok = await _ctrl.downloadEntryTo(entries.single, destDir: destDir);
      if (!mounted || ok) return;
      context.showNotification(
        context.l10n.fmDownloadFailed,
        type: QNotificationType.error,
      );
      return;
    }

    final failures = await _ctrl.downloadEntriesTo(entries, destDir: destDir);
    if (!mounted || failures == 0) return;
    context.showNotification(
      context.l10n.fmDownloadFailedCount(failures),
      type: QNotificationType.error,
    );
  }

  Future<bool> _indexFapIcon(RemoteEntry e, {bool silent = false}) async {
    final remotePath = _ctrl.childPath(e.name);
    final appId = e.name.toLowerCase().endsWith('.fap')
        ? e.name.substring(0, e.name.length - 4)
        : e.name;

    if (!silent) context.showNotification(context.l10n.fmIndexingIcon(e.name));
    final bytes = await _ctrl.readBytes(remotePath);
    if (!mounted) return false;
    if (bytes == null) {
      if (!silent) {
        context.showNotification(
          context.l10n.fmDownloadFailedFor(e.name),
          type: QNotificationType.error,
        );
      }
      return false;
    }

    final extracted = extractFapIcon(Uint8List.fromList(bytes));
    final icon = extracted?.icon;
    if (icon == null) {
      if (!silent) {
        context.showNotification(
          context.l10n.fmNoIconIn(e.name),
          type: QNotificationType.warning,
        );
      }
      return false;
    }

    // Writing bumps icon_repo.fapIconRevision, which the file rows listen to,
    // so the icon refreshes immediately without recreating the page.
    await icon_repo.writeFapIcon(appId, icon);
    if (!mounted || silent) return true;
    context.showNotification(
      context.l10n.fmIconIndexed(
        extracted?.name.isNotEmpty == true ? extracted!.name : appId,
      ),
      type: QNotificationType.good,
    );
    return true;
  }

  /// True when every selected entry is a `.fap`, which is the only case where
  /// batch icon indexing makes sense.
  bool get _selectionAllFap =>
      _selected.isNotEmpty &&
      _selectedEntries.every((e) => !e.isDir && e.extension == 'fap');

  Future<void> _indexFapIconsSelected() async {
    final items = _selectedEntries;
    if (items.isEmpty) return;
    context.showNotification(context.l10n.fmIndexingIcons(items.length));
    var indexed = 0;
    for (final e in items) {
      if (await _indexFapIcon(e, silent: true)) indexed++;
      if (!mounted) return;
    }
    _exitSelection();
    context.showNotification(
      indexed == items.length
          ? context.l10n.fmIndexedIcons(indexed)
          : context.l10n.fmIndexedPartial(indexed, items.length),
      type: indexed == items.length
          ? QNotificationType.good
          : QNotificationType.warning,
    );
  }

  Future<void> _deleteEntry(RemoteEntry e, {bool recursive = false}) async {
    final ok = await _confirm(context.l10n.fmDeleteOne(e.name));
    if (!ok) return;
    final remotePath = _ctrl.childPath(e.name);
    final success = await _ctrl.delete(remotePath, recursive: recursive);
    if (success) await _ctrl.refresh();
    if (!mounted) return;
    if (!success) {
      context.showNotification(
        context.l10n.fmDeleteFailed,
        type: QNotificationType.error,
      );
    }
  }

  Future<void> _deleteSelected() async {
    final items = _selectedEntries;
    if (items.isEmpty) return;
    final ok = await _confirm(context.l10n.fmDeleteMany(items.length));
    if (!ok) return;
    var failures = 0;
    for (final e in items) {
      final done = await _ctrl.delete(
        _ctrl.childPath(e.name),
        recursive: e.isDir,
      );
      if (!done) failures++;
    }
    _exitSelection();
    await _ctrl.refresh();
    if (!mounted) return;
    context.showNotification(
      failures == 0
          ? context.l10n.fmDeletedMany(items.length)
          : context.l10n.fmDeleteFailedCount(failures),
      type: failures == 0 ? QNotificationType.good : QNotificationType.error,
    );
  }

  Future<void> _downloadSelected() async {
    final items = _selectedEntries.toList();
    await _downloadEntries(items);
    if (mounted) _exitSelection();
  }

  void _renameSelected() {
    final items = _selectedEntries;
    if (items.length != 1) return;
    final name = items.first.name;
    _exitSelection();
    setState(() => _pendingRenameName = name);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingRenameName = null;
    });
  }

  Future<void> _renameEntry(RemoteEntry e, String newName) async {
    final from = _ctrl.childPath(e.name);
    final to = _ctrl.childPath(newName);
    final ok = await _ctrl.rename(from, to);
    if (ok) {
      _pendingRenameName = null;
      await _ctrl.refresh();
    }
    if (!mounted) return;
    if (!ok) {
      context.showNotification(
        context.l10n.fmRenameFailed,
        type: QNotificationType.error,
      );
    }
  }

  /// Picks a free name based on [base] (e.g. `new.txt`, `new1.txt`, …) within
  /// the current directory so creating a file never clobbers an existing one.
  String _uniqueName(String base) {
    final taken = _ctrl.entries.map((e) => e.name).toSet();
    if (!taken.contains(base)) return base;
    final dot = base.lastIndexOf('.');
    final stem = dot > 0 ? base.substring(0, dot) : base;
    final ext = dot > 0 ? base.substring(dot) : '';
    var i = 1;
    while (taken.contains('$stem$i$ext')) {
      i++;
    }
    return '$stem$i$ext';
  }

  Future<void> _createEmptyFile() async {
    final name = _uniqueName('new.txt');
    final ok = await _ctrl.writeBytes(_ctrl.childPath(name), const <int>[]);
    if (!mounted) return;
    if (!ok) {
      context.showNotification(
        context.l10n.fmCreateFileFailed,
        type: QNotificationType.error,
      );
      return;
    }
    _pendingRenameName = name;
    await _ctrl.refresh();
  }

  _ClipEntry _clip(RemoteEntry e) => _ClipEntry(
    remotePath: _ctrl.childPath(e.name),
    name: e.name,
    isDir: e.isDir,
  );

  void _setClipboard(List<RemoteEntry> entries, {required bool isCut}) {
    if (entries.isEmpty) return;
    setState(() {
      _clipboard = _Clipboard(items: entries.map(_clip).toList(), isCut: isCut);
    });
  }

  void _copyEntry(RemoteEntry e) => _setClipboard([e], isCut: false);

  void _cutEntry(RemoteEntry e) => _setClipboard([e], isCut: true);

  void _copySelected() {
    _setClipboard(_selectedEntries, isCut: false);
    _exitSelection();
  }

  void _moveSelected() {
    _setClipboard(_selectedEntries, isCut: true);
    _exitSelection();
  }

  Future<void> _paste() async {
    final cb = _clipboard;
    if (cb == null) return;
    var failures = 0;
    for (final item in cb.items) {
      final dest = _ctrl.childPath(item.name);
      // Skip a no-op paste into the item's own source folder.
      if (dest == item.remotePath) {
        failures++;
        continue;
      }
      bool ok;
      if (cb.isCut) {
        // Try a fast in-place rename first; it can't span storage roots
        // (e.g. /ext → /int), so fall back to copy-then-delete.
        ok = await _ctrl.rename(item.remotePath, dest);
        if (!ok) {
          ok = await _ctrl.copyEntry(item.remotePath, dest, isDir: item.isDir);
          if (ok) {
            ok = await _ctrl.delete(item.remotePath, recursive: item.isDir);
          }
        }
      } else {
        ok = await _ctrl.copyEntry(item.remotePath, dest, isDir: item.isDir);
      }
      if (!ok) failures++;
    }
    setState(() => _clipboard = null);
    await _ctrl.refresh();
    if (!mounted) return;
    if (failures == 0) {
      context.showNotification(
        cb.isCut
            ? context.l10n.fmMovedMany(cb.items.length)
            : context.l10n.fmCopiedMany(cb.items.length),
        type: QNotificationType.good,
      );
    } else {
      context.showNotification(
        cb.isCut
            ? context.l10n.fmMoveFailedCount(failures)
            : context.l10n.fmCopyFailedCount(failures),
        type: QNotificationType.error,
      );
    }
  }

  Future<void> _createFolder() async {
    final name = await _promptText(
      context.l10n.fmNewFolder,
      hintText: context.l10n.fmFolderName,
    );
    if (name == null || name.trim().isEmpty) return;
    final ok = await _ctrl.mkdir(name.trim());
    if (ok) await _ctrl.refresh();
    if (!mounted) return;
    if (!ok) {
      context.showNotification(
        context.l10n.fmCreateFolderFailed,
        type: QNotificationType.error,
      );
    }
  }

  Future<void> _uploadFromPath() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return;

    var failures = 0;
    for (final f in result.files) {
      final path = f.path;
      if (path == null) {
        failures++;
        continue;
      }
      final ok = await _ctrl.uploadFromLocal(path, targetName: f.name);
      if (!ok) failures++;
    }
    await _ctrl.refresh();
    if (!mounted) return;
    if (failures > 0) {
      context.showNotification(
        context.l10n.fmUploadFailedCount(failures, _ctrl.error ?? ''),
        type: QNotificationType.error,
      );
    } else {
      context.showNotification(
        context.l10n.fmUploaded(result.files.length),
        type: QNotificationType.good,
      );
    }
  }

  // ─── Dialogs ───────────────────────────────────────────────────────────────

  Future<bool> _confirm(String title) async {
    final colors = context.appColors;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: colors.dialogBackground,
            title: Text(title, style: TextStyle(color: colors.dialogText)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.l10n.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  context.l10n.commonDelete,
                  style: TextStyle(color: colors.danger),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> _promptText(
    String title, {
    String? initialValue,
    String? hintText,
  }) {
    final controller = TextEditingController(text: initialValue);
    final colors = context.appColors;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.dialogBackground,
        title: Text(title, style: TextStyle(color: colors.dialogText)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.dialogText),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: colors.dialogMuted),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(context.l10n.fmCreate),
          ),
        ],
      ),
    );
  }

  void _showSortSheet() {
    final colors = context.appColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        Widget tile(String label, FileSortMode mode) {
          final active = _ctrl.sortMode == mode;
          return ListTile(
            leading: Icon(
              active
                  ? (_ctrl.sortAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward)
                  : Icons.sort,
              color: active ? colors.accent : colors.textMuted,
            ),
            title: Text(
              label,
              style: TextStyle(
                color: active ? colors.accent : colors.textPrimary,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            onTap: () {
              _ctrl.setSortMode(mode);
              Navigator.of(sheetCtx).pop();
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.l10n.fmSortBy,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              tile(context.l10n.fmSortName, FileSortMode.name),
              tile(context.l10n.fmSortSize, FileSortMode.size),
              tile(context.l10n.fmSortType, FileSortMode.type),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showFabMenu() {
    final colors = context.appColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.note_add_outlined, color: colors.textPrimary),
              title: Text(
                context.l10n.fmNewFile,
                style: TextStyle(color: colors.textPrimary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _createEmptyFile();
              },
            ),
            ListTile(
              leading: SvgPicture.asset(
                'assets/ic/action/create-folder.svg',
                width: 22,
                height: 22,
                colorFilter: ColorFilter.mode(
                  colors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
              title: Text(
                context.l10n.fmNewFolder,
                style: TextStyle(color: colors.textPrimary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _createFolder();
              },
            ),
            ListTile(
              leading: SvgPicture.asset(
                'assets/ic/action/upload.svg',
                width: 22,
                height: 22,
                colorFilter: ColorFilter.mode(
                  colors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
              title: Text(
                context.l10n.fmUploadFiles,
                style: TextStyle(color: colors.textPrimary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _uploadFromPath();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  String get _sortKey => switch (_ctrl.sortMode) {
    FileSortMode.name => 'name',
    FileSortMode.type => 'type',
    FileSortMode.size => 'size',
  };

  void _onSort(String key) {
    _ctrl.setSortMode(switch (key) {
      'type' => FileSortMode.type,
      'size' => FileSortMode.size,
      _ => FileSortMode.name,
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accent = colors.accent;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _handleBack();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final entries = _ctrl.entries;
          final allSelected =
              entries.isNotEmpty &&
              entries.every((e) => _selected.contains(e.name));
          final canDismiss =
              ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
          final portrait =
              MediaQuery.orientationOf(context) == Orientation.portrait;
          final showLeading =
              _selectionMode ||
              _ctrl.isSearching ||
              _ctrl.canGoUp ||
              canDismiss;
          return Scaffold(
            backgroundColor: colors.background,
            appBar: AppBar(
              backgroundColor: accent,
              foregroundColor: colors.onAccent,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              titleSpacing: showLeading ? 0 : NavigationToolbar.kMiddleSpacing,
              automaticallyImplyLeading: false,
              leading: !showLeading
                  ? null
                  : _selectionMode
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _exitSelection,
                    )
                  : BackButton(onPressed: _handleBackButton),
              title: _selectionMode
                  ? Text(
                      context.l10n.selectedCount(_selected.length),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : _buildSearchField(colors),
              actions: _selectionMode
                  ? [
                      _BarButton(
                        icon: allSelected
                            ? Icons.deselect_rounded
                            : Icons.select_all_rounded,
                        label: allSelected
                            ? context.l10n.selectNone
                            : context.l10n.selectAll,
                        onTap: _selectAll,
                      ),
                      _BarButton(
                        icon: Icons.more_horiz_rounded,
                        tooltip: context.l10n.fmMoreActions,
                        onTap: _selected.isEmpty ? null : _showSelectionActions,
                      ),
                      const SizedBox(width: 8),
                    ]
                  : [
                      if (_ctrl.viewMode == FileViewMode.grid)
                        _BarButton(
                          icon: Icons.swap_vert_rounded,
                          tooltip: context.l10n.fmSortBy,
                          onTap: _showSortSheet,
                        ),
                      _BarButton(
                        icon: _ctrl.viewMode == FileViewMode.list
                            ? Icons.grid_view_rounded
                            : Icons.view_list_rounded,
                        tooltip: _ctrl.viewMode == FileViewMode.list
                            ? context.l10n.fmGridView
                            : context.l10n.fmListView,
                        onTap: _ctrl.toggleViewMode,
                      ),
                      _BarButton(
                        icon: _ctrl.showHidden
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        tooltip: _ctrl.showHidden
                            ? context.l10n.fmHideHidden
                            : context.l10n.fmShowHidden,
                        active: _ctrl.showHidden,
                        onTap: _ctrl.toggleHidden,
                      ),
                      if (!portrait)
                        _BarButton(
                          icon: Icons.refresh_rounded,
                          tooltip: context.l10n.fmRefresh,
                          onTap: _ctrl.loading ? null : _ctrl.refresh,
                        ),
                      _BarButton(label: '${entries.length}'),
                      const SizedBox(width: 8),
                    ],
            ),
            body: Column(
              children: [
                _buildBreadcrumbs(colors),
                if (_clipboard != null) _buildClipboardBanner(colors),
                if (_ctrl.transferLabel != null) _buildTransferBar(colors),
                Expanded(child: _buildBody(context, entries)),
              ],
            ),
            floatingActionButton: _selectionMode
                ? null
                : FloatingActionButton.small(
                    backgroundColor: accent,
                    foregroundColor: colors.onAccent,
                    onPressed: _showFabMenu,
                    child: const Icon(Icons.add),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildSearchField(QAppColors colors) {
    final on = colors.onAccent;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          onChanged: (v) => setState(() => _ctrl.setSearch(v)),
          textInputAction: TextInputAction.search,
          style: TextStyle(color: on, fontSize: 13),
          cursorColor: on,
          decoration: InputDecoration(
            hintText: context.l10n.fmSearchInFolder,
            hintStyle: TextStyle(color: on.withValues(alpha: 0.6)),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: on.withValues(alpha: 0.75),
              size: 17,
            ),
            suffixIcon: _searchCtrl.text.isEmpty
                ? null
                : IconButton(
                    tooltip: context.l10n.commonClear,
                    icon: Icon(
                      Icons.close_rounded,
                      color: on.withValues(alpha: 0.75),
                      size: 15,
                    ),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _ctrl.setSearch(''));
                      _searchFocus.requestFocus();
                    },
                  ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.16),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 9,
            ),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.28),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.55),
                width: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSelectionActions() async {
    final items = _selectedEntries;
    if (items.isEmpty) return;
    final actions = <ActionItem>[
      if (items.length == 1 && _ctrl.viewMode == FileViewMode.list)
        ActionItem(
          icon: Icons.drive_file_rename_outline,
          label: context.l10n.fmRename,
          onTap: _renameSelected,
        ),
      ActionItem(
        icon: Icons.download_outlined,
        label: context.l10n.fmDownload,
        onTap: _downloadSelected,
      ),
      ActionItem(
        icon: Icons.copy_outlined,
        label: context.l10n.fmCopy,
        onTap: _copySelected,
      ),
      ActionItem(
        icon: Icons.drive_file_move_outlined,
        label: context.l10n.fmMove,
        onTap: _moveSelected,
      ),
      if (_selectionAllFap)
        ActionItem(
          icon: Icons.image_outlined,
          label: items.length == 1
              ? context.l10n.fmIndexIcon
              : context.l10n.fmIndexIcons,
          onTap: _indexFapIconsSelected,
        ),
      ActionItem(
        icon: Icons.delete_outline,
        label: context.l10n.commonDelete,
        destructive: true,
        onTap: _deleteSelected,
      ),
    ];
    await ActionsSheet.show(
      context,
      leading: FileIconBadge(entry: items.first, size: 40),
      title: context.l10n.selectedCount(items.length),
      subtitle: _ctrl.path,
      actions: actions,
    );
  }

  Future<void> _handleBackButton() async {
    final shouldPop = await _handleBack();
    if (!shouldPop || !mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  Widget _buildBreadcrumbs(QAppColors colors) {
    final segments = _ctrl.path.split('/').where((s) => s.isNotEmpty).toList();
    final crumbs = <Widget>[];

    Widget chip(Widget child, String targetPath, {bool isLast = false}) {
      return InkWell(
        onTap: isLast ? null : () => _navigateTo(targetPath),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: child,
        ),
      );
    }

    crumbs.add(
      chip(
        Icon(
          Icons.home_filled,
          size: 18,
          color: segments.isEmpty ? colors.accent : colors.textSecondary,
        ),
        '/',
        isLast: segments.isEmpty,
      ),
    );

    var cumulative = '';
    for (var i = 0; i < segments.length; i++) {
      cumulative += '/${segments[i]}';
      final isLast = i == segments.length - 1;
      crumbs.add(Icon(Icons.chevron_right, size: 16, color: colors.textMuted));
      crumbs.add(
        chip(
          Text(
            segments[i],
            style: TextStyle(
              color: isLast ? colors.accent : colors.textSecondary,
              fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13.5,
            ),
          ),
          cumulative,
          isLast: isLast,
        ),
      );
    }

    return Container(
      height: 40,
      width: double.infinity,
      color: fileBarColor(colors),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: crumbs),
      ),
    );
  }

  Widget _buildTransferBar(QAppColors colors) {
    final progress = _ctrl.transferProgress;
    return SyncProgressBar(
      icon: Icons.download_rounded,
      label: _ctrl.transferLabel!,
      progress: progress,
      color: colors.accent,
    );
  }

  Widget _buildClipboardBanner(QAppColors colors) {
    final cb = _clipboard!;
    return Container(
      height: 32,
      color: colors.accent.withValues(alpha: 0.12),
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
      child: Row(
        children: [
          Icon(
            cb.isCut ? Icons.content_cut : Icons.content_copy,
            size: 14,
            color: colors.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${cb.isCut ? context.l10n.fmMoving : context.l10n.fmCopying}'
              ' ${cb.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textPrimary, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: _paste,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              context.l10n.fmPasteHere,
              style: TextStyle(
                color: colors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 15, color: colors.textMuted),
            onPressed: () => setState(() => _clipboard = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<RemoteEntry> entries) {
    final colors = context.appColors;
    if (_ctrl.loading && entries.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (!_ctrl.client.isConnected) {
      return ArchiveEmptyView(
        icon: Icons.link_off,
        title: context.l10n.fmNotConnected,
        subtitle: context.l10n.fmNotConnectedHint,
        actionLabel: context.l10n.commonConnect,
        onAction: _connect,
      );
    }
    if (_ctrl.error != null && entries.isEmpty) {
      return ArchiveEmptyView(
        icon: Icons.error_outline,
        title: _ctrl.error!,
        actionLabel: context.l10n.commonRetry,
        onAction: _ctrl.refresh,
      );
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        return RefreshIndicator(
          color: colors.accent,
          displacement: 15,
          onRefresh: _ctrl.refresh,
          child: entries.isEmpty
              ? SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: _buildEmptyState(),
                  ),
                )
              : _ctrl.viewMode == FileViewMode.grid
              ? _buildGrid(entries)
              : _buildTable(entries, constraints),
        );
      },
    );
  }

  Widget _buildTable(List<RemoteEntry> entries, BoxConstraints constraints) {
    final cols = layoutFileColumns(
      fileColumns(),
      constraints.maxWidth -
          kFileTrailingWidth -
          (_selectionMode ? kFileSelectionWidth : 0),
      entries,
    );
    return Column(
      children: [
        FileColumnHeader(
          cols: cols,
          sortKey: _sortKey,
          sortAsc: _ctrl.sortAscending,
          onSort: _onSort,
          selectionMode: _selectionMode,
        ),
        Expanded(
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final e = entries[i];
              return FileTableRow(
                key: ValueKey('${e.isDir}:${e.name}'),
                entry: e,
                cols: cols,
                actions: _actionsFor(e),
                selectionMode: _selectionMode,
                selected: _selected.contains(e.name),
                progress: _ctrl.entryProgress(e.name),
                autoEdit: e.name == _pendingRenameName,
                onTap: () => _onEntryTap(e),
                onLongPress: () => _enterSelection(e),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(List<RemoteEntry> entries) {
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 80),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 104,
        mainAxisExtent: 104,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[i];
        return FileGridTile(
          key: ValueKey('${e.isDir}:${e.name}'),
          entry: e,
          actions: _actionsFor(e),
          selectionMode: _selectionMode,
          selected: _selected.contains(e.name),
          progress: _ctrl.entryProgress(e.name),
          onTap: () => _onEntryTap(e),
          onLongPress: () => _enterSelection(e),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final searching = _ctrl.isSearching;
    return ArchiveEmptyView(
      icon: searching ? Icons.search_off : Icons.folder_open,
      title: searching ? context.l10n.fmNoMatches : context.l10n.fmEmptyFolder,
      subtitle: searching ? null : context.l10n.fmEmptyHint,
      actionLabel: searching
          ? context.l10n.commonClear
          : context.l10n.fmRefresh,
      onAction: searching ? _stopSearch : _ctrl.refresh,
    );
  }

  FileEntryActions _actionsFor(RemoteEntry e) {
    final cat = e.isDir ? null : ArchiveCategory.fromExtension(e.extension);
    return FileEntryActions(
      onRename: (n) => _renameEntry(e, n),
      onDelete: () => _deleteEntry(e, recursive: e.isDir),
      onShare: e.isDir
          ? null
          : () => shareRemoteFile(
              context,
              _ctrl,
              _ctrl.childPath(e.name),
              displayName: e.name,
              expectedSize: e.size,
            ),
      onCopy: () => _copyEntry(e),
      onCut: () => _cutEntry(e),
      onDownload: () => _downloadEntries([e]),
      onIndexIcon: (!e.isDir && e.extension == 'fap')
          ? () => _indexFapIcon(e)
          : null,
      onEmulate: (cat != null && cat.emulatable)
          ? () => _emulateEntry(e, cat)
          : null,
      onEdit: _isEditable(e)
          ? () {
              if (_isPaintFile(e)) {
                _openPaintEditor(_ctrl.childPath(e.name));
              } else {
                _openTextEditor(e);
              }
            }
          : null,
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    this.icon,
    this.label,
    this.tooltip,
    this.onTap,
    this.active = false,
  });

  static const double size = 36;

  final IconData? icon;
  final String? label;
  final String? tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final text = label;
    final glyph = icon;
    final foreground = active ? colors.accent : colors.onAccent;
    final dimmed = onTap == null && tooltip != null;

    Widget control = Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Center(
        child: Opacity(
          opacity: dimmed ? 0.45 : 1,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: size,
              width: (glyph != null && text == null) ? size : null,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(
                horizontal: (glyph != null && text == null) ? 0 : 10,
              ),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withValues(alpha: 0.88)
                    : Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(9),
                border: active
                    ? null
                    : Border.all(color: Colors.white.withValues(alpha: 0.26)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (glyph != null) Icon(glyph, size: 17, color: foreground),
                  if (glyph != null && text != null) const SizedBox(width: 5),
                  if (text != null)
                    Text(
                      text,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final message = tooltip;
    if (message != null) {
      control = QPageAppBarTooltip(message: message, child: control);
    }
    return control;
  }
}
