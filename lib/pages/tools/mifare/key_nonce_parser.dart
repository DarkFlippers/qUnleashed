import 'mfkey32_models.dart';

const _keySec = 'sec';
const _keyKey = 'key';
const _keyUid = 'cuid';
const _keyNt0 = 'nt0';
const _keyAr0 = 'ar0';
const _keyNr0 = 'nr0';
const _keyNt1 = 'nt1';
const _keyNr1 = 'nr1';
const _keyAr1 = 'ar1';

class KeyNonceParser {
  const KeyNonceParser._();

  static List<MfKey32Nonce> parse(String text) {
    return text.split('\n').map(_parseLine).whereType<MfKey32Nonce>().toList();
  }

  // Sample: Sec 2 key A cuid 2a234f80 nt0 55721809 nr0 ce9985f6 ar0 772f55be nt1 a27173f2 nr1 e386b505 ar1 5fa65203
  static MfKey32Nonce? _parseLine(String line) {
    if (line.trim().isEmpty) return null;
    final blocks = line.split(' ').map((e) => e.toLowerCase()).toList();
    final params = <String, String>{};
    for (var i = 0; i <= blocks.length - 1; i += 2) {
      final key = i < blocks.length ? blocks[i] : null;
      final value = i + 1 < blocks.length ? blocks[i + 1] : null;
      if (key != null && value != null) {
        params[key.toLowerCase()] = value;
      }
    }

    final sectorName = params[_keySec];
    final keyName = params[_keyKey];
    final uid = _parseHex(params[_keyUid]);
    final nt0 = _parseHex(params[_keyNt0]);
    final nr0 = _parseHex(params[_keyNr0]);
    final ar0 = _parseHex(params[_keyAr0]);
    final nt1 = _parseHex(params[_keyNt1]);
    final nr1 = _parseHex(params[_keyNr1]);
    final ar1 = _parseHex(params[_keyAr1]);

    if (sectorName == null ||
        keyName == null ||
        uid == null ||
        nt0 == null ||
        nr0 == null ||
        ar0 == null ||
        nt1 == null ||
        nr1 == null ||
        ar1 == null) {
      return null;
    }

    return MfKey32Nonce(
      sectorName: sectorName,
      keyName: keyName,
      uid: uid,
      nt0: nt0,
      nr0: nr0,
      ar0: ar0,
      nt1: nt1,
      nr1: nr1,
      ar1: ar1,
    );
  }

  static int? _parseHex(String? value) {
    if (value == null) return null;
    return int.tryParse(value, radix: 16);
  }
}
