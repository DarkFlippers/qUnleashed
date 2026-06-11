import '../../../models/category.dart';

/// A single column in the category table view.
class ArchiveCol {
  const ArchiveCol(
    this.label,
    this.width, {
    this.sortKey,
    this.right = false,
    this.hideLevel,
  });

  final String label;

  /// Fixed width in logical pixels, or 0 for the flexible name column.
  final double width;
  final String? sortKey;
  final bool right;

  /// Progressive hide priority when space is tight: 1 = size, 2 = uid/detail,
  /// 3 = mtime. Null means the column is never hidden.
  final int? hideLevel;
}

const double kNameMinWidth = 140;
const double kRowHeight = 48;
const double kHeaderHeight = 34;

/// Full column set for [cat], in display order.
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

/// Returns the subset of columns that fit in [availableWidth] by progressively
/// hiding columns in hideLevel order (1→size, 2→uid/detail, 3→mtime), together
/// with the resolved width of the flexible name column.
(List<ArchiveCol>, double) visibleColumns(
  ArchiveCategory cat,
  double availableWidth,
) {
  final all = columnsFor(cat);
  for (int level = 0; level <= 3; level++) {
    final visible = all
        .where((c) => c.hideLevel == null || c.hideLevel! > level)
        .toList();
    final fixed =
        visible.where((c) => c.width > 0).fold(0.0, (s, c) => s + c.width);
    final nameW = availableWidth - fixed - 16;
    if (nameW >= kNameMinWidth) return (visible, nameW);
  }
  // Fallback: show only non-hideable columns and give name the remaining space.
  final core = all.where((c) => c.hideLevel == null).toList();
  final fixed = core.where((c) => c.width > 0).fold(0.0, (s, c) => s + c.width);
  return (
    core,
    (availableWidth - fixed - 16).clamp(kNameMinWidth, double.infinity)
  );
}
