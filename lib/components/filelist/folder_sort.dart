/// Ordering files by the folder they live in, for the tables in this layer.
///
/// Here rather than beside `sortArchiveKeys` because none of it is about an
/// archive key. The archive's own sort uses it, the favourite apps beside
/// those keys use it, and the apps-manager tables have the same folder column
/// and the same defect waiting in their own comparator.
library;

/// Lowercases a directory path and swaps its separators for NUL, so that a
/// folder and everything under it compare as one unbroken run.
///
/// `/` does not manage that on its own. It is 0x2F, and the space, `!`, `&`,
/// `-` and `.` that Flipper folder names are full of all sort below it, so a
/// sibling whose name merely starts with a shorter folder's lands inside that
/// folder's subtree: `Flipper-IRDB/TV`, `Flipper-IRDB/TV Shows` and
/// `Flipper-IRDB/TV/Sony` compare in exactly that order, putting the sibling
/// between `TV`'s own files and `TV`'s own subfolder. Splitting the path into
/// segments would fix it too, and the archive's `_byFolder` hoists key
/// building out of the comparator so it would cost a list per file rather
/// than per comparison - but a string key is one allocation and one
/// `compareTo` where a segment list is N+1 and a loop. NUL cannot appear in a
/// file name, so it sorts below every character that can.
String folderSortKey(String path) =>
    path.toLowerCase().replaceAll('/', '\u0000');

/// Orders one file against another by the folder it lives in, then by name.
/// Both folders have been through [folderSortKey] and both names are already
/// lowercased.
///
/// [asc] turns the folders around and leaves the names alone - `ORDER BY
/// folder DESC, name ASC`. The name is a tiebreak rather than a field the user
/// picked a direction for, and reversing it too would hand back every folder's
/// contents backwards for no reason anybody asked for.
///
/// Takes four strings rather than two files because the lists that sort this
/// way share no type and are not going to: an archive key has a category
/// directory under it, a starred app is whatever sits under `/ext/apps`. The
/// rule is the part worth keeping in one place, and a generic over a pair of
/// accessors would be more machinery than the rule it carries.
int compareFolderThenName(
  String folderA,
  String nameA,
  String folderB,
  String nameB,
  bool asc,
) {
  final byFolder = folderA.compareTo(folderB);
  if (byFolder != 0) return asc ? byFolder : -byFolder;
  return nameA.compareTo(nameB);
}
