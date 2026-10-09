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
/// Two rules read it: [sanitizePathSegment] replaces them for a host path, and
/// `SeedSubFile.checkBaseName` reports them for a path on the Flipper. They
/// are the nine Windows reserves, and a single path segment cannot carry any
/// of them on the Flipper either — so the two rules were one set spelled
/// twice, in two files, with the English ARB sentence spelling it a third
/// time and nothing checking any of the three against each other. #266
///
/// "Cannot carry" is the volume's rule here: `create_name` in
/// `lib/fatfs/ff.c` rejects seven of the nine plus DEL, while `/` and `\`
/// break the segment instead of being rejected. The RPC layer above it
/// refuses eight of them too, which is [isNonAsciiNameChar]'s subject rather
/// than this one's.
///
/// Not every naming rule in the app: the paint editor's `_sanitizeName`
/// refuses far more and then collapses runs of `_`, which makes it a
/// different rule rather than a copy of this one.
///
/// Order is the order the ARB string listed them in, because
/// [reservedNameCharsSpelled] is what the user is shown.
const reservedNameChars = r'\/:*?"<>|';

/// [reservedNameChars] as a list to show a user: `\ / : * ? " < > |`.
///
/// Derived rather than typed into a translatable string, so that adding a
/// tenth character cannot leave the sentence behind.
///
/// It lists only the nine. [reservedNameCharsPattern] also refuses the control
/// range, which this cannot say — a name is refused for a control character
/// through its own message rather than this list. See `SeedNameProblem`.
final reservedNameCharsSpelled = reservedNameChars.split('').join(' ');

/// [reservedNameChars] plus the C0 range and DEL, as one character class.
///
/// The control range is here rather than only in the device rule because these
/// segments are machine-supplied — release tags, app folder names, device
/// names — so a control character in one means something upstream is wrong,
/// and `_` is the answer that keeps the path writable on every host. Windows
/// refuses such a name outright; a POSIX host accepts it and then nothing can
/// comfortably quote it. The device rule already refused them and the eleven
/// host call sites let them through, which is the half of #266 worth having
/// on its own.
///
/// Built from [reservedNameChars] rather than typed again, escaped per
/// character so that a `]`, `^` or `$` added to the set needs no thought. A
/// `-` is the one addition `RegExp.escape` leaves alone, and in a non-final
/// position it would open a range: `test/reserved_name_chars_test.dart` walks
/// every code unit below 0x80 against the constant, which is what catches that.
final reservedNameCharsPattern = RegExp(
  '[\\x00-\\x1f\\x7f'
  '${reservedNameChars.split('').map(RegExp.escape).join()}]',
);

/// Whether [unit] is a character no name may carry and
/// [reservedNameCharsSpelled] cannot name: a C0 control, or DEL.
///
/// [reservedNameCharsPattern] refuses these as well. This exists beside it so
/// that a rule reporting a problem to a user can tell the two apart and say
/// something they can act on — "a name cannot contain \ / : * ? " < > |" names
/// nothing a user who pasted a newline typed.
///
/// `test/reserved_name_chars_test.dart` holds the two spellings of the range
/// to each other, since the pattern writes it as `\x00-\x1f\x7f` and this
/// writes it in Dart.
bool isControlNameChar(int unit) => unit <= 0x1f || unit == 0x7f;

/// Whether [unit] is outside ASCII, which a path on the **Flipper** may not
/// carry and a path on the host may.
///
/// Not part of [reservedNameCharsPattern], and deliberately not applied by
/// [sanitizePathSegment]: a host filename holds a Cyrillic letter perfectly
/// well, and replacing one with `_` would mangle names this app has no reason
/// to touch. The device is the one with the rule.
///
/// The rule is `path_contains_only_ascii` in the firmware's
/// `lib/toolbox/path.c`, which takes the segment after the last `/` and
/// refuses any byte outside `0x20`-`0x7e` — **and** the eight characters
/// `\<>*|":?`, which is [reservedNameChars] minus the `/` it has already
/// split on. So that one function owns both halves of what a name may not
/// carry, and the nine are refused at this layer as well as by the volume.
/// Only the charset half is new here; the nine were already refused.
///
/// `rpc_storage.c` calls it and answers `ERROR_STORAGE_INVALID_NAME` for a
/// Write, a Mkdir, a Rename (on `new_path` only - so a name that reached the
/// card by other means can be renamed *away* from) and a TarExtract (on
/// `out_path` only). Two read paths use it to drop rather than to fail: the
/// List filter, so such a file is not listed at all, and
/// `rpc_system_storage_is_dir_is_empty`, which makes a directory holding
/// nothing else report itself empty. A Stat does *not* check - it goes
/// straight to `storage_common_stat` - so one of these paths does stat
/// successfully. #282
///
/// Function names and not line numbers, here and below: the firmware is not
/// vendored and not a submodule, so a `:NNN` cannot be checked by anything in
/// CI and is wrong at the next release while still reading as precise.
///
/// A code unit rather than a byte, which is the same test: a string has a
/// code unit above `0x7f` exactly when its UTF-8 has a byte above `0x7f`.
/// Both halves of a surrogate pair are above it, so an emoji is caught by
/// either spelling. Nothing can hand either predicate a value above `0xffff`,
/// because the only caller walks `codeUnits` and those are UTF-16.
///
/// What this is *not* about is FatFS, which would take such a name: the
/// firmware sets `_LFN_UNICODE 0` and `_CODE_PAGE 850`, and the CP850 table
/// in `lib/fatfs/option/ccsbcs.c` maps all 128 high bytes injectively, so the
/// volume both accepts one and reads it back unchanged. The refusal is the RPC
/// layer's, one above the volume, and it is the only layer this app talks to.
bool isNonAsciiNameChar(int unit) => unit > 0x7f;

/// Replaces the characters Windows rejects in a path segment with `_`.
///
/// Not every rule Windows has: a segment of `CON` or `NUL`, or one ending in a
/// dot, is still refused by the platform and is not touched here.
///
/// Trimmed before replacing, not after. A name ending in a newline used to
/// have it trimmed away, and replacing first would turn it into a trailing `_`
/// — a different directory from the one an existing install already has, for
/// the two call sites that derive a persistent per-device folder.
String sanitizePathSegment(String input) {
  return input.trim().replaceAll(reservedNameCharsPattern, '_');
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
