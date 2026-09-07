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

/// Replaces the characters Windows rejects in a path segment with `_`.
String sanitizePathSegment(String input) {
  return input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
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
