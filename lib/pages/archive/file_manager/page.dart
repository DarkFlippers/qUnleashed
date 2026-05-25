import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../../../widgets/notification.dart';
import '../../remote/page.dart';
import '../share_remote_file.dart';
import 'controller.dart';
import 'text_editor_page.dart';
import 'widgets/file_row.dart';

class _ClipboardItem {
  _ClipboardItem({
    required this.remotePath,
    required this.name,
    required this.isCut,
  });

  final String remotePath;
  final String name;
  final bool isCut;
}

class FileManagerPage extends StatefulWidget {
  const FileManagerPage({super.key, this.initialPath = '/ext'});

  final String initialPath;

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  late final FileManagerController _ctrl;
  _ClipboardItem? _clipboard;

  @override
  void initState() {
    super.initState();
    _ctrl = FileManagerController(initialPath: widget.initialPath);
    _ctrl.refresh();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onEntryTap(RemoteEntry e) {
    if (e.isDir) {
      _ctrl.open(_ctrl.childPath(e.name));
      return;
    }
    final ext = _ext(e.name);
    if (const {'bin', 'elf', 'fuf'}.contains(ext)) return;
    if (ext == 'fap') {
      _launchFap(_ctrl.childPath(e.name));
      return;
    }
    _openTextEditor(_ctrl.childPath(e.name));
  }

  String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  Future<void> _launchFap(String remotePath) async {
    final ok = await _ctrl.launchFap(remotePath);
    if (!mounted) return;
    if (!ok) {
      context.showNotification('Failed to launch app', type: QNotificationType.error);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RemoteControlPage()),
    );
  }

  Future<void> _openTextEditor(String remotePath) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            TextEditorPage(controller: _ctrl, remotePath: remotePath),
      ),
    );
    await _ctrl.refresh();
  }

  Future<void> _downloadFile(String remotePath) async {
    final result = await _ctrl.downloadTo(remotePath);
    if (!mounted) return;
    context.showNotification(
      result == null ? 'Download failed' : 'Saved to $result',
      type: result == null ? QNotificationType.error : QNotificationType.good,
    );
  }

  Future<void> _deleteEntry(RemoteEntry e, {bool recursive = false}) async {
    final ok = await _confirm('Delete ${e.name}?');
    if (!ok) return;
    final remotePath = _ctrl.childPath(e.name);
    final success = await _ctrl.delete(remotePath, recursive: recursive);
    if (success) await _ctrl.refresh();
    if (!mounted) return;
    if (!success) {
      context.showNotification('Delete failed', type: QNotificationType.error);
    }
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

  void _copyFile(RemoteEntry e) {
    setState(() {
      _clipboard = _ClipboardItem(
        remotePath: _ctrl.childPath(e.name),
        name: e.name,
        isCut: false,
      );
    });
  }

  void _cutFile(RemoteEntry e) {
    setState(() {
      _clipboard = _ClipboardItem(
        remotePath: _ctrl.childPath(e.name),
        name: e.name,
        isCut: true,
      );
    });
  }

  Future<void> _pasteFile() async {
    final cb = _clipboard;
    if (cb == null) return;
    final dest = _ctrl.childPath(cb.name);
    bool ok;
    if (cb.isCut) {
      ok = await _ctrl.rename(cb.remotePath, dest);
    } else {
      ok = await _ctrl.copy(cb.remotePath, dest);
    }
    if (ok) {
      setState(() => _clipboard = null);
      await _ctrl.refresh();
    }
    if (!mounted) return;
    if (!ok) {
      context.showNotification(
        cb.isCut ? 'Move failed' : 'Copy failed',
        type: QNotificationType.error,
      );
    }
  }

  Future<void> _createFolder() async {
    final name = await _promptText('New folder');
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
                child: Text('OK', style: TextStyle(color: colors.danger)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> _promptText(String title,
      {String? initialValue, String? hintText}) {
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showFabMenu() {
    final colors = context.appColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: SvgPicture.asset(
                'assets/flipper_svg/archive/ic_create_folder.svg',
                width: 22,
                height: 22,
                colorFilter:
                    ColorFilter.mode(colors.textPrimary, BlendMode.srcIn),
              ),
              title: Text('New folder',
                  style: TextStyle(color: colors.textPrimary)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _createFolder();
              },
            ),
            ListTile(
              leading: SvgPicture.asset(
                'assets/flipper_svg/archive/ic_upload.svg',
                width: 22,
                height: 22,
                colorFilter:
                    ColorFilter.mode(colors.textPrimary, BlendMode.srcIn),
              ),
              title: Text('Upload files',
                  style: TextStyle(color: colors.textPrimary)),
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            leading: _ctrl.canGoUp
                ? IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: _ctrl.goUp,
                  )
                : const BackButton(),
            title: Text(
              _ctrl.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            actions: [
              IconButton(
                tooltip: _ctrl.showHidden ? 'Hide hidden' : 'Show hidden',
                onPressed: _ctrl.toggleHidden,
                icon: Icon(
                  _ctrl.showHidden ? Icons.visibility : Icons.visibility_off,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _ctrl.loading ? null : _ctrl.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Column(
            children: [
              if (_clipboard != null) _buildClipboardBanner(colors),
              if (_ctrl.transferLabel != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _ctrl.transferLabel!,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            '${(_ctrl.transferProgress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _ctrl.transferProgress,
                          minHeight: 4,
                          color: colors.accent,
                          backgroundColor: colors.divider,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(child: _buildList(context)),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            onPressed: _showFabMenu,
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  Widget _buildClipboardBanner(QAppColors colors) {
    final cb = _clipboard!;
    return Container(
      color: colors.card,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
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
                cb.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _pasteFile,
              child: Text(
                'Paste here',
                style: TextStyle(color: colors.accent, fontWeight: FontWeight.w700),
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

  Widget _buildList(BuildContext context) {
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
              Text(_ctrl.error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _ctrl.refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final list = _ctrl.entries;
    if (list.isEmpty) {
      return Center(
        child: Text('Empty folder', style: TextStyle(color: colors.textMuted)),
      );
    }
    return RefreshIndicator(
      color: colors.accent,
      onRefresh: _ctrl.refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final e = list[i];
          return FileRow(
            entry: e,
            onTap: () => _onEntryTap(e),
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
            onCopy: e.isDir ? null : () => _copyFile(e),
            onCut: e.isDir ? null : () => _cutFile(e),
            onDownload: e.isDir
                ? null
                : () => _downloadFile(_ctrl.childPath(e.name)),
          );
        },
      ),
    );
  }
}
