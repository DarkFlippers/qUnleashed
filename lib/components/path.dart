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

/// Strips characters no filesystem accepts in a single path segment.
String sanitizePathSegment(String input) {
  return input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
}

/// Resolves an archive entry name under [rootPath], or `null` when the entry
/// would land outside it.
///
/// Entry names come out of an archive downloaded from somewhere else, so a
/// `..` segment is a hostile entry rather than a path to repair: it is refused
/// instead of being normalized away, and the caller skips the entry. Absolute
/// names are read as relative to [rootPath], since a leading separator only
/// ever means the archive was packed from the filesystem root. Everything that
/// survives goes through [sanitizePathSegment], so an entry that is merely
/// illegal on Windows still unpacks.
///
/// [separator] defaults to the host separator; an isolate that already carries
/// one in its spawn arguments passes it instead.
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
    final safe = sanitizePathSegment(part);
    if (safe.isEmpty) continue;
    segments.add(safe);
  }
  if (segments.isEmpty) return null;
  return [rootPath, ...segments].join(separator ?? io.Platform.pathSeparator);
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
