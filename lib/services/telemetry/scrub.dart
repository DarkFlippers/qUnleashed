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
/// Two levels, because the two readers want different things.
///
/// [paths] runs at the sink, on everything kept, as it has since #89: a home
/// directory is noise to the person reading the log on their own phone and a
/// name to anyone else, so there is no build in which keeping it is right.
/// Nothing unredacted ever enters the history.
///
/// [outbound] runs on what leaves the device. The difference matters because
/// the aggressive patterns §6 asks for - a Flipper's name, a card filename,
/// a long hex run - are the very words that make an on-screen log useful to
/// the user debugging their own device. Scrubbing those at the sink would
/// hand them a log about `<redacted>` failing to read `<redacted>`. So the
/// history stays readable and the copy that travels is the one that pays.
abstract final class Scrub {
  /// Home directories, longest first, replaced with `~` wherever they appear.
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
  static String paths(String msg) {
    var out = msg;
    for (final home in _homes) {
      out = out.replaceAll(home, '~');
    }
    return out;
  }

  /// [msg] made fit to leave the device.
  ///
  /// Everything [paths] does, and — once §6's remaining patterns land — known
  /// Flipper names, filenames under `/ext` and `/int` with the extension kept,
  /// long hex runs, coordinates and URL query strings. **Those are not here
  /// yet**: today this is [paths] under a second name, and the name exists so
  /// that every outbound call site is already routed through the one function
  /// that will grow them, rather than being found again afterwards.
  ///
  /// What that means for what has shipped: an error reaching Sentry today
  /// carries whatever the message said, minus the account name. That is the
  /// same exposure the Log screen's Copy button has had since #89, to a
  /// smaller audience. Replay and metrics - the categories that could carry a
  /// card dump rather than a sentence about one - are phase 3 and are gated on
  /// this being finished (§6.4).
  static String outbound(String msg) => paths(msg);
}
