import 'dart:io' as io;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Takes out of a message what can be taken out mechanically.
///
/// [ADR 0013 §6](../../../docs/adr/0013-observability-with-sentry.md) asks for
/// one scrubber rather than one per destination, and this is it. It lives in
/// `telemetry/` because that is where the ADR puts it and because Sentry is
/// the destination that made it load-bearing — but it imports nothing from the
/// SDK, so `LogService` can call it without the app growing a vendor
/// dependency outside this folder.
///
/// One level, and it used to be two.
///
/// The split existed because the app kept its own on-screen log: scrubbing a
/// Flipper's name and a card filename at the sink would have handed the user a
/// log about `<redacted>` failing to read `<redacted>`, so [outbound]'s
/// aggressive patterns were held back for what left the device while a milder
/// `paths` ran on what stayed.
///
/// ADR 0013 §1 removed the local log, so there is no "what stayed" any more.
/// Everything `LogService` forwards leaves, which means everything pays - and
/// the two-level distinction became a seam with one side.
///
/// The console is the exception, and it is not this function's business: a
/// talking build prints the real path, because that build is a developer's own
/// machine.
abstract final class Scrub {
  /// Home directories replaced with `~` wherever they appear.
  ///
  /// Not sorted, unlike [_deviceNames]. Order does not matter here because
  /// each pattern is anchored against continuing a name, so a home that is a
  /// prefix of another cannot leave the remainder behind - the anchor carries
  /// what sorting would. This used to say "longest first", which a reader
  /// would reasonably have taken for a guarantee.
  ///
  /// The log is something a user copies into a public issue, and absolute
  /// paths are the one category that leaks every time it fires: the IR
  /// recovery names the tree it could not clear — at every launch — and any
  /// FileSystemException prints `path = '<absolute>'`. All of them begin with
  /// the account name.
  static List<RegExp> _homes = _resolveHomes(_environmentHomes());

  static List<String> _environmentHomes() => [
    for (final key in const ['USERPROFILE', 'HOME'])
      ?io.Platform.environment[key],
  ];

  /// Builds the patterns for [homes], in both the spellings a message can
  /// carry them in.
  ///
  /// A path reaches the log two ways and they do not look alike. A
  /// FileSystemException prints the native form — `C:\Users\Myte\...` — while
  /// a stack frame prints a URI, `file:///C:/Users/Myte/...`, with the
  /// separators flipped and the drive behind a scheme. Matching only the
  /// environment value catches the first and misses the second, which is
  /// exactly backwards: the entries carrying stacks are the ones most likely
  /// to be pasted into an issue.
  ///
  /// Each is anchored so that the next character cannot continue a name.
  /// Without that, a HOME of `/root` — ordinary in a container — would rewrite
  /// `/rootfs` to `~fs` and corrupt messages that had no path in them at all.
  static List<RegExp> _resolveHomes(List<String> homes) {
    final spellings = <String>{};
    for (final home in homes) {
      // Too short to be a home directory, and long enough to appear inside
      // unrelated text.
      if (home.length <= 3) continue;
      spellings.add(home);
      // The separator flipped, which is how a stack frame spells it. A URI
      // form — `file:///C:/Users/Myte/...` — contains this string, so the one
      // spelling covers both it and a bare forward-slash path. On POSIX it is
      // the same string as above and the set drops it.
      spellings.add(home.replaceAll(r'\', '/'));
    }
    return [
      for (final spelling in spellings)
        RegExp('${RegExp.escape(spelling)}(?![A-Za-z0-9_.-])'),
    ];
  }

  /// Points redaction at [homes] for the duration of a test.
  ///
  /// The real list comes from the environment, which a test cannot vary — and
  /// the cases worth pinning are all about unusual environments: a Windows
  /// home reached through a URI, one that is a prefix of an unrelated word,
  /// two that are the same string.
  @visibleForTesting
  static void debugUseHomes(List<String>? homes) =>
      _homes = _resolveHomes(homes ?? _environmentHomes());

  /// How many patterns redaction scans for. Behaviour cannot show a duplicate
  /// — replacing the same thing twice is the same answer — so the cost is the
  /// only way to see one, and on Windows under Git Bash both environment keys
  /// hold the same string.
  @visibleForTesting
  static int get debugHomePatternCount => _homes.length;

  /// [msg] with the account name out of every path in it.
  ///
  /// Private now. It was the public first level of a two-level scrubber; with
  /// the local log gone, the only entry point is [outbound], and a second
  /// public one would be an invitation to send something half-scrubbed.
  static String _paths(String msg) {
    var out = msg;
    for (final home in _homes) {
      out = out.replaceAll(home, '~');
    }
    return out;
  }

  /// Everything after a `?` in a URL.
  ///
  /// The host and the path stay, because which endpoint failed is the whole
  /// value of the line. The query goes because the map's tile URLs carry
  /// `QU_CARTO_KEY` in it - a paid key, in a message produced by every tile
  /// that will not load.
  ///
  /// Stops at whitespace and at the quote characters a message wraps a URL in,
  /// so a URL mentioned mid-sentence does not swallow the rest of the
  /// sentence.
  static final RegExp _query = RegExp(
    r'(\bhttps?://[^\s"\x27<>?]*)\?[^\s"\x27<>]*',
  );

  /// A *file* under `/ext` or `/int`: the directories, then the name, then the
  /// extension.
  ///
  /// The Flipper's two filesystems. The directory says what kind of thing
  /// failed - `/ext/nfc`, `/ext/subghz` - and that is diagnostic; the filename
  /// is the user's own and is often the whole leak: a card called
  /// `Office badge.nfc`, a dictionary named after a UID, a `.sub` named after
  /// a gate.
  ///
  /// Three things make this tighter than it looks.
  ///
  /// The extension is **required**, not optional, which is what tells a file
  /// from a directory. Every format the Flipper stores has one, and matching a
  /// bare `/ext/subghz` would replace the diagnostic half and keep nothing.
  ///
  /// The name may contain **spaces**, because real ones do - `Office
  /// badge.nfc`. An earlier version excluded whitespace and so matched only up
  /// to the space, leaving a last segment with no dot in it and redacting
  /// nothing at all. That is the kind of failure that looks like it works.
  ///
  /// Since the name may hold spaces, the clause separators are what bound it:
  /// `,;:` and the quotes. Without them `listing /ext/nfc failed, see
  /// notes.txt` would read `nfc failed, see notes` as one filename and eat the
  /// sentence. Directory segments exclude whitespace as well, so a prefix
  /// cannot run across prose to find a later extension.
  static final RegExp _flipperFile = RegExp(
    r'(/(?:ext|int)(?:/[^/\s"\x27<>,;:]+)*?/)'
    r'([^/\n"\x27<>,;:]{1,64}?)'
    r'(\.[A-Za-z0-9]{1,8})(?![A-Za-z0-9])',
  );

  /// The extensions the Flipper stores, for [_bareFile].
  ///
  /// An allow-list rather than `\.[a-z]+`, because these patterns match a
  /// filename with **no directory in front of it** - so anything looser would
  /// also rewrite `main.dart`, `pubspec.yaml` and every sentence ending in a
  /// word with a dot in it.
  ///
  /// **`txt` and `log` are deliberately absent**, though the Flipper stores
  /// both. They are too ordinary to claim bare: `CMakeLists.txt` is not a
  /// card, and a bare `.log` is more often a host file than a nonce log. The
  /// instances that matter - `/ext/nfc/.mfkey32.log` and its siblings - are
  /// written with their path, and [_flipperFile] takes any extension once a
  /// `/ext` or `/int` directory is in front of it.
  ///
  /// Only these two rules consult the list; [_flipperFile] does not, because
  /// the directory is the evidence there.
  static const List<String> _flipperExtensions = [
    'nfc',
    'sub',
    'ir',
    'rfid',
    'ibtn',
    'picopass',
    'nfcdict',
    'keys',
    'fap',
    'fal',
    'fim',
    'u2f',
  ];

  /// A Flipper file named without its directory, **in quotes**.
  ///
  /// The quotes are what make a multi-word name safe to match: they delimit
  /// the stem, so spaces inside it cannot run backwards across the sentence.
  /// `[Seed] refused "Garage gate.sub"` is the shape this is for.
  static final RegExp _quotedFile = RegExp(
    '(["\\x27])([^"\\x27/\\n]{1,64}?)\\.(${_flipperExtensions.join('|')})\\1',
    caseSensitive: false,
  );

  /// A Flipper file named without its directory and without quotes.
  ///
  /// [_flipperFile] requires the `/ext` or `/int` prefix, which is how
  /// `[Archive] restore Office badge.nfc failed` went out with the name
  /// intact - the directory case working is what made the gap easy to miss.
  ///
  /// **No spaces in the stem, unlike the other two rules**, and that is a
  /// deliberate under-reach. A bare unquoted name has nothing delimiting its
  /// start: allowing spaces made `listing /ext/nfc failed, see notes.txt`
  /// match from `failed,` onwards and swallow the clause. There is no pattern
  /// that tells a multi-word filename from the prose in front of it.
  ///
  /// So a multi-word unquoted basename loses its last word and keeps the
  /// rest - `restore Office badge.nfc` becomes `restore Office <name>.nfc`.
  /// That is a partial redaction, chosen over destroying the message: the
  /// outbound log exists to be read, and a filename is lower-value than the
  /// keys and UIDs the hex rule takes. Quote the name at the call site and it
  /// is covered in full.
  static final RegExp _bareFile = RegExp(
    // A backslash ends the stem as well as a slash: without it the rule
    // swallowed the `~` that [paths] had just left behind, so
    // `~\\dict.nfc` came out as `<name>.nfc` and the message lost the one
    // marker saying a home directory had been there.
    '(?<![-\\w/.])([^\\s/\\\\"\\x27<>,;:]{1,64}?)'
    '\\.(${_flipperExtensions.join('|')})'
    '(?![-\\w])',
    caseSensitive: false,
  );

  /// A long hex run: a card dump, a key, a UID, a block.
  ///
  /// Eight is the floor because a 4-byte MIFARE UID is exactly eight
  /// characters, and a UID is the one identifier the user cannot change.
  ///
  /// **At least one `A-F` is required**, which is what keeps this off ordinary
  /// numbers. Without it the pattern matches any run of eight digits, and a
  /// message naming a timestamp, a byte count or a build number would come out
  /// as `<hex>` - over-redaction that costs the readability the whole outbound
  /// path exists for. The price is that an all-numeric UID survives; a UID is
  /// pseudonymous where a key is not, so that is the right side to err on.
  ///
  /// Boundaries rather than `\b`, and the reason is the **underscore**:
  /// `\b` treats `_` as a word character, so `_a1b2c3d4` would match nothing,
  /// while these lookarounds exclude only `[0-9A-Za-z]` and catch it.
  ///
  /// This used to claim the reason was the hyphen in `a1b2c3d4-e5f6`, which is
  /// wrong twice: `-` is a boundary for these lookarounds too, so the halves
  /// are still matched separately - and `\b` would have matched only the
  /// first half anyway, because the second is four characters and under the
  /// floor. Nothing currently keeps a hyphenated pair together.
  static final RegExp _hex = RegExp(
    r'(?<![0-9A-Za-z])(?=[0-9A-Fa-f]{8,}(?![0-9A-Za-z]))'
    r'[0-9A-Fa-f]*[A-Fa-f][0-9A-Fa-f]*',
  );

  /// A decimal with four or more places, which is what a coordinate is.
  ///
  /// Sub-GHz captures and the map both carry them. Four places is about 11
  /// metres, so nothing with fewer is locating anybody; it also keeps this off
  /// a version (`0.15.0` has none) and off the one- and two-place decimals
  /// that durations and percentages are written with.
  static final RegExp _coordinate = RegExp(r'-?\d{1,3}\.\d{4,}');

  /// Flipper names the app has seen, longest first, as anchored patterns.
  ///
  /// **Anchored**, which they were not. `replaceAll(name, '<device>')` on a
  /// bare substring corrupts every message containing it: a Flipper called
  /// `Zero`, `Data`, `File` or `Time` turned `FileSystemException` into
  /// `<device>SystemException`. [_resolveHomes] goes to the same trouble for
  /// the same reason, and the four-character floor below even cites that
  /// argument - it just was not applied here. The cost fell on the reports
  /// that had already failed.
  ///
  /// A learned set rather than a pattern, because a device name is arbitrary
  /// text and nothing distinguishes one from any other word. People name a
  /// Flipper after themselves, so this is the field most likely to carry a
  /// person's name out of the device.
  ///
  /// Fed from where the app learns the name, not from here. Mutable process
  /// state, which is what it has to be: the name is not known until a device
  /// answers, and the messages worth scrubbing are the ones produced after
  /// that.
  static final List<String> _deviceNames = [];
  static final List<RegExp> _devicePatterns = [];

  /// Remembers [name] so [outbound] takes it out of what it sends.
  ///
  /// Ignores anything under four characters. A two- or three-letter name would
  /// match inside unrelated words and corrupt every message carrying one,
  /// which is the failure the home-directory anchoring exists to prevent -
  /// and a name that short identifies nobody.
  ///
  /// Longest first, so a name that is a prefix of another does not leave the
  /// remainder behind.
  static void rememberDeviceName(String name) {
    final trimmed = name.trim();
    if (trimmed.length < 4 || _deviceNames.contains(trimmed)) return;
    _deviceNames
      ..add(trimmed)
      ..sort((a, b) => b.length.compareTo(a.length));
    _devicePatterns
      ..clear()
      ..addAll(_deviceNames.map(_anchored));
  }

  /// [text] as a pattern that cannot match inside a longer word.
  ///
  /// The same anchoring [_resolveHomes] uses, as a named function so the two
  /// rules cannot drift - the device names being the one unanchored rule in a
  /// file whose others all anchor is how a `<device>SystemException` happened.
  static RegExp _anchored(String text) =>
      RegExp('(?<![A-Za-z0-9_])${RegExp.escape(text)}(?![A-Za-z0-9_])');

  /// Forgets the learned names, so one test does not inherit another's.
  @visibleForTesting
  static void debugForgetDeviceNames() {
    _deviceNames.clear();
    _devicePatterns.clear();
  }

  /// [msg] made fit to leave the device.
  ///
  /// §6.2's whole list. The order is load-bearing in one place: [_hex] runs
  /// last, because it would otherwise eat pieces of a path or a name before
  /// the pattern that knows what they are gets to look at them.
  ///
  /// Every rule replaces rather than drops. A scrubber that returned null on
  /// something it did not recognise would lose exactly the failures nobody has
  /// seen before, and `beforeSend` reads null as "drop this event".
  static String outbound(String msg) {
    var out = _paths(msg);
    out = out.replaceAllMapped(_query, (m) => '${m[1]}?<query>');
    out = out.replaceAllMapped(_flipperFile, (m) => '${m[1]}<name>${m[3]}');
    // After the path rule, which has already replaced the stems it owns - so
    // these only ever see a filename nobody named a directory for. Quoted
    // first: it is the stricter match, and running it second would find
    // nothing left to quote.
    out = out.replaceAllMapped(
      _quotedFile,
      (m) => '${m[1]}<name>.${m[3]}${m[1]}',
    );
    out = out.replaceAllMapped(_bareFile, (m) => '<name>.${m[2]}');
    for (final pattern in _devicePatterns) {
      out = out.replaceAll(pattern, '<device>');
    }
    out = out.replaceAll(_coordinate, '<coord>');
    out = out.replaceAll(_hex, '<hex>');
    return out;
  }
}
