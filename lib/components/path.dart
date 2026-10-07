import 'dart:io' as io;

/// Joins [parts] with the host path separator, skipping empty segments.
String pathJoin(Iterable<String> parts) {
  final sep = io.Platform.pathSeparator;
  final out = <String>[];
  for (final raw in parts) {
    if (raw.isEmpty) continue;
    out.add(raw);
  }
  return out.join(sep);
}

/// The characters a name may not carry, written down once.
///
/// Both of this app's naming rules read it: [sanitizePathSegment] replaces
/// them for a host path, and `SeedSubFile.checkBaseName` reports them for a
/// path on the Flipper. They are the nine Windows reserves, which are also the
/// nine a FAT volume cannot hold — so the two rules were one set spelled
/// twice, in two files, and then a third time as prose in every locale's ARB.
/// #266
///
/// Order is the order the ARB string listed them in, because
/// [reservedNameCharsSpelled] is what the user is shown.
const reservedNameChars = r'\/:*?"<>|';

/// [reservedNameChars] as a list to show a user: `\ / : * ? " < > |`.
///
/// Derived rather than typed into a translatable string. The ARB spelled the
/// nine out in prose, in three locales, with nothing checking any of them
/// against the regex — so a tenth character meant remembering two regexes and
/// three sentences, two of which are in languages this repository may not
/// hand-edit.
final reservedNameCharsSpelled = reservedNameChars.split('').join(' ');

/// [reservedNameChars] plus the C0 range and DEL, as one character class.
///
/// The control characters are here rather than only in the device rule because
/// a host file name cannot carry them either: on Windows the write fails with
/// a bare "invalid argument", and on a POSIX host it produces a name nothing
/// can quote. They were refused on the one device path and let through on all
/// nine host ones, which is the half of #266 worth having on its own.
///
/// Built from [reservedNameChars] rather than typed again. Only a backslash
/// needs escaping inside a class; `test/reserved_name_chars_test.dart` walks
/// every code unit below 0x80 against the constant, so a later addition that
/// *does* need escaping — a `]`, a `-` that would open a range — fails there
/// rather than quietly widening or narrowing what this matches.
final reservedNameCharsPattern = RegExp(
  '[\\x00-\\x1f\\x7f${reservedNameChars.replaceAll(r'\', r'\\')}]',
);

/// Replaces the characters a host path segment may not carry with `_`.
String sanitizePathSegment(String input) {
  return input.replaceAll(reservedNameCharsPattern, '_').trim();
}

/// Resolves an archive entry name under [rootPath]. Returns `null` when the
/// entry would escape it, and equally when cleaning leaves nothing to write
/// (`''`, `'/'`, `'./.'`) — callers skip both cases alike.
///
/// Entry names come out of an archive downloaded from somewhere else, so a
/// `..` segment is a hostile entry rather than a path to repair: it is refused
/// instead of being normalized away. A Windows drive prefix is not a
/// separator and survives splitting, so `C:` is defused by
/// [sanitizePathSegment] into a plain `C_` rather than reaching another volume.
///
/// The containment check is lexical: it does not resolve symlinks, so a caller
/// that turns entries into links can still escape [rootPath].
String? resolveArchivePath(
  String rootPath,
  String entryName, {
  String? separator,
}) {
  final segments = <String>[];
  for (final raw in entryName.split(RegExp(r'[/\\]'))) {
    final part = raw.trim();
    if (part.isEmpty || part == '.') continue;
    if (part == '..') return null;
    segments.add(sanitizePathSegment(part));
  }
  if (segments.isEmpty) return null;
  return [rootPath, ...segments].join(separator ?? io.Platform.pathSeparator);
}

/// Resolves an archive entry that sits inside a single wrapper folder — the
/// shape GitHub's source archives come in — under [rootPath].
///
/// The wrapper is whatever the first segment happens to be rather than a name
/// worth checking, so it is stripped and an entry sitting beside it at the
/// archive root is skipped. Containment is [resolveArchivePath]'s.
String? resolveWrappedArchivePath(
  String rootPath,
  String entryName, {
  String? separator,
}) {
  final name = entryName.replaceAll('\\', '/');
  final slash = name.indexOf('/');
  if (slash < 0) return null;
  return resolveArchivePath(
    rootPath,
    name.substring(slash + 1),
    separator: separator,
  );
}

/// Last segment of a `/`-separated path, e.g. `/ext/apps/foo.fap` -> `foo.fap`.
String basename(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}

/// Everything before the last `/`, empty when the path has no directory part.
String dirname(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}
