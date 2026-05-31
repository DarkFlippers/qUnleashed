import '../models/key.dart';

/// Returns a new list of [keys] sorted by [sortKey], ascending when [asc].
/// Numeric meta fields fall back to 0 and text fields to the empty string.
List<ArchiveKey> sortArchiveKeys(
  List<ArchiveKey> keys,
  String sortKey,
  bool asc,
) {
  int meta(ArchiveKey k, String field) =>
      int.tryParse(k.meta?[field] ?? '') ?? 0;
  String text(ArchiveKey k, String field) => k.meta?[field] ?? '';

  int cmp(ArchiveKey a, ArchiveKey b) {
    switch (sortKey) {
      case 'name':
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case 'type':
      case 'protocol':
        return (a.protocol ?? '').compareTo(b.protocol ?? '');
      case 'uid':
      case 'data':
      case 'protocols':
      case 'modulation':
      case 'kind':
        return text(a, sortKey).compareTo(text(b, sortKey));
      case 'signals':
      case 'frequency':
      case 'lines':
        return meta(a, sortKey).compareTo(meta(b, sortKey));
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
