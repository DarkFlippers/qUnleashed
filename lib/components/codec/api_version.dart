/// Firmware API version helpers shared by the catalog and the `.fap` checks.
(int, int)? parseApi(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final parts = raw.split('.');
  final major = int.tryParse(parts[0]);
  if (major == null) return null;
  final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return (major, minor);
}

int compareApi((int, int) a, (int, int) b) {
  if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
  return a.$2.compareTo(b.$2);
}
