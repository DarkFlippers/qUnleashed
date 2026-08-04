import 'nested_models.dart';

/// Parser for the Flipper `.nested.log` format, e.g.
///
///   Sec 10 key A cuid 7c30d979 nt0 214904f0 ks0 c03823d1 par0 0000 \
///     nt1 f69baa3a ks1 8a2107ad par1 1010 dist 0
///   Sec 0 key A cuid 5bcbb2e4 nt0 a0bbe1ef ks0 c70d97e3 par0 1110 dist 0
///
/// Lines carry one `nt/ks/par` sample (static-encrypted) or two (weak nested),
/// optionally followed by `dist`. Values are hex except `sec`/`dist` (decimal),
/// `key` (`A`/`B`) and `par` (a 4-char binary string).
class NestedNonceParser {
  const NestedNonceParser._();

  static List<NestedNonce> parse(String text) {
    return text
        .split('\n')
        .map(_parseLine)
        .whereType<NestedNonce>()
        .toList(growable: false);
  }

  static NestedNonce? _parseLine(String line) {
    if (line.trim().isEmpty) return null;

    final tokens = line.trim().split(RegExp(r'\s+'));
    final fields = <String, String>{};
    for (var i = 0; i + 1 < tokens.length; i += 2) {
      fields[tokens[i].toLowerCase()] = tokens[i + 1];
    }

    final sector = int.tryParse(fields['sec'] ?? '');
    final keyType = _parseKeyType(fields['key']);
    final cuid = _parseHex(fields['cuid']);
    if (sector == null || keyType == null || cuid == null) return null;

    final samples = <NestedSample>[];
    for (var index = 0; index < 2; index++) {
      final sample = _parseSample(fields, index);
      if (sample == null) break;
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
    final nt = _parseHex(fields['nt$index']);
    final ks = _parseHex(fields['ks$index']);
    if (nt == null || ks == null) return null;
    return NestedSample(nt: nt, ks: ks, par: _parseBinary(fields['par$index']));
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

  static int? _parseHex(String? value) =>
      value == null ? null : int.tryParse(value, radix: 16);

  static int _parseBinary(String? value) =>
      value == null ? 0 : (int.tryParse(value, radix: 2) ?? 0);
}
