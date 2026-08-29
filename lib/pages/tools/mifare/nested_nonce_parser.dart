import 'nested_models.dart';

/// A parsed `.nested.log`: the usable nonces, and how many non-blank lines had
/// to be dropped as corrupt. The caller surfaces the drops rather than quietly
/// attacking a subset of the card.
typedef NestedLog = ({List<NestedNonce> nonces, int droppedLines});

/// Parser for the Flipper `.nested.log` format. Each record is a single line;
/// two-sample (weak-nested) lines just carry more fields:
///
///   Sec 10 key A cuid 7c30d979 nt0 214904f0 ks0 c03823d1 par0 0000 nt1 f69baa3a ks1 8a2107ad par1 1010 dist 0
///   Sec 0 key A cuid 5bcbb2e4 nt0 a0bbe1ef ks0 c70d97e3 par0 1110 dist 0
///
/// Lines carry one `nt/ks/par` sample (static-encrypted) or two (weak nested),
/// optionally followed by `dist`. Values are hex except `sec`/`dist` (decimal),
/// `key` (`A`/`B`) and `par` (a 4-char binary string).
class NestedNonceParser {
  const NestedNonceParser._();

  static NestedLog parse(String text) {
    final lines = text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    final nonces = lines
        .map(_parseLine)
        .whereType<NestedNonce>()
        .toList(growable: false);
    return (nonces: nonces, droppedLines: lines.length - nonces.length);
  }

  static final RegExp _whitespace = RegExp(r'\s+');

  static NestedNonce? _parseLine(String line) {
    final tokens = line.trim().split(_whitespace);
    final fields = <String, String>{};
    for (var i = 0; i + 1 < tokens.length; i += 2) {
      fields[tokens[i].toLowerCase()] = tokens[i + 1];
    }

    // A sector no card has is corrupt on its face, and it also breaks the
    // per-card dictionary's fixed entry width - see `writeCuidDictEntry`.
    final sector = int.tryParse(fields['sec'] ?? '');
    final keyType = _parseKeyType(fields['key']);
    final cuid = _parseWord32(fields['cuid']);
    if (sector == null || sector < 0 || sector >= mifareClassicMaxSectors) {
      return null;
    }
    if (keyType == null || cuid == null) return null;

    final samples = <NestedSample>[];
    for (var index = 0; index < 2; index++) {
      final present =
          fields.containsKey('nt$index') || fields.containsKey('ks$index');
      final sample = _parseSample(fields, index);
      if (sample == null) {
        // Fields for this sample were present but unparseable/out of range: the
        // line is corrupt, so drop it rather than silently keeping a partial,
        // mis-classified nonce. An absent sample simply ends the line.
        if (present) return null;
        break;
      }
      samples.add(sample);
    }
    if (samples.isEmpty) return null;

    return NestedNonce(
      sector: sector,
      keyType: keyType,
      cuid: cuid,
      samples: samples,
      dist: int.tryParse(fields['dist'] ?? ''),
    );
  }

  static NestedSample? _parseSample(Map<String, String> fields, int index) {
    final nt = _parseWord32(fields['nt$index']);
    final ks = _parseWord32(fields['ks$index']);
    final par = _parseParity(fields['par$index']);
    if (nt == null || ks == null || par == null) return null;
    return NestedSample(nt: nt, ks: ks, par: par);
  }

  static NestedKeyType? _parseKeyType(String? value) {
    switch (value?.toUpperCase()) {
      case 'A':
        return NestedKeyType.a;
      case 'B':
        return NestedKeyType.b;
      default:
        return null;
    }
  }

  /// Parses a hex field, rejecting anything outside an unsigned 32-bit word:
  /// `int.tryParse(radix: 16)` accepts a leading `-` and wraps a 16-digit value
  /// to a negative int, so both ends have to be bounded.
  static int? _parseWord32(String? value) {
    final parsed = value == null ? null : int.tryParse(value, radix: 16);
    if (parsed == null || parsed < 0 || parsed > 0xFFFFFFFF) return null;
    return parsed;
  }

  /// Parses the four parity bits the firmware always writes as four binary
  /// digits. Absent or malformed is a corrupt line, never a zero: parity drives
  /// the candidate filter, so a wrong value keeps the wrong half of the
  /// candidate space and the real key can never be among what we generate.
  static int? _parseParity(String? value) {
    if (value == null || value.length != 4) return null;
    final parsed = int.tryParse(value, radix: 2);
    if (parsed == null || parsed < 0 || parsed > 0xF) return null;
    return parsed;
  }
}
