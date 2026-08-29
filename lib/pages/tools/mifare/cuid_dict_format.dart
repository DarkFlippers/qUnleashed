/// The per-card candidate dictionary the static-encrypted attack leaves on the
/// device for on-tag verification: `nfc/assets/mf_classic_dict_<cuid>.nfc`, one
/// entry per line. A single owner for the on-device format, so the device
/// write, the UI label and the entry encoding cannot drift apart.
library;

import 'dart:typed_data';

import 'mfkey32_models.dart';

String cuidDictFileName(int cuid) => 'mf_classic_dict_${formatCuid(cuid)}.nfc';

String cuidDictPath(int cuid) => '/ext/nfc/assets/${cuidDictFileName(cuid)}';

/// Bytes one entry occupies: 14 hex digits and the newline the reader splits on.
const cuidDictEntryBytes = 15;

const _hexDigits = '0123456789ABCDEF';

/// Writes one entry - 14 uppercase hex digits and a newline - into [out] at
/// [offset], which must leave [cuidDictEntryBytes] of room.
///
/// The firmware sizes these entries at `sizeof(MfClassicKey) + 1` bytes: a
/// one-byte key index ahead of the 6-byte [key]. The index is `sector * 2` for
/// key A and one more for key B, and a candidate is only ever tried against the
/// one (sector, key type) it names — so which key a candidate belongs to has to
/// travel with it.
///
/// The width is not self-policing. `keys_dict_read_key_line` cuts every line
/// down to 14 characters *before* checking that it is 14, so a short line is
/// dropped — which is why a dictionary of bare 12-digit keys reads as empty @
/// but an over-wide one is accepted with its tail cut off and lands on an
/// unrelated key index. Hence the asserts: they hold the two operands to the
/// widths that keep an entry at exactly 14 digits.
void writeCuidDictEntry(
  Uint8List out,
  int offset, {
  required int sector,
  required bool isKeyA,
  required int key,
}) {
  final keyIndex = sector * 2 + (isKeyA ? 0 : 1);
  assert(keyIndex >= 0 && keyIndex <= 0xFF, 'key index is one byte');
  assert(key >= 0 && key <= 0xFFFFFFFFFFFF, 'key is a 48-bit value');
  out[offset] = _hexDigits.codeUnitAt((keyIndex >> 4) & 0xF);
  out[offset + 1] = _hexDigits.codeUnitAt(keyIndex & 0xF);
  for (var i = 0, shift = 44; shift >= 0; i++, shift -= 4) {
    out[offset + 2 + i] = _hexDigits.codeUnitAt((key >> shift) & 0xF);
  }
  out[offset + 14] = 0x0A;
}

/// The same entry as a string, without the trailing newline - the readable form
/// of [writeCuidDictEntry], and what the format is pinned against in tests.
String formatCuidDictEntry({
  required int sector,
  required bool isKeyA,
  required int key,
}) {
  final out = Uint8List(cuidDictEntryBytes);
  writeCuidDictEntry(out, 0, sector: sector, isKeyA: isKeyA, key: key);
  return String.fromCharCodes(out, 0, cuidDictEntryBytes - 1);
}
