import 'package:flutter/material.dart';

import '../../../services/localization/l10n.dart';
import '../../../components/format.dart';
import '../../../theme/theme.dart';
import 'controller.dart';
import 'widgets/file_type.dart';

class FileCol {
  const FileCol(
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

typedef SizedFileCol = ({FileCol col, double width});

Color fileBarColor(QAppColors colors) => colors.card.withValues(alpha: 0.7);

const double kFileNameMinWidth = 130;
const double kFileRowHeight = 48;
const double kFileHeaderHeight = 34;
const double kFileSelectionWidth = 26;
const double kFileTrailingWidth = 36;

List<FileCol> fileColumns() {
  final s = l10n;
  return [
    FileCol(s.colNameFolder, 0, sortKey: 'name'),
    FileCol(s.colType, 130, sortKey: 'type'),
    FileCol(s.colSize, 76, sortKey: 'size', right: true, hideLevel: 1),
  ];
}

String fileColumnValue(FileCol col, RemoteEntry e) {
  switch (col.sortKey) {
    case 'type':
      return fileTypeLabel(e);
    case 'size':
      return e.isDir
          ? '—'
          : formatBytes(e.size, space: false, gigabytes: false);
    default:
      return '';
  }
}

double _requiredWidth(FileCol col, List<RemoteEntry> entries) {
  var contentW = 0.0;
  for (final e in entries) {
    final w = (fileColumnValue(col, e).length + 1) * 7.2;
    if (w > contentW) contentW = w;
  }
  final labelW = col.label.length * 6.6 + 20;
  final needed = (contentW > labelW ? contentW : labelW) + 8;
  return needed < col.width ? needed : col.width;
}

List<SizedFileCol> layoutFileColumns(
  List<FileCol> all,
  double availableWidth,
  List<RemoteEntry> entries,
) {
  final req = <FileCol, double>{
    for (final c in all)
      if (c.width > 0) c: _requiredWidth(c, entries),
  };

  List<SizedFileCol> sized(List<FileCol> visible, double nameW) => [
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
    if (nameW >= kFileNameMinWidth) return sized(visible, nameW);
  }

  final core = all.where((c) => c.hideLevel == null).toList();
  final fixed = core.where((c) => c.width > 0).fold(0.0, (s, c) => s + req[c]!);
  final nameW = (availableWidth - fixed - 16).clamp(
    kFileNameMinWidth,
    double.infinity,
  );
  return sized(core, nameW);
}
