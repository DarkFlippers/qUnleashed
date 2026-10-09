import 'seed_models.dart';

/// Where the Flipper-side capture app writes its files.
///
/// It creates the folder itself, so a device that has never run the app has no
/// such directory - which the browse step has to read as "nothing captured
/// yet" rather than as an error.
const seedCaptureDir = '/ext/apps_data/subghz_seed_captures';

/// The extension those files carry. Deliberately not `.sub`: the file is a fix
/// and a set of hops, not a playable signal, and the capture app's own header
/// comment says so.
const seedCaptureExtension = '.txt';

/// A parsed capture, and what had to be skipped to get it.
///
/// `skipped` is surfaced rather than swallowed: a file half of whose hops did
/// not parse is one a user should be told about, because the hops that remain
/// can be left with a gap wider than [SeedCapture.maxCounterGap] and the search
/// will then find nothing for a reason that has nothing to do with their
/// remote. A hop dropped for repeating the one before it is reported the same
/// way, though it is not a fault in the file and does not make the capture
/// worse - the comment at that drop says why it is still worth showing.
typedef SeedCaptureParse = ({SeedCapture? capture, List<String> skipped});

/// Reads the capture files the `seed_capturer` app writes.
///
/// The format is Flipper's own key-value one: a `Filetype` header, then
/// `Key: value` lines, with `#` comments and repeated `Hop:` entries.
///
///     Filetype: Flipper SubGhz Seed Capture
///     Version: 1
///     Received: 2026-10-06 21:14:33
///     Manufacturer: Genius
///     Protocol: Faac SLH
///     Frequency: 868350000
///     Preset: FuriHalSubGhzPresetOok650Async
///     Fix: A0DC9330
///     Hops: 3
///     Hop: 29389EF7
///     Hop: 40101499
///     Hop: A1F9C88F
///
/// Tolerant by the same rule as the `.nested.log` parser: a line that does not
/// make sense is skipped and named, rather than failing the whole file. The
/// file comes off a removable card written by a separate application, and one
/// bad line should not cost the user the other nine hops.
///
/// Two fields are not tolerated, because without either there is nothing to
/// attack: the fixed code, and at least [SeedCapture.minHops] hops.
class SeedCaptureFormat {
  const SeedCaptureFormat._();

  static const _fileType = 'Flipper SubGhz Seed Capture';
  static const _fileVersion = 1;

  /// Parses [text]. Returns a null capture when the file cannot be used at all,
  /// with `skipped` saying why.
  static SeedCaptureParse parse(String text) {
    final skipped = <String>[];
    final fields = <String, String>{};
    final hops = <int>[];
    // Hop lines that parsed, duplicates included. The declared-count
    // cross-check below compares against this rather than against the hops
    // kept, so a file with a repeated press is not also reported as a
    // truncated write - those are different faults with different advice.
    var hopLines = 0;

    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final colon = line.indexOf(':');
      if (colon <= 0) {
        skipped.add('no key: "$line"');
        continue;
      }
      final key = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim();

      // `Hop` repeats; everything else is one value. A second `Fix` would mean
      // two remotes in one file, which is a file worth refusing rather than
      // silently attacking the first.
      if (key == 'Hop') {
        final hop = _hex(value);
        if (hop == null) {
          skipped.add('unreadable hop: "$value"');
          continue;
        }
        hopLines++;
        if (hops.isNotEmpty && hops.last == hop) {
          // The engine refuses a step of zero: the same frame twice is a break
          // in the counter march, not a small one. The probe's `the same hop
          // twice` vector pins that refusal, and says there what produces it -
          // a capture app that wrote one press twice.
          //
          // So a capture that keeps the repeat cannot solve as a whole, which
          // costs the first sweep in every case. It costs the *answer* when
          // neither side of the repeat keeps [seedHopsConfident] hops, because
          // then no window the ladder offers avoids it: a three-hop capture, or
          // a four-hop one with the repeat in the middle. The user then sees
          // "no seed matched" and a hint that sends them to record the same
          // file again.
          //
          // Dropping it changes nothing else: two identical hops are the same
          // counter, so they are one press however far apart the lines sit, and
          // no step between distinct hops moves. Named rather than silent,
          // because a capture app writing every press twice is worth seeing.
          // #289
          skipped.add('repeated hop: "$value"');
          continue;
        }
        hops.add(hop);
        continue;
      }
      if (fields.containsKey(key) && fields[key] != value) {
        skipped.add('$key given twice: "${fields[key]}" then "$value"');
        // A second Fix is two remotes in one file. Keeping the first and
        // merging both sets of hops produces a capture whose hops are not all
        // from one remote, which sweeps the whole space and ends on "nothing
        // matched" - the one answer this feature is careful not to give
        // wrongly. Refused rather than attacked.
        if (key == 'Fix') return (capture: null, skipped: skipped);
        continue;
      }
      fields[key] = value;
    }

    // Required, not merely checked when present: a file with no header at all
    // was being accepted and attacked.
    final fileType = fields['Filetype'];
    if (fileType != _fileType) {
      skipped.add('not a seed capture: Filetype "${fileType ?? ''}"');
      return (capture: null, skipped: skipped);
    }

    // The version is the capture app's own statement that the layout changed.
    // Ignoring it is how a v2 file - a renamed field, a different byte order, a
    // button split out of the fix - parses cleanly under v1 rules, sweeps the
    // whole space and comes back "no seed matched this capture", sending the
    // user to re-record a remote that was never the problem.
    final version = int.tryParse(fields['Version'] ?? '');
    if (version != _fileVersion) {
      skipped.add(
        'capture is version ${fields['Version'] ?? '?'}, '
        'this build reads version $_fileVersion',
      );
      return (capture: null, skipped: skipped);
    }

    final fix = _hex(fields['Fix']);
    if (fix == null) {
      skipped.add('no usable Fix');
      return (capture: null, skipped: skipped);
    }

    final manufacturer = SeedManufacturer.fromLabel(
      fields['Manufacturer'] ?? '',
    );
    if (manufacturer == null) {
      // Named rather than guessed. The mode decides which manufacture key the
      // search uses, so picking one would not fail - it would sweep the whole
      // space and report that no seed exists, which is the one answer a user
      // must not be given wrongly.
      skipped.add('unknown Manufacturer "${fields['Manufacturer'] ?? ''}"');
      return (capture: null, skipped: skipped);
    }

    final protocol = fields['Protocol'];
    if (protocol != null && protocol != manufacturer.protocol) {
      skipped.add(
        'file says Protocol "$protocol" for '
        '${manufacturer.label}, which this build pairs with '
        '"${manufacturer.protocol}"',
      );
      return (capture: null, skipped: skipped);
    }

    if (hops.length < SeedCapture.minHops) {
      skipped.add(
        'only ${hops.length} hop(s); at least '
        '${SeedCapture.minHops} are needed',
      );
      return (capture: null, skipped: skipped);
    }

    // The declared count is a cross-check, not the source of truth: the `Hop`
    // lines are. A mismatch means the file was truncated mid-write, which is
    // worth saying because the hops that survived can be left with a gap too
    // wide for the engine to tolerate - or that a line did not parse, which is
    // named on its own line above as well. Two messages for one fault there,
    // which is the lesser evil: counting an unparseable line as present would
    // hide a truncated final hop, and that is the case `_hex` refuses short
    // words for.
    //
    // Both numbers are hop *lines*, said so because the card beside them counts
    // hops kept - a deduplicated file would otherwise read "3 hops" under "found
    // 4".
    final declared = int.tryParse(fields['Hops'] ?? '');
    if (declared != null && declared != hopLines) {
      skipped.add('file says $declared hop lines, read $hopLines');
    }

    return (
      capture: SeedCapture(
        fix: fix,
        hops: List.unmodifiable(hops),
        manufacturer: manufacturer,
        frequencyHz: _frequency(fields['Frequency']),
        preset: fields['Preset'],
      ),
      skipped: skipped,
    );
  }

  /// A 32-bit hex word, with or without `0x`.
  ///
  /// Exactly eight digits, because that is what the capture app writes
  /// (`%08lX`) and because a shorter one is a truncated write rather than a
  /// small number: `Hop: 2938` would otherwise parse as `0x00002938`, join the
  /// capture, and poison it - and the declared-count cross-check cannot see it,
  /// since the line is present.
  ///
  /// `int.tryParse` on its own would also accept a leading sign and values too
  /// wide to be a frame half, so the shape is checked first either way.
  static int? _hex(String? value) {
    if (value == null) return null;
    final text = value.trim().replaceFirst(RegExp('^0[xX]'), '');
    if (!RegExp(r'^[0-9A-Fa-f]{8}$').hasMatch(text)) return null;
    return int.parse(text, radix: 16);
  }

  /// Hertz, or null for anything that is not a usable frequency.
  ///
  /// `int.tryParse` alone accepts `0` and `-1`, and a `.sub` written with
  /// either transmits into the void - which is the whole reason this field is
  /// held as nullable rather than defaulted. The range is deliberately loose:
  /// the point is to reject a truncated or corrupt line, not to police which
  /// bands the radio supports.
  static int? _frequency(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 1000000 || parsed > 2000000000) return null;
    return parsed;
  }
}
