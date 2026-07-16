import '../../data/category.dart';
import '../../data/models/key.dart';
import '../format.dart';

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

List<ArchiveCol> columnsFor(ArchiveCategory cat) {
  switch (cat) {
    case ArchiveCategory.nfc:
      return const [
        ArchiveCol('Name / Folder', 0, sortKey: 'name'),
        ArchiveCol('Type', 140, sortKey: 'type'),
        ArchiveCol('UID', 190, sortKey: 'uid', hideLevel: 2),
        ArchiveCol('Size', 68, sortKey: 'size', right: true, hideLevel: 1),
        ArchiveCol('Modified', 88, sortKey: 'mtime', right: true, hideLevel: 3),
      ];
    case ArchiveCategory.rfid:
      return const [
        ArchiveCol('Key / Folder', 0, sortKey: 'name'),
        ArchiveCol('Type', 120, sortKey: 'type'),
        ArchiveCol('Data', 190, sortKey: 'data', hideLevel: 2),
        ArchiveCol('Size', 68, sortKey: 'size', right: true, hideLevel: 1),
        ArchiveCol('Modified', 88, sortKey: 'mtime', right: true, hideLevel: 3),
      ];
    case ArchiveCategory.infrared:
      return const [
        ArchiveCol('Remote / Folder', 0, sortKey: 'name'),
        ArchiveCol('Signals', 72, sortKey: 'signals', right: true),
        ArchiveCol('Protocols', 170, sortKey: 'protocols', hideLevel: 2),
        ArchiveCol('Modified', 88, sortKey: 'mtime', right: true, hideLevel: 3),
      ];
    case ArchiveCategory.subghz:
    case ArchiveCategory.wardriving:
      return const [
        ArchiveCol('Name / Folder', 0, sortKey: 'name'),
        ArchiveCol('Frequency', 104, sortKey: 'frequency', right: true),
        ArchiveCol('Protocol', 120, sortKey: 'protocol'),
        ArchiveCol('Preset', 100, hideLevel: 2),
        ArchiveCol('Mod', 56, sortKey: 'modulation', hideLevel: 1),
        ArchiveCol('Modified', 88, sortKey: 'mtime', right: true, hideLevel: 3),
      ];
    case ArchiveCategory.ibutton:
      return const [
        ArchiveCol('Key / Folder', 0, sortKey: 'name'),
        ArchiveCol('Type', 120, sortKey: 'type'),
        ArchiveCol('Size', 68, sortKey: 'size', right: true, hideLevel: 1),
        ArchiveCol('Modified', 88, sortKey: 'mtime', right: true, hideLevel: 3),
      ];
    case ArchiveCategory.badusb:
      return const [
        ArchiveCol('Script / Folder', 0, sortKey: 'name'),
        ArchiveCol('Kind', 76, sortKey: 'kind'),
        ArchiveCol('Lines', 60, sortKey: 'lines', right: true, hideLevel: 2),
        ArchiveCol('Size', 68, sortKey: 'size', right: true, hideLevel: 1),
        ArchiveCol('Modified', 88, sortKey: 'mtime', right: true, hideLevel: 3),
      ];
    case ArchiveCategory.javascript:
      return const [
        ArchiveCol('Script / Folder', 0, sortKey: 'name'),
        ArchiveCol('Size', 68, sortKey: 'size', right: true, hideLevel: 1),
        ArchiveCol('Modified', 88, sortKey: 'mtime', right: true, hideLevel: 3),
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
      return fmtSize(k.localSize);
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
) {
  final all = columnsFor(cat);
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
  final fixed = core
      .where((c) => c.width > 0)
      .fold(0.0, (s, c) => s + req[c]!);
  final nameW = (availableWidth - fixed - 16).clamp(
    kNameMinWidth,
    double.infinity,
  );
  return sized(core, nameW);
}
