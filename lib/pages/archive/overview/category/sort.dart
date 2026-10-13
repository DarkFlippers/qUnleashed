import '../../../../components/archive/models/key.dart';
import '../../../../components/filelist/folder_sort.dart';

/// Returns a new list of [keys] sorted by [sortKey], ascending when [asc].
/// Numeric meta fields fall back to 0 and text fields to the empty string.
List<ArchiveKey> sortArchiveKeys(
  List<ArchiveKey> keys,
  String sortKey,
  bool asc,
) {
  if (sortKey == 'folder') return _byFolder(keys, asc);

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

/// Groups [keys] by the folder they live in, and orders each folder's files by
/// name. The folders are the only categories a Flipper's archive has once a
/// collection the size of Flipper-IRDB is on it, and sorting by name alone
/// scatters every one of them. #122
///
/// The comparison keys are built once per file rather than inside the
/// comparator, which is where the `name` sort above still lowercases. This one
/// would have more to repeat - a lowercase, a `replaceAll` and the join before
/// them, on both sides of every comparison - and it runs against a list of the
/// order of ten thousand entries on a Flipper carrying a full Flipper-IRDB,
/// inside the `AnimatedBuilder` that the archive controller notifies at least
/// twice per file, and again on every throttled progress tick, for the length
/// of a sync.
List<ArchiveKey> _byFolder(List<ArchiveKey> keys, bool asc) {
  final rows = [
    for (final k in keys)
      (
        key: k,
        folder: folderSortKey(
          k.subFolder.isEmpty ? k.flipperDir : '${k.flipperDir}/${k.subFolder}',
        ),
        name: k.name.toLowerCase(),
      ),
  ];
  rows.sort(
    (a, b) => compareFolderThenName(a.folder, a.name, b.folder, b.name, asc),
  );
  return [for (final r in rows) r.key];
}
