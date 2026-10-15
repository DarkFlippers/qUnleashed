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
///
/// **Two rules were removed rather than lost, and what they covered is now
/// sent whole.** A learned Flipper name, which used to become `<device>`, and
/// a long hex run - a UID, a key, a MAC, a serial, a block - which used to
/// become `<hex>`. The project looked at both and decided they are not worth
/// hiding: a Flipper's name is generated, not a person's, and a key or a UID
/// is the thing the app exists to recover and the thing a bug report about it
/// has to contain. A report that says what went wrong on screen beside a log
/// that says `<hex>` was the worst of both.
///
/// **The replay does not follow all the way**, and the exception matters
/// before the rest is read as a principle: a recovered key and a card UID
/// stay masked there, because `diagnosticsShareSubtitle` and §1's notice
/// promise the user that keys are never sent. ADR 0013 §6.4 has the
/// argument. Device name, serial, BLE MAC and the `device info` dump are open
/// on all three channels.
///
/// One consequence worth knowing, since the hex rule was broad: the FAAC
/// `fix` is logged in hex by `tools/subghz/seed/seed_controller.dart`, at
/// `[Seed] searching ...` on every run and `[Seed] search failed for ...`
/// when one fails, so that identifier now leaves intact. It names a remote
/// rather than opening one, and the seed beside it is never logged - only
/// `seed=<bool>`. The old rule did not reliably take it either, since
/// `toRadixString(16)` drops leading zeros and the rule wanted eight
/// characters with a letter among them. It was not part of the decision, and
/// those two call sites are the place to change if it should be.
abstract final class Scrub {
  /// Home directories replaced with `~` wherever they appear.
  ///
  /// Not sorted. Order does not matter here because
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
  /// outbound log exists to be read, and half a filename still says what kind
  /// of thing failed. Quote the name at the call site and it is covered in
  /// full. (This used to weigh the loss against "the keys and UIDs the hex
  /// rule takes"; that rule is gone, and the class doc now argues the
  /// opposite valuation, so the comparison went with it.)
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

  /// A decimal with four or more places, which is what a coordinate is.
  ///
  /// Sub-GHz captures and the map both carry them. Four places is about 11
  /// metres, so nothing with fewer is locating anybody; it also keeps this off
  /// a version (`0.15.0` has none) and off the one- and two-place decimals
  /// a percentage is written with.
  ///
  /// **The lookbehinds are for `Duration.toString()`,** which writes `H:MM:SS`
  /// and then *six* places - so every duration in every outbound line was over
  /// the four-place floor, and a timeout arrived with `0:00:<coord>` where its
  /// seconds had been: the one number the reader needed, gone. This was shipped
  /// and measured. It reached Sentry on the firmware **directory fetch**'s
  /// timeout (`pages/devices/firmware/repository.dart`, not `installer.dart`,
  /// whose 30-second budget is the post-recovery reconnect wait) and on
  /// `reconnect failed` - two failures whose whole content is how long
  /// something waited.
  ///
  /// The comment above used to say this rule stayed off "the one- and
  /// two-place decimals that durations and percentages are written with",
  /// and `test/scrub_test.dart` asserted it with `took 1.25s` - a format
  /// nothing in the app produces. Two places was never the shape at risk.
  ///
  /// **Two lookbehinds, and both are load-bearing.** `(?<!\d:\d\d:)` rejects
  /// a decimal sitting immediately after `H:MM:`, which is `30.000000`. On its
  /// own that is not enough: `replaceAll` simply advances one character and
  /// matches `0.000000` instead, so the line came out as `0:00:3<coord>` -
  /// worse than before, because it looks like a number rather than a
  /// redaction. `(?<!\d)` is what closes that, by refusing to start the
  /// integer part in the middle of a digit run. The first version of this fix
  /// had only the first one and its own test caught it.
  ///
  /// Narrow on purpose: neither excludes every colon, so `lat:50.4501` is
  /// still redacted.
  ///
  /// What `(?<!\d)` also does, which is worth knowing before widening the
  /// floor: a decimal whose integer part runs past three digits is now left
  /// alone entirely, where the old rule redacted its tail. `1234.5678` used to
  /// come out `1<coord>`, which was never the intent. The cost is that a
  /// coordinate written NMEA-style - `5027.0067,N`, degrees and minutes run
  /// together - passes through whole. Nothing in the app produces that today:
  /// the map parses decimal degrees (`lat:`/`latitude:`), which cap at three
  /// integer digits. A raw GPS line quoted into an exception message would be
  /// the way it arrives, and this rule would not catch it.
  static final RegExp _coordinate = RegExp(
    r'(?<!\d)(?<!\d:\d\d:)-?\d{1,3}\.\d{4,}',
  );

  /// [msg] made fit to leave the device.
  ///
  /// §6.2's whole list. One ordering constraint went with the hex rule, which
  /// ran last so that it could not eat pieces of a path before the pattern
  /// that knew what they were had looked at them. The others stand, and the
  /// comments inside say so: [_paths] before [_bareFile], and [_quotedFile]
  /// before [_bareFile].
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
    out = out.replaceAll(_coordinate, '<coord>');
    return out;
  }
}
