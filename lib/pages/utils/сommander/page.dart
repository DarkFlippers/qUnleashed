import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../../../widgets/notification.dart';
import '../../archive/emulate/page.dart';
import '../../../models/category.dart';
import '../../archive/models/key.dart';
import '../../editor/page.dart';
import '../../remote/page.dart';
import 'share_remote_file.dart';
import 'controller.dart';
import 'widgets/file_row.dart';

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
      items.length == 1 ? items.first.name : '${items.length} items';
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

  bool _searching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

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

  // ─── Navigation ────────────────────────────────────────────────────────────

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
    _openTextEditor(_ctrl.childPath(e.name));
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
    if (_searching) {
      _stopSearch();
      return false;
    }
    if (_ctrl.canGoUp) {
      await _ctrl.goUp();
      return false;
    }
    return true;
  }

  // ─── Selection ───────────────────────────────────────────────────────────────

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

  // ─── Search ──────────────────────────────────────────────────────────────────

  void _startSearch() {
    setState(() => _searching = true);
    _searchFocus.requestFocus();
  }

  void _stopSearch() {
    _searchCtrl.clear();
    _ctrl.setSearch('');
    setState(() => _searching = false);
  }

  // ─── File operations ──────────────────────────────────────────────────────────

  Future<void> _launchFap(String remotePath) async {
    final ok = await _ctrl.launchFap(remotePath);
    if (!mounted) return;
    if (!ok) {
      context.showNotification(
        'Failed to launch app',
        type: QNotificationType.error,
      );
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RemoteControlPage()));
  }

  Future<void> _openTextEditor(String remotePath) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            TextEditorPage(remotePath: remotePath, client: _ctrl.client),
      ),
    );
    await _ctrl.refresh();
  }

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
        dialogTitle: 'Choose download location',
      );
    } catch (e) {
      if (mounted) {
        context.showNotification(
          'Choosing a folder is not supported on this platform',
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
        'Nothing to download',
        type: QNotificationType.warning,
      );
      return;
    }
    final destDir = await _pickDestinationDir();
    if (!mounted || destDir == null) return;

    final failures = await _ctrl.downloadEntriesTo(entries, destDir: destDir);
    if (!mounted) return;
    context.showNotification(
      failures == 0
          ? 'Downloaded to $destDir'
          : 'Failed to download $failures file(s)',
      type: failures == 0 ? QNotificationType.good : QNotificationType.error,
    );
  }

  Future<void> _deleteEntry(RemoteEntry e, {bool recursive = false}) async {
    final ok = await _confirm('Delete “${e.name}”?');
    if (!ok) return;
    final remotePath = _ctrl.childPath(e.name);
    final success = await _ctrl.delete(remotePath, recursive: recursive);
    if (success) await _ctrl.refresh();
    if (!mounted) return;
    if (!success) {
      context.showNotification('Delete failed', type: QNotificationType.error);
    }
  }

  Future<void> _deleteSelected() async {
    final items = _selectedEntries;
    if (items.isEmpty) return;
    final ok = await _confirm(
      'Delete ${items.length} item${items.length == 1 ? '' : 's'}?',
    );
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
          ? 'Deleted ${items.length} item${items.length == 1 ? '' : 's'}'
          : 'Failed to delete $failures item(s)',
      type: failures == 0 ? QNotificationType.good : QNotificationType.error,
    );
  }

  Future<void> _downloadSelected() async {
    final items = _selectedEntries.toList();
    await _downloadEntries(items);
    if (mounted) _exitSelection();
  }

  Future<void> _renameEntry(RemoteEntry e, String newName) async {
    final from = _ctrl.childPath(e.name);
    final to = _ctrl.childPath(newName);
    final ok = await _ctrl.rename(from, to);
    if (ok) await _ctrl.refresh();
    if (!mounted) return;
    if (!ok) {
      context.showNotification('Rename failed', type: QNotificationType.error);
    }
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
    final verb = cb.isCut ? 'move' : 'copy';
    if (failures == 0) {
      context.showNotification(
        '${cb.isCut ? 'Moved' : 'Copied'} ${cb.items.length} item${cb.items.length == 1 ? '' : 's'}',
        type: QNotificationType.good,
      );
    } else {
      context.showNotification(
        'Failed to $verb $failures item(s)',
        type: QNotificationType.error,
      );
    }
  }

  Future<void> _createFolder() async {
    final name = await _promptText('New folder', hintText: 'Folder name');
    if (name == null || name.trim().isEmpty) return;
    final ok = await _ctrl.mkdir(name.trim());
    if (ok) await _ctrl.refresh();
    if (!mounted) return;
    if (!ok) {
      context.showNotification(
        'Create folder failed',
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
        'Upload failed for $failures file(s): ${_ctrl.error ?? ''}',
        type: QNotificationType.error,
      );
    } else {
      context.showNotification(
        'Uploaded ${result.files.length} file(s)',
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
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Delete', style: TextStyle(color: colors.danger)),
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Create'),
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
                    'Sort by',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              tile('Name', FileSortMode.name),
              tile('Size', FileSortMode.size),
              tile('Type', FileSortMode.type),
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
                'New folder',
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
                'Upload files',
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
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
          return Scaffold(
            backgroundColor: colors.background,
            appBar: _buildAppBar(colors),
            body: Column(
              children: [
                _buildBreadcrumbs(colors),
                if (_clipboard != null) _buildClipboardBanner(colors),
                if (_ctrl.transferLabel != null) _buildTransferBar(colors),
                Expanded(child: _buildBody(context)),
              ],
            ),
            floatingActionButton: _selectionMode
                ? null
                : FloatingActionButton(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                    onPressed: _showFabMenu,
                    child: const Icon(Icons.add),
                  ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(QAppColors colors) {
    if (_selectionMode) {
      return AppBar(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exitSelection,
        ),
        title: Text(
          '${_selected.length} selected',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: _buildSelectionActions(colors),
      );
    }

    if (_searching) {
      return AppBar(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _stopSearch,
        ),
        title: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          autofocus: true,
          style: TextStyle(color: colors.onAccent, fontSize: 16),
          cursorColor: colors.onAccent,
          decoration: InputDecoration(
            hintText: 'Search in this folder',
            border: InputBorder.none,
            hintStyle: TextStyle(color: colors.onAccent.withValues(alpha: 0.7)),
          ),
          onChanged: _ctrl.setSearch,
        ),
        actions: [
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _searchCtrl.clear();
                _ctrl.setSearch('');
                setState(() {});
              },
            ),
        ],
      );
    }

    final title = _ctrl.canGoUp
        ? _ctrl.path.substring(_ctrl.path.lastIndexOf('/') + 1)
        : _ctrl.path;
    return AppBar(
      backgroundColor: colors.accent,
      foregroundColor: colors.onAccent,
      leading: BackButton(onPressed: () => _handleBackButton()),
      title: Text(
        title.isEmpty ? '/' : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search),
          onPressed: _startSearch,
        ),
        IconButton(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort),
          onPressed: _showSortSheet,
        ),
        IconButton(
          tooltip: _ctrl.viewMode == FileViewMode.list
              ? 'Grid view'
              : 'List view',
          icon: Icon(
            _ctrl.viewMode == FileViewMode.list
                ? Icons.grid_view
                : Icons.view_list,
          ),
          onPressed: _ctrl.toggleViewMode,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            switch (v) {
              case 'hidden':
                _ctrl.toggleHidden();
              case 'select':
                if (_ctrl.entries.isNotEmpty) {
                  setState(() => _selectionMode = true);
                }
              case 'refresh':
                if (!_ctrl.loading) _ctrl.refresh();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'hidden',
              child: Row(
                children: [
                  Icon(
                    _ctrl.showHidden ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(_ctrl.showHidden ? 'Hide hidden' : 'Show hidden'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'select',
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 20),
                  SizedBox(width: 12),
                  Text('Select'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'refresh',
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 20),
                  SizedBox(width: 12),
                  Text('Refresh'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _handleBackButton() async {
    final shouldPop = await _handleBack();
    if (shouldPop && mounted) Navigator.of(context).pop();
  }

  List<Widget> _buildSelectionActions(QAppColors colors) {
    final all = _ctrl.entries.length;
    final empty = _selected.isEmpty;
    return [
      IconButton(
        tooltip: 'Download',
        icon: const Icon(Icons.download_outlined),
        onPressed: empty ? null : _downloadSelected,
      ),
      IconButton(
        tooltip: 'Copy',
        icon: const Icon(Icons.copy_outlined),
        onPressed: empty ? null : _copySelected,
      ),
      IconButton(
        tooltip: 'Move',
        icon: const Icon(Icons.drive_file_move_outlined),
        onPressed: empty ? null : _moveSelected,
      ),
      IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline),
        onPressed: empty ? null : _deleteSelected,
      ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (v) {
          if (v == 'all') _selectAll();
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'all',
            child: Row(
              children: [
                Icon(
                  _selected.length == all ? Icons.deselect : Icons.select_all,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(_selected.length == all ? 'Deselect all' : 'Select all'),
              ],
            ),
          ),
        ],
      ),
    ];
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
    // While progress is still zero (planning, or first chunk not yet sent) show
    // an indeterminate animation instead of an empty 0% bar.
    final indeterminate = progress <= 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _ctrl.transferLabel!,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ),
              Text(
                indeterminate ? '…' : '${(progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: indeterminate ? null : progress,
              minHeight: 4,
              color: colors.accent,
              backgroundColor: colors.divider,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClipboardBanner(QAppColors colors) {
    final cb = _clipboard!;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            cb.isCut ? Icons.content_cut : Icons.content_copy,
            size: 18,
            color: colors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${cb.isCut ? 'Moving' : 'Copying'} ${cb.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _paste,
            child: Text(
              'Paste here',
              style: TextStyle(
                color: colors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: colors.textMuted),
            onPressed: () => setState(() => _clipboard = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ─── Body ────────────────────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context) {
    final colors = context.appColors;
    if (_ctrl.loading && _ctrl.entries.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_ctrl.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colors.danger),
              const SizedBox(height: 12),
              Text(
                _ctrl.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _ctrl.refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_ctrl.isEmptyAfterFilter) {
      return _buildEmptyState(colors);
    }

    final grid = _ctrl.viewMode == FileViewMode.grid;
    return RefreshIndicator(
      color: colors.accent,
      onRefresh: _ctrl.refresh,
      child: CustomScrollView(
        slivers: [
          ..._buildSection(colors, 'Folders', _ctrl.folders, grid),
          ..._buildSection(colors, 'Files', _ctrl.files, grid),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(QAppColors colors) {
    final searching = _ctrl.isSearching;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  searching ? Icons.search_off : Icons.folder_open_outlined,
                  size: 56,
                  color: colors.textMuted,
                ),
                const SizedBox(height: 14),
                Text(
                  searching ? 'No matches' : 'This folder is empty',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!searching) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Use + to add files or folders',
                    style: TextStyle(color: colors.textMuted, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSection(
    QAppColors colors,
    String label,
    List<RemoteEntry> items,
    bool grid,
  ) {
    if (items.isEmpty) return const [];
    final header = SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(
          '$label · ${items.length}',
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );

    FileEntryActions makeActions(RemoteEntry e) {
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
              ),
        onCopy: () => _copyEntry(e),
        onCut: () => _cutEntry(e),
        onDownload: () => _downloadEntries([e]),
        onEmulate: (cat != null && cat.emulatable)
            ? () => _emulateEntry(e, cat)
            : null,
        onEdit: _isEditable(e)
            ? () => _openTextEditor(_ctrl.childPath(e.name))
            : null,
      );
    }

    if (grid) {
      final body = SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 104,
            // Fixed tile height keeps the layout stable regardless of how
            // narrow the column gets (e.g. a small desktop window).
            mainAxisExtent: 104,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          delegate: SliverChildBuilderDelegate((_, i) {
            final e = items[i];
            return FileGridTile(
              entry: e,
              actions: makeActions(e),
              selectionMode: _selectionMode,
              selected: _selected.contains(e.name),
              onTap: () => _onEntryTap(e),
              onLongPress: () => _enterSelection(e),
            );
          }, childCount: items.length),
        ),
      );
      return [header, body];
    }

    final body = SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final e = items[i];
          return FileRow(
            key: ValueKey('${e.isDir}:${e.name}'),
            entry: e,
            actions: makeActions(e),
            selectionMode: _selectionMode,
            selected: _selected.contains(e.name),
            onTap: () => _onEntryTap(e),
            onLongPress: () => _enterSelection(e),
          );
        },
      ),
    );
    return [header, body];
  }
}
