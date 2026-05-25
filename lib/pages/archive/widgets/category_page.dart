import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../controller.dart';
import '../models/category.dart';
import '../models/key.dart';
import 'empty_view.dart';
import 'key_actions_sheet.dart';
import 'key_card.dart';
import 'sync_progress_view.dart';

// ── Column definitions ────────────────────────────────────────────────────────

class _Col {
  const _Col(this.label, this.width, {this.sortKey, this.right = false, this.hideLevel});
  final String label;
  final double width; // 0 = flexible (name column)
  final String? sortKey;
  final bool right;
  // 1=hide first (size), 2=hide second (uid/detail), 3=hide third (mtime)
  final int? hideLevel;
}

const double _nameMinW = 140;
const double _rowH = 48;
const double _headerH = 34;

Map<ArchiveCategory, List<_Col>> _cols(ArchiveCategory cat) {
  switch (cat) {
    case ArchiveCategory.nfc:
      return {
        cat: const [
          _Col('Name / Folder', 0, sortKey: 'name'),
          _Col('Type', 140, sortKey: 'type'),
          _Col('UID', 190, sortKey: 'uid', hideLevel: 2),
          _Col('Size', 68, sortKey: 'size', right: true, hideLevel: 1),
          _Col('Modified', 88, sortKey: 'mtime', right: true, hideLevel: 3),
        ]
      };
    case ArchiveCategory.rfid:
      return {
        cat: const [
          _Col('Key / Folder', 0, sortKey: 'name'),
          _Col('Type', 120, sortKey: 'type'),
          _Col('Data', 190, sortKey: 'data', hideLevel: 2),
          _Col('Size', 68, sortKey: 'size', right: true, hideLevel: 1),
          _Col('Modified', 88, sortKey: 'mtime', right: true, hideLevel: 3),
        ]
      };
    case ArchiveCategory.infrared:
      return {
        cat: const [
          _Col('Remote / Folder', 0, sortKey: 'name'),
          _Col('Signals', 72, sortKey: 'signals', right: true),
          _Col('Protocols', 170, sortKey: 'protocols', hideLevel: 2),
          _Col('Modified', 88, sortKey: 'mtime', right: true, hideLevel: 3),
        ]
      };
    case ArchiveCategory.subghz:
    case ArchiveCategory.wardriving:
      return {
        cat: const [
          _Col('Name / Folder', 0, sortKey: 'name'),
          _Col('Frequency', 104, sortKey: 'frequency', right: true),
          _Col('Protocol', 120, sortKey: 'protocol'),
          _Col('Preset', 100, hideLevel: 2),
          _Col('Mod', 56, sortKey: 'modulation', hideLevel: 1),
          _Col('Modified', 88, sortKey: 'mtime', right: true, hideLevel: 3),
        ]
      };
    case ArchiveCategory.ibutton:
      return {
        cat: const [
          _Col('Key / Folder', 0, sortKey: 'name'),
          _Col('Type', 120, sortKey: 'type'),
          _Col('Size', 68, sortKey: 'size', right: true, hideLevel: 1),
          _Col('Modified', 88, sortKey: 'mtime', right: true, hideLevel: 3),
        ]
      };
    case ArchiveCategory.badusb:
      return {
        cat: const [
          _Col('Script / Folder', 0, sortKey: 'name'),
          _Col('Kind', 76, sortKey: 'kind'),
          _Col('Lines', 60, sortKey: 'lines', right: true, hideLevel: 2),
          _Col('Size', 68, sortKey: 'size', right: true, hideLevel: 1),
          _Col('Modified', 88, sortKey: 'mtime', right: true, hideLevel: 3),
        ]
      };
  }
}

List<_Col> _colsFor(ArchiveCategory cat) => _cols(cat)[cat]!;

/// Returns the subset of columns that fit in [availableWidth] by progressively
/// hiding columns in hideLevel order (1→size, 2→uid/detail, 3→mtime).
/// Also returns the resolved name-column width.
(List<_Col>, double) _visibleCols(ArchiveCategory cat, double availableWidth) {
  final all = _colsFor(cat);
  for (int level = 0; level <= 3; level++) {
    final visible = all
        .where((c) => c.hideLevel == null || c.hideLevel! > level)
        .toList();
    final fixed = visible
        .where((c) => c.width > 0)
        .fold(0.0, (s, c) => s + c.width);
    final nameW = availableWidth - fixed - 16;
    if (nameW >= _nameMinW) return (visible, nameW);
  }
  // Fallback: show only non-hideable columns and give name whatever space remains.
  final core = all.where((c) => c.hideLevel == null).toList();
  final fixed = core.where((c) => c.width > 0).fold(0.0, (s, c) => s + c.width);
  return (core, (availableWidth - fixed - 16).clamp(_nameMinW, double.infinity));
}

// ── Sort helpers ──────────────────────────────────────────────────────────────

List<ArchiveKey> _sortKeys(
  List<ArchiveKey> keys,
  String sortKey,
  bool asc,
  ArchiveCategory cat,
) {
  int cmp(ArchiveKey a, ArchiveKey b) {
    switch (sortKey) {
      case 'name':
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case 'type':
        return (a.protocol ?? '').compareTo(b.protocol ?? '');
      case 'uid':
        return (a.meta?['uid'] ?? '').compareTo(b.meta?['uid'] ?? '');
      case 'data':
        return (a.meta?['data'] ?? '').compareTo(b.meta?['data'] ?? '');
      case 'protocols':
        return (a.meta?['protocols'] ?? '')
            .compareTo(b.meta?['protocols'] ?? '');
      case 'signals':
        final ai = int.tryParse(a.meta?['signals'] ?? '') ?? 0;
        final bi = int.tryParse(b.meta?['signals'] ?? '') ?? 0;
        return ai.compareTo(bi);
      case 'frequency':
        final af = int.tryParse(a.meta?['frequency'] ?? '') ?? 0;
        final bf = int.tryParse(b.meta?['frequency'] ?? '') ?? 0;
        return af.compareTo(bf);
      case 'protocol':
        return (a.protocol ?? '').compareTo(b.protocol ?? '');
      case 'modulation':
        return (a.meta?['modulation'] ?? '')
            .compareTo(b.meta?['modulation'] ?? '');
      case 'kind':
        return (a.meta?['kind'] ?? '').compareTo(b.meta?['kind'] ?? '');
      case 'lines':
        final al = int.tryParse(a.meta?['lines'] ?? '') ?? 0;
        final bl = int.tryParse(b.meta?['lines'] ?? '') ?? 0;
        return al.compareTo(bl);
      case 'size':
        return a.localSize.compareTo(b.localSize);
      case 'mtime':
        final at = a.mtime;
        final bt = b.mtime;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      default:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
  }

  final out = [...keys];
  out.sort((a, b) => asc ? cmp(a, b) : cmp(b, a));
  return out;
}

// ── Formatters ────────────────────────────────────────────────────────────────

String _fmtSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}

String _fmtMtime(DateTime? dt) {
  if (dt == null) return '—';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}

// ── CategoryPage ──────────────────────────────────────────────────────────────

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

  // ── Data ──────────────────────────────────────────────────────────────────

  List<ArchiveKey> get _allKeys => _ctrl.keysFor(_cat);

  List<String> get _filterOptions {
    final opts = <String>{};
    for (final k in _allKeys) {
      final v = _filterValue(k);
      if (v != null && v.isNotEmpty) opts.add(v);
    }
    return opts.toList()..sort();
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
    }
  }

  List<ArchiveKey> get _filtered {
    var keys = _allKeys;
    if (_starredOnly) keys = keys.where((k) => k.favorite).toList();
    if (_filterVal != null) {
      keys = keys.where((k) => _filterValue(k) == _filterVal).toList();
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
    return _sortKeys(keys, _sortKey, _sortAsc, _cat);
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
        title: Text('Rename', style: TextStyle(color: colors.dialogText)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: colors.dialogText),
          decoration: InputDecoration(
            hintText: 'File name',
            hintStyle: TextStyle(color: colors.textMuted),
          ),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Rename')),
        ],
      ),
    );
    ctrl.dispose();
    if (newName != null && newName.isNotEmpty && newName != key.name) {
      await _ctrl.renameKey(key, newName);
    }
  }

  String _emptyTitle() {
    if (_starredOnly) return 'No starred ${_cat.title} keys';
    if (_filterVal != null) return 'No keys matching filter';
    if (_query.isNotEmpty) return 'No results for "$_query"';
    if (!_ctrl.isConnected) {
      return 'No ${_cat.title} keys\nConnect a Flipper to sync';
    }
    return 'No ${_cat.title} keys\nPull down to sync';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
          WidgetsBinding.instance
              .addPostFrameCallback((_) => setState(() => _filterVal = null));
        }

        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: catColor,
            foregroundColor: Colors.white,
            elevation: 0,
            titleSpacing: 0,
            title: _AppBarTitle(cat: _cat),
            actions: [
              _CountBadge(filtered: filtered.length, total: total),
              if (_ctrl.syncing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(50),
              child: _ToolbarRow(
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
              if (_ctrl.syncing)
                SyncProgressView(progress: _ctrl.syncProgress),
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final (visibleCols, nameW) =
                        _visibleCols(_cat, constraints.maxWidth);

                    return RefreshIndicator(
                      color: catColor,
                      onRefresh: () => _ctrl.syncCategory(_cat),
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
                                _ColumnHeader(
                                  cols: visibleCols,
                                  nameW: nameW,
                                  sortKey: _sortKey,
                                  sortAsc: _sortAsc,
                                  onSort: _onSort,
                                  colors: colors,
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    itemCount: filtered.length,
                                    itemBuilder: (_, i) {
                                      final key = filtered[i];
                                      return _TableRow(
                                        key: ValueKey(_keyId(key)),
                                        flipperKey: key,
                                        cols: visibleCols,
                                        nameW: nameW,
                                        colors: colors,
                                        cat: _cat,
                                        onTap: () =>
                                            _showKeyActions(context, key),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
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

  String _keyId(ArchiveKey k) =>
      '${k.category.flipperDir}/${k.subFolder.isEmpty ? '' : '${k.subFolder}/'}${k.name}.${k.extension}';

  Future<void> _confirmDelete(BuildContext ctx, ArchiveKey k) async {
    final colors = ctx.appColors;
    final connected = _ctrl.isConnected;
    final String msg;
    if (connected && k.onDevice && k.inLocal) {
      msg =
          'This file will be permanently deleted from the Flipper and this phone.';
    } else if (connected && k.onDevice) {
      msg = 'This file will be permanently deleted from the Flipper.';
    } else {
      msg = 'This local file will be permanently deleted.';
    }
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: colors.dialogBackground,
        title: Text('Delete ${k.name}?',
            style: TextStyle(color: colors.dialogText)),
        content:
            Text(msg, style: TextStyle(color: colors.dialogMuted, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Delete', style: TextStyle(color: colors.danger))),
        ],
      ),
    );
    if (ok == true) await _ctrl.deleteKey(k);
  }
}

// ── AppBar widgets ────────────────────────────────────────────────────────────

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({required this.cat});
  final ArchiveCategory cat;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SvgPicture.asset(
          cat.asset,
          width: 18,
          height: 18,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
        const SizedBox(width: 8),
        Text(cat.title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text(cat.remoteDir,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w400)),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.filtered, required this.total});
  final int filtered;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            filtered < total ? '$filtered/$total' : '$total',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _ToolbarRow extends StatelessWidget {
  const _ToolbarRow({
    required this.searchCtrl,
    required this.query,
    required this.filterVal,
    required this.filterOpts,
    required this.starredOnly,
    required this.catColor,
    required this.colors,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onStarredToggle,
  });

  final TextEditingController searchCtrl;
  final String query;
  final String? filterVal;
  final List<String> filterOpts;
  final bool starredOnly;
  final Color catColor;
  final QAppColors colors;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onFilterChanged;
  final VoidCallback onStarredToggle;

  static const double _h = 36;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: catColor,
      padding: const EdgeInsets.fromLTRB(10, 0, 8, 10),
      child: SizedBox(
        height: _h,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TextField(
                controller: searchCtrl,
                onChanged: onQueryChanged,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search…',
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: Colors.white.withValues(alpha: 0.65), size: 17),
                  suffixIcon: query.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: Colors.white.withValues(alpha: 0.65),
                              size: 15),
                          onPressed: () {
                            searchCtrl.clear();
                            onQueryChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.14),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1)),
                  isDense: true,
                ),
              ),
            ),
            if (filterOpts.isNotEmpty) ...[
              const SizedBox(width: 6),
              _FilterBtn(
                selected: filterVal,
                opts: filterOpts,
                catColor: catColor,
                colors: colors,
                onChanged: onFilterChanged,
              ),
            ],
            const SizedBox(width: 4),
            _StarBtn(active: starredOnly, onToggle: onStarredToggle),
          ],
        ),
      ),
    );
  }
}

class _FilterBtn extends StatelessWidget {
  const _FilterBtn({
    required this.selected,
    required this.opts,
    required this.catColor,
    required this.colors,
    required this.onChanged,
  });

  final String? selected;
  final List<String> opts;
  final Color catColor;
  final QAppColors colors;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = selected != null;
    return GestureDetector(
      onTap: () => _show(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.88)
              : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded,
                size: 14,
                color: active ? catColor : Colors.white.withValues(alpha: 0.8)),
            if (active) ...[
              const SizedBox(width: 4),
              Text(selected!,
                  style: TextStyle(
                      color: catColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }

  void _show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Filter',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            Divider(height: 1, color: colors.divider),
            ListTile(
              title:
                  Text('All', style: TextStyle(color: colors.textPrimary)),
              trailing: selected == null
                  ? Icon(Icons.check_rounded, color: catColor)
                  : null,
              onTap: () {
                Navigator.pop(context);
                onChanged(null);
              },
            ),
            for (final o in opts)
              ListTile(
                title: Text(o, style: TextStyle(color: colors.textPrimary)),
                trailing: selected == o
                    ? Icon(Icons.check_rounded, color: catColor)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  onChanged(o);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _StarBtn extends StatelessWidget {
  const _StarBtn({required this.active, required this.onToggle});
  final bool active;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.88)
                : Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            active ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 17,
            color: active
                ? Colors.amber.shade700
                : Colors.white.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

// ── Column header ─────────────────────────────────────────────────────────────

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({
    required this.cols,
    required this.nameW,
    required this.sortKey,
    required this.sortAsc,
    required this.onSort,
    required this.colors,
  });

  final List<_Col> cols;
  final double nameW;
  final String sortKey;
  final bool sortAsc;
  final ValueChanged<String> onSort;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _headerH,
      color: colors.card.withValues(alpha: 0.7),
      child: Row(
        children: [
          const SizedBox(width: 8),
          for (final col in cols)
            _HeaderCell(
              col: col,
              width: col.width == 0 ? nameW : col.width,
              active: sortKey == col.sortKey,
              asc: sortAsc,
              onSort: col.sortKey != null ? () => onSort(col.sortKey!) : null,
              colors: colors,
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.col,
    required this.width,
    required this.active,
    required this.asc,
    required this.onSort,
    required this.colors,
  });

  final _Col col;
  final double width;
  final bool active;
  final bool asc;
  final VoidCallback? onSort;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: active ? colors.textSecondary : colors.textMuted,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );

    Widget cell = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment:
          col.right ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Text(col.label.toUpperCase(), style: textStyle),
        if (active) ...[
          const SizedBox(width: 2),
          Icon(
            asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 10,
            color: colors.textSecondary,
          ),
        ],
      ],
    );

    if (onSort != null) {
      cell = GestureDetector(onTap: onSort, child: cell);
    }

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: col.right ? Alignment.centerRight : Alignment.centerLeft,
          child: cell,
        ),
      ),
    );
  }
}

// ── Table row ─────────────────────────────────────────────────────────────────

class _TableRow extends StatelessWidget {
  const _TableRow({
    super.key,
    required this.flipperKey,
    required this.cols,
    required this.nameW,
    required this.colors,
    required this.cat,
    required this.onTap,
  });

  final ArchiveKey flipperKey;
  final List<_Col> cols;
  final double nameW;
  final QAppColors colors;
  final ArchiveCategory cat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = flipperKey;
    return Material(
      color: colors.card,
      child: InkWell(
        onTap: onTap,
        splashColor: cat.color.withValues(alpha: 0.06),
        highlightColor: cat.color.withValues(alpha: 0.04),
        child: Container(
          height: _rowH,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.divider.withValues(alpha: 0.6)),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              for (final col in cols)
                SizedBox(
                  width: col.width == 0 ? nameW : col.width,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _cellContent(context, col, k),
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cellContent(BuildContext ctx, _Col col, ArchiveKey k) {
    if (col.width == 0) return _nameCell(k);
    switch (col.sortKey) {
      case 'type':
        return _textCell(k.protocol ?? '—');
      case 'uid':
        return _monoCell(k.meta?['uid'] ?? '—');
      case 'data':
        return _monoCell(k.meta?['data'] ?? '—');
      case 'signals':
        return _textCell(k.meta?['signals'] ?? '—', right: true);
      case 'protocols':
        return _textCell(k.meta?['protocols'] ?? '—');
      case 'frequency':
        final freq = k.meta?['frequency'];
        final hz = int.tryParse(freq ?? '');
        final label = hz != null
            ? '${(hz / 1000000).toStringAsFixed(3)} MHz'
            : (k.extra ?? '—');
        return _monoCell(label, right: true);
      case 'protocol':
        final proto = k.protocol;
        final hasRaw = k.meta?['has_raw'] == '1';
        if (proto == null) return _textCell('—');
        return Row(
          children: [
            Flexible(
                child: Text(proto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: colors.textSecondary, fontSize: 12))),
            if (hasRaw && proto != 'RAW') ...[
              const SizedBox(width: 4),
              Text('(raw)',
                  style: TextStyle(color: colors.textMuted, fontSize: 10)),
            ],
          ],
        );
      case 'modulation':
        return _textCell(k.meta?['modulation'] ?? '—');
      case 'kind':
        return _textCell(k.meta?['kind'] ?? '—');
      case 'lines':
        return _textCell(k.meta?['lines'] ?? '—', right: true);
      case 'size':
        return _textCell(_fmtSize(k.localSize), right: true, muted: true);
      case 'mtime':
        return _textCell(_fmtMtime(k.mtime), right: true, muted: true);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _nameCell(ArchiveKey k) {
    final relDir = k.subFolder.isEmpty ? '/' : '/${k.subFolder}/';
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cat.color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(7),
          ),
          child: SvgPicture.asset(
            cat.asset,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(cat.color, BlendMode.srcIn),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                k.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
              Text(
                relDir,
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

  Widget _textCell(String text, {bool right = false, bool muted = false}) {
    return Align(
      alignment: right ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: muted ? colors.textMuted : colors.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _monoCell(String text, {bool right = false}) {
    return Align(
      alignment: right ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 11,
          fontFamily: 'monospace',
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── DeletedPage ───────────────────────────────────────────────────────────────

class DeletedPage extends StatelessWidget {
  const DeletedPage({super.key, required this.controller});

  final ArchiveController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final keys = controller.deletedKeys();
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            title: const Text('Deleted'),
          ),
          body: keys.isEmpty
              ? const ArchiveEmptyView(
                  icon: Icons.delete_outline,
                  title: 'Nothing here',
                  subtitle:
                      'Deleted keys are kept on this device until purged',
                )
              : RefreshIndicator(
                  color: colors.accent,
                  onRefresh: controller.refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: keys.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => KeyCard(
                      flipperKey: keys[i],
                      onTap: () =>
                          KeyActionsSheet.show(context, controller, keys[i]),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
