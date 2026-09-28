import 'dart:io' as io;

import '../../../../components/path.dart';
import '../../../../services/storage/paths.dart';

/// Per-animation settings as stored in a Flipper `manifest.txt`
/// (`Filetype: Flipper Animation Manifest`). Mirrors the editable fields of
/// FlipperAnimationManager's `Animation` (`.sources/FlipperAnimationManager`):
/// each selected animation contributes one block to the manifest.
class ManifestEntry {
  ManifestEntry({
    required this.name,
    this.selected = false,
    this.minButthurt = kDefaultMinButthurt,
    this.maxButthurt = kDefaultMaxButthurt,
    this.minLevel = kDefaultMinLevel,
    this.maxLevel = kDefaultMaxLevel,
    this.weight = kDefaultWeight,
  });

  /// Defaults match FlipperAnimationManager's `Animation` initial values.
  static const int kDefaultMinButthurt = 0;
  static const int kDefaultMaxButthurt = 14;
  static const int kDefaultMinLevel = 1;
  static const int kDefaultMaxLevel = 30;
  static const int kDefaultWeight = 8;

  /// Animation name; must equal the on-device folder name under `/ext/dolphin`.
  String name;
  bool selected;
  int minButthurt;
  int maxButthurt;
  int minLevel;
  int maxLevel;
  int weight;
}

/// What a manifest parse found, and what it could not place.
///
/// [nameless] counts paragraphs that held settings but no `Name:` line. They
/// belong to no animation and their lines are dropped; the screen says so,
/// because the alternative is a file the user edited doing something other
/// than what it looks like.
class ManifestRead {
  const ManifestRead({required this.entries, required this.nameless});

  final Map<String, ManifestEntry> entries;
  final int nameless;
}

/// Reads, parses and serializes the Flipper animation manifest.
///
/// The format is line-based: a two-line header (`Filetype:`/`Version:`) followed
/// by blank-line-separated blocks, one per animation, each with `Name`,
/// `Min/Max butthurt`, `Min/Max level` and `Weight`. Matches the parser in
/// `.sources/FlipperAnimationManager/src/Manifest.cpp`.
abstract final class DolphinManifest {
  static const String header =
      'Filetype: Flipper Animation Manifest\nVersion: 1\n';

  /// Parses a manifest into entries keyed by animation name, and says how many
  /// paragraphs held settings but no name.
  ///
  /// Blocks are blank-line separated, so a blank line ends the block it
  /// follows. A paragraph with settings and no `Name:` of its own belongs to
  /// no animation: its lines are dropped rather than folded into the block
  /// above, which is what they used to do - a stray `Weight: 9` silently
  /// changed the animation before it. #171 holds the reading of the reference
  /// parser that settled this.
  ///
  /// A malformed block costs only itself. The reference implementation stops
  /// at the first fault and discards every animation after it; keeping them is
  /// this project's rule for feed-shaped input, and the count is what makes
  /// keeping them honest rather than silent.
  static ManifestRead parse(String text) {
    final out = <String, ManifestEntry>{};
    ManifestEntry? current;
    var nameless = 0;
    var strayInParagraph = false;

    void commit() {
      final e = current;
      if (e != null) out[e.name] = e;
      current = null;
    }

    void endParagraph() {
      if (current == null && strayInParagraph) nameless++;
      commit();
      strayInParagraph = false;
    }

    int? readInt(String line, String key) {
      if (!line.startsWith(key)) return null;
      return int.tryParse(line.substring(key.length).trim());
    }

    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        endParagraph();
        continue;
      }
      if (line.startsWith('Name: ')) {
        commit();
        current = ManifestEntry(name: line.substring(6).trim(), selected: true);
        strayInParagraph = false;
        continue;
      }
      final e = current;
      if (e == null) {
        // A setting with no block to belong to. Counted once for the
        // paragraph, when the blank line closes it or the text runs out.
        if (_isSetting(line)) strayInParagraph = true;
        continue;
      }
      final mb = readInt(line, 'Min butthurt: ');
      if (mb != null) e.minButthurt = mb;
      final xb = readInt(line, 'Max butthurt: ');
      if (xb != null) e.maxButthurt = xb;
      final ml = readInt(line, 'Min level: ');
      if (ml != null) e.minLevel = ml;
      final xl = readInt(line, 'Max level: ');
      if (xl != null) e.maxLevel = xl;
      final w = readInt(line, 'Weight: ');
      if (w != null) e.weight = w;
    }
    endParagraph();
    return ManifestRead(entries: out, nameless: nameless);
  }

  static bool _isSetting(String line) => const [
    'Min butthurt: ',
    'Max butthurt: ',
    'Min level: ',
    'Max level: ',
    'Weight: ',
  ].any(line.startsWith);

  /// Serializes the [selected] entries into manifest text, in iteration order.
  /// Mirrors the string built in `.sources/FlipperAnimationManager/src/main.cpp`.
  static String build(Iterable<ManifestEntry> selected) {
    final sb = StringBuffer(header);
    for (final e in selected) {
      sb
        ..write('\nName: ')
        ..write(e.name)
        ..write('\nMin butthurt: ')
        ..write(e.minButthurt)
        ..write('\nMax butthurt: ')
        ..write(e.maxButthurt)
        ..write('\nMin level: ')
        ..write(e.minLevel)
        ..write('\nMax level: ')
        ..write(e.maxLevel)
        ..write('\nWeight: ')
        ..write(e.weight)
        ..write('\n');
    }
    return sb.toString();
  }

  /// Loads the manifest mirrored from the device on the last import
  /// (`Animations/dolphin/manifest.txt`). Returns an empty map when the folder
  /// or file is absent — in that case nothing is pre-selected.
  static Future<Map<String, ManifestEntry>> loadLocal() async {
    try {
      final dir = await appDolphinAnimationsDirectory();
      final file = io.File(pathJoin([dir.path, 'manifest.txt']));
      if (!await file.exists()) return <String, ManifestEntry>{};
      return parse(await file.readAsString()).entries;
    } catch (_) {
      return <String, ManifestEntry>{};
    }
  }
}
