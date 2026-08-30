import '../../services/localization/l10n.dart';
import '../format.dart';
import '../archive/category.dart';
import '../archive/models/key.dart';

class ArchiveCol {
  const ArchiveCol(
    this.label,
    this.width, {
    this.sortKey,
    this.right = false,
    this.hideLevel,
  });

  final String label;
  final double width;
  final String? sortKey;
  final bool right;
  final int? hideLevel;
}

typedef SizedColumn = ({ArchiveCol col, double width});

const double kNameMinWidth = 140;
const double kRowHeight = 48;
const double kHeaderHeight = 34;

/// Single column set for the unified "Deleted" table, which mixes files from
/// every category. Keeps only fields common to all of them: name/folder (with a
/// per-row category icon), the parsed protocol/type, size and modified time.
List<ArchiveCol> deletedColumns() {
  final s = l10n;
  return [
    ArchiveCol(s.colNameFolder, 0, sortKey: 'name'),
    ArchiveCol(s.colProtocol, 150, sortKey: 'protocol', hideLevel: 3),
    ArchiveCol(s.colSize, 68, sortKey: 'size', right: true, hideLevel: 1),
    ArchiveCol(s.colModified, 88, sortKey: 'mtime', right: true, hideLevel: 2),
  ];
}

List<ArchiveCol> columnsFor(ArchiveCategory cat) {
  final s = l10n;
  switch (cat) {
    case ArchiveCategory.nfc:
      return [
        ArchiveCol(s.colNameFolder, 0, sortKey: 'name'),
        ArchiveCol(s.colType, 140, sortKey: 'type'),
        ArchiveCol('UID', 190, sortKey: 'uid', hideLevel: 2),
        ArchiveCol(s.colSize, 68, sortKey: 'size', right: true, hideLevel: 1),
        ArchiveCol(
          s.colModified,
          88,
          sortKey: 'mtime',
          right: true,
          hideLevel: 3,
        ),
      ];
    case ArchiveCategory.rfid:
      return [
        ArchiveCol(s.colKeyFolder, 0, sortKey: 'name'),
        ArchiveCol(s.colType, 120, sortKey: 'type'),
        ArchiveCol(s.colData, 190, sortKey: 'data', hideLevel: 2),
        ArchiveCol(s.colSize, 68, sortKey: 'size', right: true, hideLevel: 1),
        ArchiveCol(
          s.colModified,
          88,
          sortKey: 'mtime',
          right: true,
          hideLevel: 3,
        ),
      ];
    case ArchiveCategory.infrared:
      return [
        ArchiveCol(s.colRemoteFolder, 0, sortKey: 'name'),
        ArchiveCol(s.colSignals, 72, sortKey: 'signals', right: true),
        ArchiveCol(s.colProtocols, 170, sortKey: 'protocols', hideLevel: 2),
        ArchiveCol(
          s.colModified,
          88,
          sortKey: 'mtime',
          right: true,
          hideLevel: 3,
        ),
      ];
    case ArchiveCategory.subghz:
    case ArchiveCategory.wardriving:
      return [
        ArchiveCol(s.colNameFolder, 0, sortKey: 'name'),
        ArchiveCol(s.colFrequency, 104, sortKey: 'frequency', right: true),
        ArchiveCol(s.colProtocol, 120, sortKey: 'protocol'),
        ArchiveCol(s.colPreset, 100, hideLevel: 2),
        ArchiveCol(s.colModulation, 56, sortKey: 'modulation', hideLevel: 1),
        ArchiveCol(
          s.colModified,
          88,
          sortKey: 'mtime',
          right: true,
          hideLevel: 3,
        ),
      ];
    case ArchiveCategory.ibutton:
      return [
        ArchiveCol(s.colKeyFolder, 0, sortKey: 'name'),
        ArchiveCol(s.colType, 120, sortKey: 'type'),
        ArchiveCol(s.colSize, 68, sortKey: 'size', right: true, hideLevel: 1),
        ArchiveCol(
          s.colModified,
          88,
          sortKey: 'mtime',
          right: true,
          hideLevel: 3,
        ),
      ];
    case ArchiveCategory.badusb:
      return [
        ArchiveCol(s.colScriptFolder, 0, sortKey: 'name'),
        ArchiveCol(s.colKind, 76, sortKey: 'kind'),
        ArchiveCol(s.colLines, 60, sortKey: 'lines', right: true, hideLevel: 2),
        ArchiveCol(s.colSize, 68, sortKey: 'size', right: true, hideLevel: 1),
        ArchiveCol(
          s.colModified,
          88,
          sortKey: 'mtime',
          right: true,
          hideLevel: 3,
        ),
      ];
    case ArchiveCategory.javascript:
      return [
        ArchiveCol(s.colScriptFolder, 0, sortKey: 'name'),
        ArchiveCol(s.colSize, 68, sortKey: 'size', right: true, hideLevel: 1),
        ArchiveCol(
          s.colModified,
          88,
          sortKey: 'mtime',
          right: true,
          hideLevel: 3,
        ),
      ];
  }
}

String columnValue(ArchiveCol col, ArchiveKey k) {
  switch (col.sortKey) {
    case 'type':
      return k.protocol ?? '—';
    case 'uid':
      return k.meta?['uid'] ?? '—';
    case 'data':
      return k.meta?['data'] ?? '—';
    case 'signals':
      return k.meta?['signals'] ?? '—';
    case 'protocols':
      return k.meta?['protocols'] ?? '—';
    case 'frequency':
      final hz = int.tryParse(k.meta?['frequency'] ?? '');
      return hz != null
          ? '${(hz / 1000000).toStringAsFixed(3)} MHz'
          : (k.extra ?? '—');
    case 'protocol':
      final proto = k.protocol;
      if (proto == null) return '—';
      final hasRaw = k.meta?['has_raw'] == '1';
      return hasRaw && proto != 'RAW' ? '$proto (raw)' : proto;
    case 'modulation':
      return k.meta?['modulation'] ?? '—';
    case 'kind':
      return k.meta?['kind'] ?? '—';
    case 'lines':
      return k.meta?['lines'] ?? '—';
    case 'size':
      return formatBytes(k.localSize, space: false, gigabytes: false);
    case 'mtime':
      return fmtMtime(k.mtime);
    default:
      return '';
  }
}

double _requiredWidth(ArchiveCol col, List<ArchiveKey> keys) {
  final mono = col.sortKey == 'uid' || col.sortKey == 'data';
  final charW = mono ? 6.9 : 7.2;
  var contentW = 0.0;
  for (final k in keys) {
    final w = (columnValue(col, k).length + 1) * charW;
    if (w > contentW) contentW = w;
  }
  final labelW = col.label.length * 6.6 + 20;
  final needed = (contentW > labelW ? contentW : labelW) + 8;
  return needed < col.width ? needed : col.width;
}

List<SizedColumn> visibleColumns(
  ArchiveCategory cat,
  double availableWidth,
  List<ArchiveKey> keys,
) => layoutColumns(columnsFor(cat), availableWidth, keys);

/// Resolves the visible subset of [all] and their widths for [availableWidth],
/// progressively hiding higher [ArchiveCol.hideLevel] columns until the name
/// column fits. Shared by the per-category and unified deleted tables.
List<SizedColumn> layoutColumns(
  List<ArchiveCol> all,
  double availableWidth,
  List<ArchiveKey> keys,
) {
  final req = <ArchiveCol, double>{
    for (final c in all)
      if (c.width > 0) c: _requiredWidth(c, keys),
  };

  List<SizedColumn> sized(List<ArchiveCol> visible, double nameW) => [
    for (final c in visible) (col: c, width: c.width == 0 ? nameW : req[c]!),
  ];

  for (var level = 0; level <= 3; level++) {
    final visible = all
        .where((c) => c.hideLevel == null || c.hideLevel! > level)
        .toList();
    final fixed = visible
        .where((c) => c.width > 0)
        .fold(0.0, (s, c) => s + req[c]!);
    final nameW = availableWidth - fixed - 16;
    if (nameW >= kNameMinWidth) return sized(visible, nameW);
  }

  final core = all.where((c) => c.hideLevel == null).toList();
  final fixed = core.where((c) => c.width > 0).fold(0.0, (s, c) => s + req[c]!);
  final nameW = (availableWidth - fixed - 16).clamp(
    kNameMinWidth,
    double.infinity,
  );
  return sized(core, nameW);
}
