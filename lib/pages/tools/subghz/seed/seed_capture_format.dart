import '../../../../services/logging.dart';
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
/// not parse is one a user should be told about, because the remaining hops may
/// no longer be consecutive and the search will then find nothing for a reason
/// that has nothing to do with their remote.
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

  /// Parses [text]. Returns a null capture when the file cannot be used at all,
  /// with `skipped` saying why.
  static SeedCaptureParse parse(String text, {String? path}) {
    final skipped = <String>[];
    final fields = <String, String>{};
    final hops = <int>[];

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
        } else {
          hops.add(hop);
        }
        continue;
      }
      if (fields.containsKey(key) && fields[key] != value) {
        skipped.add('$key given twice: "${fields[key]}" then "$value"');
        continue;
      }
      fields[key] = value;
    }

    final fileType = fields['Filetype'];
    if (fileType != null && fileType != _fileType) {
      skipped.add('not a seed capture: Filetype "$fileType"');
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

    if (hops.length < SeedCapture.minHops) {
      skipped.add(
        'only ${hops.length} hop(s); at least '
        '${SeedCapture.minHops} are needed',
      );
      return (capture: null, skipped: skipped);
    }

    // The declared count is a cross-check, not the source of truth: the `Hop`
    // lines are. A mismatch means the file was truncated mid-write, which is
    // worth saying because the hops that survived may not be consecutive.
    final declared = int.tryParse(fields['Hops'] ?? '');
    if (declared != null && declared != hops.length) {
      skipped.add('file says $declared hops, found ${hops.length}');
    }

    return (
      capture: SeedCapture(
        fix: fix,
        hops: List.unmodifiable(hops),
        manufacturer: manufacturer,
        frequencyHz: int.tryParse(fields['Frequency'] ?? ''),
        received: _timestamp(fields['Received']),
        sourcePath: path,
      ),
      skipped: skipped,
    );
  }

  /// Parses and logs what was skipped, for callers that have no UI for it.
  ///
  /// `warn`, not `info`: `info` const-folds away in release, so a file whose
  /// hops were half dropped would reach a user as "no seed found" with nothing
  /// anywhere saying why.
  static SeedCapture? parseAndReport(String text, {String? path}) {
    final result = parse(text, path: path);
    if (result.skipped.isNotEmpty) {
      LogService.warn(
        '[SeedCapture] ${path ?? 'capture'}: skipped '
        '${result.skipped.length} line(s) - ${result.skipped.join('; ')}',
      );
    }
    return result.capture;
  }

  /// A 32-bit hex word, with or without `0x`.
  ///
  /// `int.tryParse` on its own would accept a leading sign and silently take
  /// values too wide to be a frame half, so the shape is checked first.
  static int? _hex(String? value) {
    if (value == null) return null;
    final text = value.trim().replaceFirst(RegExp('^0[xX]'), '');
    if (!RegExp(r'^[0-9A-Fa-f]{1,8}$').hasMatch(text)) return null;
    return int.parse(text, radix: 16);
  }

  /// `YYYY-MM-DD HH:MM:SS`, as the capture app writes it.
  ///
  /// Null on anything else, including a plausible-looking date from a device
  /// whose clock was never set. It is only used to label a file in a list, so
  /// an absent timestamp costs a sort order and nothing else.
  static DateTime? _timestamp(String? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.trim().replaceFirst(' ', 'T'));
  }
}
