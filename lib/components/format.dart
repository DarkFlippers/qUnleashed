/// Threshold byte-size label: `512 B`, `1.5 KB`, `2.0 MB`, `1.25 GB`.
///
/// [space] drops the separator for compact tables, [gigabytes] stops scaling at
/// megabytes.
String formatBytes(int bytes, {bool space = true, bool gigabytes = true}) {
  final sep = space ? ' ' : '';
  if (bytes < 1024) return '$bytes${sep}B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)}${sep}KB';
  }
  if (!gigabytes || bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}${sep}MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}${sep}GB';
}

const List<String> _scaledUnits = ['B', 'KB', 'MB', 'GB', 'TB'];

/// Scaling byte-size label that drops the fraction once the value gets large:
/// `512 B`, `1.5 KB`, `150 KB`.
///
/// [maxUnit] is the highest index in `B, KB, MB, GB, TB` the value may reach,
/// [coarseAt] the value from which the fraction is dropped, and
/// [topUnitPrecision] overrides the digit count once [maxUnit] is reached.
String formatBytesScaled(
  int bytes, {
  int maxUnit = 3,
  int coarseAt = 10,
  int? topUnitPrecision,
}) {
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < maxUnit) {
    value /= 1024;
    unit++;
  }
  final precision = unit == maxUnit && topUnitPrecision != null
      ? topUnitPrecision
      : (value >= coarseAt || unit == 0 ? 0 : 1);
  return '${value.toStringAsFixed(precision)} ${_scaledUnits[unit]}';
}

/// Relative "time ago" label for a modification time, e.g. `now`, `5m ago`,
/// `yesterday`, `3w ago`. Returns `—` when [dt] is null.
String fmtMtime(DateTime? dt) {
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
