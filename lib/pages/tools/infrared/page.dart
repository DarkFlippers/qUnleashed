import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme/theme.dart';
import 'package:qunleashed/components/appbar.dart';
import 'package:qunleashed/theme/colors/category.dart';
import '../../../widgets/notification.dart';
import 'controller.dart';
import 'file_page.dart';
import 'models.dart';
import 'settings_dialog.dart';
import 'widgets/ir_search_field.dart';

const _infraredAsset = 'assets/ic/fileformat/ir.svg';

class IrLibPage extends StatefulWidget {
  const IrLibPage({super.key});

  @override
  State<IrLibPage> createState() => _IrLibPageState();
}

class _IrLibPageState extends State<IrLibPage> {
  final IrLibController _ctrl = IrLibController();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.initialize();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  bool get _canPop => _ctrl.searchQuery.isEmpty && !_ctrl.canGoUp;

  void _handlePop() {
    if (_ctrl.searchQuery.isNotEmpty) {
      _searchCtrl.clear();
      _ctrl.clearSearch();
      return;
    }
    if (_ctrl.canGoUp) {
      _ctrl.goUp();
    }
  }

  void _openEntry(IrEntry entry) {
    if (entry.isDir) {
      _ctrl.openPath(entry.path);
      return;
    }
    if (!entry.isIrFile) {
      context.showNotification(
        'Unsupported file: ${entry.name}',
        type: QNotificationType.warning,
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IrLibFilePage(controller: _ctrl, entry: entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handlePop();
      },
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Scaffold(
            backgroundColor: colors.background,
            appBar: QPageAppBar(
              title: _ctrl.title,
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              leading: _ctrl.canGoUp
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => _ctrl.goUp(),
                    )
                  : null,
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: _ctrl.loading ? null : _ctrl.refresh,
                ),
                IconButton(
                  tooltip: 'Source settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => IrLibSettingsDialog.show(context, _ctrl),
                ),
              ],
            ),
            body: Column(
              children: [
                IrSearchField(
                  controller: _searchCtrl,
                  hintText: 'Search whole IRDB',
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  onSubmitted: (q) => _ctrl.startSearch(q),
                  onClear: _ctrl.clearSearch,
                ),
                Expanded(child: _buildBody(context)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = context.appColors;
    if (_ctrl.searching) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: colors.accent),
              const SizedBox(height: 14),
              Text(
                'Searching IRDB',
                style: TextStyle(color: colors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                _ctrl.searchProgressPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    final isSearch = _ctrl.searchQuery.isNotEmpty;
    final source = isSearch ? _ctrl.searchResults : _ctrl.entries;
    final list = source.where((e) => e.isDir || e.isIrFile).toList();

    if (_ctrl.loading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_ctrl.error != null && list.isEmpty) {
      return _ErrorView(message: _ctrl.error!, onRetry: _ctrl.refresh);
    }
    if (list.isEmpty) {
      return _EmptyView(
        title: isSearch
            ? 'No matches for "${_ctrl.searchQuery}"'
            : 'Empty folder',
      );
    }

    return RefreshIndicator(
      color: colors.accent,
      onRefresh: () async {
        if (isSearch) {
          await _ctrl.startSearch(_ctrl.searchQuery);
        } else {
          await _ctrl.refresh();
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        itemCount: list.length + (isSearch ? 1 : 0),
        itemBuilder: (context, i) {
          if (isSearch && i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
              child: Text(
                '${list.length} result${list.length == 1 ? '' : 's'} for "${_ctrl.searchQuery}"',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            );
          }
          final entry = list[isSearch ? i - 1 : i];
          return _IrEntryCard(entry: entry, onTap: () => _openEntry(entry));
        },
      ),
    );
  }
}

class _IrEntryCard extends StatelessWidget {
  const _IrEntryCard({required this.entry, required this.onTap});

  final IrEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final infraredColor = ArchiveCategoryColor.infrared.color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: entry.isDir
                        ? colors.textMuted.withValues(alpha: 0.18)
                        : infraredColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: entry.isDir
                      ? Icon(
                          Icons.folder_outlined,
                          color: colors.textPrimary,
                          size: 22,
                        )
                      : SvgPicture.asset(
                          _infraredAsset,
                          width: 22,
                          height: 22,
                          colorFilter: ColorFilter.mode(
                            infraredColor,
                            BlendMode.srcIn,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.isDir
                            ? 'Folder'
                            : 'Infrared В· ${_formatSize(entry.size)}',
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(
                  entry.isDir ? Icons.chevron_right : Icons.download_outlined,
                  color: colors.textMuted,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatSize(int size) {
    if (size <= 0) return 'вЂ”';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 48, color: colors.textMuted),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(color: colors.textPrimary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 44, color: colors.danger),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textPrimary),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
