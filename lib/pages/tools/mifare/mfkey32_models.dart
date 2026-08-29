/// A reader (mfkey32) nonce pair parsed from `.mfkey32.log`.
class MfKey32Nonce {
  const MfKey32Nonce({
    required this.sectorName,
    required this.keyName,
    required this.uid,
    required this.nt0,
    required this.nr0,
    required this.ar0,
    required this.nt1,
    required this.nr1,
    required this.ar1,
  });

  final String sectorName;
  final String keyName;
  final int uid;
  final int nt0;
  final int nr0;
  final int ar0;
  final int nt1;
  final int nr1;
  final int ar1;
}

/// Formats a recovered 48-bit MIFARE Classic key as 12 uppercase hex digits.
String formatMifareKey(int key) =>
    key.toRadixString(16).padLeft(12, '0').toUpperCase();

/// Formats a card UID as 8 lowercase hex digits - the on-device
/// `mf_classic_dict_<cuid>.nfc` filename convention.
String formatCuid(int cuid) => cuid.toRadixString(16).padLeft(8, '0');

/// Formats one entry of a per-card candidate dictionary
/// (`mf_classic_dict_<cuid>.nfc`) as 14 uppercase hex digits.
///
/// The firmware sizes these entries at `sizeof(MfClassicKey) + 1` bytes: a
/// one-byte key index ahead of the 6-byte [key]. The index is `sector * 2` for
/// key A and one more for key B, and a candidate is only ever tried against the
/// one (sector, key type) it names — so which key the candidate belongs to has
/// to travel with it.
///
/// The width is not self-policing. `keys_dict_read_key_line` cuts every line
/// down to 14 characters *before* checking that it is 14, so a short line is
/// dropped — which is why a dictionary of bare 12-digit keys reads as empty --
/// but an over-wide one is accepted with its tail cut off and lands on an
/// unrelated key index. The asserts hold both operands to the widths that make
/// this exactly 14.
String formatCuidDictEntry({
  required int sector,
  required bool isKeyA,
  required int key,
}) {
  assert(sector >= 0 && sector < 40, 'sector is a MIFARE Classic sector');
  assert(key >= 0 && key <= 0xFFFFFFFFFFFF, 'key is a 48-bit value');
  final keyIndex = sector * 2 + (isKeyA ? 0 : 1);
  return '${keyIndex.toRadixString(16).padLeft(2, '0').toUpperCase()}'
      '${formatMifareKey(key)}';
}
