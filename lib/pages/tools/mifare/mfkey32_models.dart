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
