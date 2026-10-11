// Every character the UI can print in Born2bSportyV3 has a glyph in it.
//
// Born2bSportyV3 is the face on every `ProgressButton` and on the about page.
// It is a pixel font, and a pixel font covers whatever its author drew and
// nothing else. When a string reaches it with a character it does not have,
// Flutter does not fail and does not warn: it substitutes the system face for
// that one character and renders the rest in the pixel font. The result is a
// button that reads `НЕМА З'ЄДНАННЯ` with a serif Є sitting in the middle of
// it, which is how this was found - on a screenshot, months after it shipped.
//
// That is the whole reason this test exists. Nothing else in the toolchain can
// see it. `flutter analyze` has no opinion about glyphs, a widget test renders
// to a canvas nobody looks at, and the fallback is by design, so there is no
// error to assert on. The only moment the problem is visible is when a human
// reads a screenshot in a language they speak.
//
// Two things are checked:
//
//  1. Every codepoint in every ARB file, filtered to the scripts the font
//     claims to cover, is in its cmap.
//  2. The codepoints `tool/patch_pixel_font.py` adds are still there, so
//     rebuilding or replacing the .ttf cannot quietly drop them.
//
// What it deliberately does not check:
//
//  * Codepoints outside the claimed scripts - Han, kana, Hangul, Arabic,
//    Hebrew, Thai, Devanagari. The font has none of them and 20,992 Han glyphs
//    is not a thing anyone is going to draw on a 6x9 grid. If a CJK locale is
//    added, those strings will fall back, and the decision to take will be
//    which face `ProgressButton` uses for that locale, not which glyphs to
//    draw. Failing this test would not help make that decision.
//  * Whether a glyph is any *good*. The shipped solidus was present the whole
//    time and drawn as a zig-zag; only a person looking at it caught that.
//  * The other bundled face, GravityBold8, which has no Cyrillic at all. Every
//    string set in it is a hardcoded English word on the about page, so there
//    is nothing here to hold.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Scripts Born2bSportyV3 claims. A codepoint outside these is allowed to be
/// absent, and falls back - see the header.
const List<(int, int)> kClaimedRanges = [
  (0x0020, 0x007E), // ASCII
  (0x00A0, 0x00FF), // Latin-1 Supplement
  (0x0100, 0x017F), // Latin Extended-A
  (0x0218, 0x021B), // Romanian comma-below, added by the patch tool
  (0x0370, 0x03FF), // Greek
  (0x0400, 0x04FF), // Cyrillic
  (0x2010, 0x2027), // dashes, quotes, bullet, ellipsis
  (0x2190, 0x2193), // arrows
  (0x2212, 0x2212), // minus
  (0x2713, 0x2713), // check mark
];

/// What `tool/patch_pixel_font.py` adds. Losing one of these is the regression
/// this file is named after, so they are listed rather than derived.
const Map<String, String> kAddedByPatchTool = {
  'Ukrainian': 'ЄєІіЇїҐґ',
  'Belarusian': 'Ўў',
  'Macedonian and Serbian': 'ЅѕЃѓЌќЀѐЍѝ',
  'Romanian': 'ȘșȚț',
  'punctuation': '–—…•→−✓“”‘’',
};

void main() {
  late final Set<int> cmap;

  setUpAll(() {
    final file = File('assets/font/born2b-sporty-v3.ttf');
    expect(file.existsSync(), isTrue, reason: 'the button font is missing');
    cmap = _readCmap(file.readAsBytesSync());
  });

  test('the font still has everything the patch tool put in it', () {
    final missing = <String>[];
    for (final MapEntry(key: language, value: characters)
        in kAddedByPatchTool.entries) {
      for (final character in characters.runes) {
        if (!cmap.contains(character)) {
          missing.add(
            '$language ${String.fromCharCode(character)} '
            '(U+${character.toRadixString(16).toUpperCase().padLeft(4, '0')})',
          );
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'Born2bSportyV3 lost glyphs it is supposed to have. Rebuild it with '
          '`python tool/patch_pixel_font.py` rather than editing the .ttf.',
    );
  });

  test('every translated string is printable in the button font', () {
    final offenders = <String, List<String>>{};
    for (final file in Directory('translations').listSync().whereType<File>()) {
      if (!file.path.endsWith('.arb')) continue;
      final strings =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      for (final MapEntry(key: key, value: value) in strings.entries) {
        if (key.startsWith('@') || value is! String) continue;
        for (final character in value.runes) {
          if (!_isClaimed(character) || cmap.contains(character)) continue;
          offenders
              .putIfAbsent(
                'U+${character.toRadixString(16).toUpperCase().padLeft(4, '0')} '
                '${String.fromCharCode(character)}',
                () => <String>[],
              )
              .add('${file.uri.pathSegments.last}:$key');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'These characters are in a script Born2bSportyV3 covers but have no '
          'glyph, so a label containing one renders that character in the '
          'system face and the rest in the pixel face. Draw them in '
          '`tool/patch_pixel_font.py` and rebuild.\n'
          '${offenders.entries.map((e) => '  ${e.key}: ${e.value.take(3).join(', ')}').join('\n')}',
    );
  });
}

bool _isClaimed(int codepoint) =>
    kClaimedRanges.any((r) => codepoint >= r.$1 && codepoint <= r.$2);

/// The codepoints a TrueType file maps, read out of its format 4 cmap subtable.
///
/// Format 4 is the only one this font has, and it is the one every desktop
/// font has, so there is no format 12 path here. If a future font needs one,
/// this throws rather than silently reporting an empty cmap - an empty set
/// would make the tests above pass by covering nothing.
Set<int> _readCmap(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);

  final tableCount = data.getUint16(4);
  var cmapStart = -1;
  for (var i = 0; i < tableCount; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
    if (tag == 'cmap') {
      cmapStart = data.getUint32(record + 8);
      break;
    }
  }
  if (cmapStart < 0) throw StateError('no cmap table');

  final subtableCount = data.getUint16(cmapStart + 2);
  var best = -1;
  for (var i = 0; i < subtableCount; i++) {
    final record = cmapStart + 4 + i * 8;
    final platform = data.getUint16(record);
    final encoding = data.getUint16(record + 2);
    final offset = cmapStart + data.getUint32(record + 4);
    // Windows BMP, or Unicode BMP. Either carries the full Unicode mapping;
    // the Macintosh subtable is 8 bit and would lose every accented letter.
    if ((platform == 3 && encoding == 1) || (platform == 0 && encoding == 3)) {
      best = offset;
      if (platform == 3) break;
    }
  }
  if (best < 0) throw StateError('no Unicode cmap subtable');

  final format = data.getUint16(best);
  if (format != 4) throw StateError('cmap subtable is format $format, not 4');

  final segments = data.getUint16(best + 6) ~/ 2;
  final endCodes = best + 14;
  final startCodes = endCodes + segments * 2 + 2;
  final deltas = startCodes + segments * 2;
  final rangeOffsets = deltas + segments * 2;

  final covered = <int>{};
  for (var segment = 0; segment < segments; segment++) {
    final end = data.getUint16(endCodes + segment * 2);
    final start = data.getUint16(startCodes + segment * 2);
    if (start > end) continue;
    final delta = data.getInt16(deltas + segment * 2);
    final rangeOffsetAt = rangeOffsets + segment * 2;
    final rangeOffset = data.getUint16(rangeOffsetAt);

    for (var code = start; code <= end && code != 0xFFFF; code++) {
      final int glyph;
      if (rangeOffset == 0) {
        glyph = (code + delta) & 0xFFFF;
      } else {
        final at = rangeOffsetAt + rangeOffset + (code - start) * 2;
        if (at + 1 >= bytes.length) continue;
        final raw = data.getUint16(at);
        glyph = raw == 0 ? 0 : (raw + delta) & 0xFFFF;
      }
      if (glyph != 0) covered.add(code);
    }
  }
  return covered;
}
