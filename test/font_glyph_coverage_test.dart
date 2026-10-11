// Every character the UI can print in Born2bSportyV3 has a glyph with ink in it.
//
// Born2bSportyV3 is the face on every `ProgressButton` and on the about page.
// It is a pixel font, and a pixel font covers whatever its author drew and
// nothing else. When a string reaches it with a character it has not got,
// Flutter does not fail and does not warn: it substitutes the system face for
// that one character and renders the rest in the pixel font. The result is a
// button that reads `НЕМА З'ЄДНАННЯ` with a serif Є sitting in the middle of
// it, which is how this was found - on a screenshot, months after it shipped.
//
// That is the whole reason this file exists. Nothing else in the toolchain can
// see it. `flutter analyze` has no opinion about glyphs, a widget test renders
// in Ahem and never loads a pubspec font at all, and the fallback is by
// design, so there is no error to assert on. The only moment the problem is
// visible is when a human reads a screenshot in a language they speak.
//
// Four things are checked:
//
//  1. The font the app asks for is the font this file validates. `fontFamily`
//     is a string the compiler never checks, and a family Flutter cannot
//     resolve falls back silently and wholesale - a worse version of the same
//     bug, the whole label rather than one character.
//  2. Every codepoint `tool/patch_pixel_font.py` declares is mapped AND has an
//     outline. Mapped-but-blank is worse than missing: a missing glyph gets
//     the system face, a blank one gets nothing at all.
//  3. The tool's declarations and this file's list of them have not drifted.
//  4. Every character of every ARB file - and of its uppercasing, since
//     `firmware_update_button.dart` uppercases its labels - is in the font,
//     unless a script in `kFallbackAllowed` names it.
//
// Check 4 is a denylist on purpose. It was an allowlist of claimed ranges
// first, which reads the same way round and is not: a codepoint nobody had
// thought of was skipped in silence, so `№`, `₴` and `ʼ` - all absent from the
// font, all plausible in a Ukrainian or Russian string - would have shipped
// the original bug with this file green. Now anything unlisted fails, and the
// exemption has to be argued for in a diff.
//
// What it still cannot see, and what covers each instead:
//
//  * Whether a glyph is any good. The shipped solidus was present the whole
//    time and drawn as a zig-zag. `tool/patch_pixel_font_test.py` pins the
//    shapes by reading them back out of the built font.
//  * Strings that are not in an ARB file. `recover_page.dart` puts a literal
//    `'…'` on a `ProgressButton`, and runtime values - a Flipper filename, a
//    device name - can hold any codepoint at all. `ProgressButton` carries a
//    `fontFamilyFallback` for that, which cannot be asserted here.
//  * The other bundled face, GravityBold8, which has no Cyrillic. Every string
//    set in it is a hardcoded English word on the about page.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// `fontFamily: 'Something'`. A regex rather than the analyzer, unlike the
/// budget ratchets: the thing being checked is a string literal, so parsing
/// buys no precision, and the AST node for a named argument has already been
/// renamed once between analyzer versions.
final RegExp _fontFamilyLiteral = RegExp("""fontFamily:\\s*['"]([^'"]+)['"]""");

const String kFamily = 'Born2bSportyV3';
const String kFontPath = 'assets/font/born2b-sporty-v3.ttf';
const String kToolPath = 'tool/patch_pixel_font.py';

/// Scripts the pixel font deliberately does not cover, so a character in one
/// falls back rather than failing this file.
///
/// Han alone is 20,992 codepoints; nobody is drawing those on a six by nine
/// grid. If a CJK locale is added, the decision to take is which face
/// `ProgressButton` uses for it - a `fontFamilyFallback`, or dropping the
/// pixel face there - and failing this test would not help make it. The list
/// only ever shrinks.
const List<(int, int, String)> kFallbackAllowed = [
  (0x3000, 0x303F, 'CJK punctuation'),
  (0x3040, 0x30FF, 'kana'),
  (0x3400, 0x4DBF, 'Han extension A'),
  (0x4E00, 0x9FFF, 'Han'),
  (0xAC00, 0xD7A3, 'Hangul'),
  (0xF900, 0xFAFF, 'Han compatibility'),
  (0x0590, 0x05FF, 'Hebrew'),
  (0x0600, 0x06FF, 'Arabic'),
  (0x0900, 0x097F, 'Devanagari'),
  (0x0E00, 0x0E7F, 'Thai'),
];

/// Codepoints with no ink by definition. A blank glyph is a defect everywhere
/// else, so these are named rather than inferred.
const Set<int> kBlankByDesign = {0x0020, 0x00A0};

/// What `tool/patch_pixel_font.py` adds, as characters rather than numbers so
/// a reader can see what is at stake. Derived from the tool it would be
/// circular - the test would agree with whatever the tool did, including
/// nothing - so it is written out here and cross-checked against the tool's
/// declarations by its own test below.
const Map<String, String> kAddedByPatchTool = {
  'Ukrainian': 'ЄєІіЇїҐґ',
  'Belarusian': 'Ўў',
  'Macedonian': 'ЅѕЃѓЌќ',
  'Macedonian and Bulgarian': 'ЀѐЍѝ',
  'Romanian': 'ȘșȚț',
  'punctuation': '–—…•→−✓“”‘’ʼ',
};

void main() {
  late final _Font font;

  setUpAll(() {
    final file = File(kFontPath);
    expect(file.existsSync(), isTrue, reason: '$kFontPath is missing');
    font = _Font.parse(file.readAsBytesSync());
    // A cmap this small would mean the parser found something it did not
    // understand and reported almost nothing, which would make every
    // assertion below pass by asking nothing.
    expect(
      font.cmap.length,
      greaterThan(400),
      reason:
          'only ${font.cmap.length} codepoints parsed out of $kFontPath; '
          'the parser is reading the wrong thing',
    );
  });

  test('the app asks for the font this file validates', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      contains('- family: $kFamily'),
      reason: 'pubspec.yaml does not declare $kFamily',
    );
    expect(
      pubspec,
      contains('- asset: $kFontPath'),
      reason:
          'pubspec.yaml declares $kFamily but not against $kFontPath, so '
          'this file is validating a font the app does not load',
    );

    final declared = RegExp(
      r'^\s*- family: (\S+)',
      multiLine: true,
    ).allMatches(pubspec).map((m) => m.group(1)!).toSet();
    // Families Flutter resolves itself; everything else must be in pubspec.
    const platformFamilies = {'monospace', 'serif', 'sans-serif'};

    final unknown = <String>[];
    var seen = 0;
    for (final path in dartFilesUnderLib()) {
      for (final match in _fontFamilyLiteral.allMatches(
        File(path).readAsStringSync(),
      )) {
        seen++;
        final family = match.group(1)!;
        if (declared.contains(family) || platformFamilies.contains(family)) {
          continue;
        }
        unknown.add('$path: $family');
      }
    }
    expect(
      seen,
      greaterThan(0),
      reason:
          'no fontFamily literal was found anywhere under lib/, so this '
          'check examined nothing',
    );
    expect(
      unknown,
      isEmpty,
      reason:
          'These fontFamily values are not declared in pubspec.yaml. '
          'Flutter does not fail on an unresolvable family - it silently '
          'renders the whole string in the default face.\n'
          '${unknown.join('\n')}',
    );
  });

  test('this file and the build tool agree on what was added', () {
    final tool = File(kToolPath).readAsStringSync();
    final declared = <int>{};
    // Alias entries: `0x0406: "I",`
    for (final m in RegExp(r'0x([0-9A-Fa-f]{4}):\s*"').allMatches(tool)) {
      declared.add(int.parse(m.group(1)!, radix: 16));
    }
    // Derived entries: `(0x0404, "uni0404",`
    for (final m in RegExp(r'\(0x([0-9A-Fa-f]{4}),\s*"').allMatches(tool)) {
      declared.add(int.parse(m.group(1)!, radix: 16));
    }
    expect(
      declared,
      isNotEmpty,
      reason:
          'found no codepoint declarations in $kToolPath; the regexes '
          'above have stopped matching the file they read',
    );

    final listed = kAddedByPatchTool.values
        .expand((characters) => characters.runes)
        .toSet();
    expect(
      declared.difference(listed).map(_name).toList()..sort(),
      isEmpty,
      reason:
          '$kToolPath adds codepoints this file does not list, so they '
          'are not held by anything. Add them to kAddedByPatchTool.',
    );
    expect(
      listed.difference(declared).map(_name).toList()..sort(),
      isEmpty,
      reason: 'This file lists codepoints $kToolPath no longer adds.',
    );
  });

  test('the font still has everything the patch tool put in it', () {
    final missing = <String>[];
    final blank = <String>[];
    for (final MapEntry(key: language, value: characters)
        in kAddedByPatchTool.entries) {
      for (final character in characters.runes) {
        final glyph = font.cmap[character];
        if (glyph == null) {
          missing.add('$language ${_name(character)}');
        } else if (!font.hasInk(glyph)) {
          blank.add('$language ${_name(character)}');
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          '$kFamily lost glyphs it is supposed to have. Rebuild it with '
          '`python $kToolPath` rather than editing the .ttf.',
    );
    expect(
      blank,
      isEmpty,
      reason:
          'These codepoints are mapped to a glyph with no outline, which '
          'renders as nothing at all - worse than the fallback this font '
          'exists to remove, because there is no fallback for a glyph that '
          'is present and empty.',
    );
  });

  test('every translated string is printable in the button font', () {
    final arbFiles = Directory('translations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))
        .toList();
    // Without this the whole test is a no-op the moment the ARB files move or
    // get renamed, and a no-op that reports success is how a guard becomes
    // decoration. `test/translation_completeness_test.dart` guards itself the
    // same way, for the same reason.
    expect(
      arbFiles.length,
      greaterThanOrEqualTo(2),
      reason:
          'found ${arbFiles.length} .arb files under translations/; '
          'this test cannot check anything without them',
    );

    final offenders = <String, List<String>>{};
    final examined = <int>{};
    for (final file in arbFiles) {
      final strings =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      for (final MapEntry(key: key, value: value) in strings.entries) {
        if (key.startsWith('@') || value is! String) continue;
        // The firmware button renders `state.label.toUpperCase()`, so the
        // uppercase form is as much a rendered string as the stored one.
        for (final character in '$value${value.toUpperCase()}'.runes) {
          if (_isWhitespaceOrControl(character)) continue;
          if (_fallbackAllowed(character) != null) continue;
          examined.add(character);
          final glyph = font.cmap[character];
          if (glyph != null && font.hasInk(glyph)) continue;
          if (glyph != null && kBlankByDesign.contains(character)) continue;
          offenders
              .putIfAbsent(_name(character), () => <String>[])
              .add('${file.uri.pathSegments.last}:$key');
        }
      }
    }

    expect(
      examined.length,
      greaterThan(100),
      reason:
          'only ${examined.length} distinct codepoints were examined; '
          'the ARB files read as near-empty, so this test proved nothing',
    );
    expect(
      examined.any((c) => c >= 0x0400 && c <= 0x04FF),
      isTrue,
      reason:
          'no Cyrillic was examined at all, so the locale this font was '
          'fixed for is not being checked',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'These characters have no glyph with ink in $kFamily, so a '
          'label containing one renders that character in the system face '
          'and the rest in the pixel face. Draw them in $kToolPath and '
          'rebuild, or add the script to kFallbackAllowed with a reason.\n'
          '${offenders.entries.map((e) => '  ${e.key}: ${e.value.take(3).join(', ')}').join('\n')}',
    );
  });
}

String _name(int codepoint) =>
    'U+${codepoint.toRadixString(16).toUpperCase().padLeft(4, '0')} '
    '${String.fromCharCode(codepoint)}';

String? _fallbackAllowed(int codepoint) {
  for (final (start, end, why) in kFallbackAllowed) {
    if (codepoint >= start && codepoint <= end) return why;
  }
  return null;
}

bool _isWhitespaceOrControl(int codepoint) =>
    codepoint < 0x20 ||
    codepoint == 0x7F ||
    codepoint == 0x200B ||
    codepoint == 0x200E ||
    codepoint == 0x200F ||
    codepoint == 0xFEFF;

/// The parts of a TrueType file this test needs: which codepoints map to which
/// glyph, and which glyphs have an outline.
class _Font {
  _Font(this.cmap, this._inked);

  final Map<int, int> cmap;
  final Set<int> _inked;

  bool hasInk(int glyphId) => _inked.contains(glyphId);

  static _Font parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final tables = <String, (int, int)>{};
    final tableCount = data.getUint16(4);
    for (var i = 0; i < tableCount; i++) {
      final record = 12 + i * 16;
      final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
      tables[tag] = (data.getUint32(record + 8), data.getUint32(record + 12));
    }
    return _Font(
      _readCmap(data, bytes, _need(tables, 'cmap').$1),
      _readInkedGlyphs(data, tables),
    );
  }

  static (int, int) _need(Map<String, (int, int)> tables, String tag) {
    final entry = tables[tag];
    if (entry == null) throw StateError('the font has no $tag table');
    return entry;
  }

  /// Glyph ids whose `loca` entry has a non-zero length. A glyph with a
  /// zero-length entry is blank - which is what an all-paper bitmap produces,
  /// and what nothing else in the toolchain would notice.
  static Set<int> _readInkedGlyphs(
    ByteData data,
    Map<String, (int, int)> tables,
  ) {
    final head = _need(tables, 'head').$1;
    final maxp = _need(tables, 'maxp').$1;
    final loca = _need(tables, 'loca').$1;
    final longFormat = data.getInt16(head + 50) == 1;
    final glyphCount = data.getUint16(maxp + 4);

    int offsetAt(int index) => longFormat
        ? data.getUint32(loca + index * 4)
        : data.getUint16(loca + index * 2) * 2;

    final inked = <int>{};
    for (var glyph = 0; glyph < glyphCount; glyph++) {
      if (offsetAt(glyph + 1) > offsetAt(glyph)) inked.add(glyph);
    }
    return inked;
  }

  /// The codepoint-to-glyph mapping, from the format 4 cmap subtable.
  ///
  /// The font has three subtables - two format 4, and an 8 bit Macintosh
  /// format 6 that could not carry an accented letter at all. Only format 4 is
  /// read, and an unexpected format throws rather than returning a partial
  /// mapping: a mapping with holes in it would make the ARB check above report
  /// fewer offenders, which is a weaker assertion that still passes.
  static Map<int, int> _readCmap(ByteData data, Uint8List bytes, int start) {
    final subtableCount = data.getUint16(start + 2);
    var best = -1;
    for (var i = 0; i < subtableCount; i++) {
      final record = start + 4 + i * 8;
      final platform = data.getUint16(record);
      final encoding = data.getUint16(record + 2);
      final offset = start + data.getUint32(record + 4);
      if ((platform == 3 && encoding == 1) ||
          (platform == 0 && encoding == 3)) {
        best = offset;
        if (platform == 3) break;
      }
    }
    if (best < 0) throw StateError('no Unicode cmap subtable');

    final format = data.getUint16(best);
    if (format != 4) throw StateError('cmap subtable is format $format, not 4');
    final end = best + data.getUint16(best + 2);

    final segments = data.getUint16(best + 6) ~/ 2;
    final endCodes = best + 14;
    final startCodes = endCodes + segments * 2 + 2;
    final deltas = startCodes + segments * 2;
    final rangeOffsets = deltas + segments * 2;

    final mapping = <int, int>{};
    for (var segment = 0; segment < segments; segment++) {
      final last = data.getUint16(endCodes + segment * 2);
      final first = data.getUint16(startCodes + segment * 2);
      if (first > last) continue;
      final delta = data.getInt16(deltas + segment * 2);
      final rangeOffsetAt = rangeOffsets + segment * 2;
      final rangeOffset = data.getUint16(rangeOffsetAt);

      for (var code = first; code <= last && code != 0xFFFF; code++) {
        final int glyph;
        if (rangeOffset == 0) {
          glyph = (code + delta) & 0xFFFF;
        } else {
          final at = rangeOffsetAt + rangeOffset + (code - first) * 2;
          // Bounded by the subtable, not the file: a read past the subtable
          // would return whatever the next table holds and report codepoints
          // as covered that are not.
          if (at + 1 >= end || at + 1 >= bytes.length) {
            throw StateError('cmap subtable is truncated at offset $at');
          }
          final raw = data.getUint16(at);
          glyph = raw == 0 ? 0 : (raw + delta) & 0xFFFF;
        }
        if (glyph != 0) mapping[code] = glyph;
      }
    }
    return mapping;
  }
}
