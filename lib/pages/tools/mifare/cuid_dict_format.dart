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
/// Throws an [ArgumentError] rather than writing an entry that does not fit,
/// in release builds too. The width is not self-policing on the device:
/// `keys_dict_read_key_line` cuts every line down to 14 characters *before*
/// checking that it is 14, so a short line is dropped — which is why a
/// dictionary of bare 12-digit keys reads as empty — but an over-wide one is
/// accepted with its tail cut off and lands on an unrelated key index. A
/// malformed entry is therefore worse than no dictionary at all.
void writeCuidDictEntry(
  Uint8List out,
  int offset, {
  required int sector,
  required bool isKeyA,
  required int key,
}) {
  final keyIndex = sector * 2 + (isKeyA ? 0 : 1);
  if (keyIndex < 0 || keyIndex > 0xFF) {
    throw ArgumentError.value(sector, 'sector', 'no one-byte CUID key index');
  }
  if (key < 0 || key > 0xFFFFFFFFFFFF) {
    throw ArgumentError.value(key, 'key', 'not a 48-bit MIFARE key');
  }
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

/// One card's finished dictionary, plus what would make it incomplete on the
/// device. Both gap lists name sector keys as `12A` / `7B`.
class CuidDictBody {
  const CuidDictBody({
    required this.bytes,
    required this.entries,
    required this.skippedKeys,
    required this.cappedKeys,
  });

  /// The dictionary body, ready to write to [cuidDictPath].
  final Uint8List bytes;

  /// Number of entries in [bytes], not of distinct keys: one key value
  /// recovered for two different sector keys is two entries, since the device
  /// only tries a candidate against the key index it is filed under.
  final int entries;

  /// Sector keys that yielded no candidates at all. The device indexes the
  /// dictionary by key index and skips an index with no entries, so it will not
  /// attack these at all — indistinguishable, on screen, from an index whose
  /// candidates were merely all wrong.
  final List<String> skippedKeys;

  /// Sector keys whose candidate list hit the generator's cap and was cut
  /// short, so the real key may not be among the entries written.
  final List<String> cappedKeys;

  bool get isEmpty => entries == 0;

  bool get isComplete => skippedKeys.isEmpty && cappedKeys.isEmpty;
}

/// Assembles one card's dictionary entry by entry, recording the gaps that
/// would leave part of the card unattacked.
///
/// Candidates are appended as bytes rather than accumulated as strings: at the
/// millions of entries a full 4K card can produce, a string body costs an extra
/// copy plus the UTF-8 encoder's 3x scratch buffer, which is enough to exhaust
/// a mobile isolate's heap.
class CuidDictBuilder {
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  final List<String> _skipped = [];
  final List<String> _capped = [];
  int _entries = 0;

  /// Files every candidate in [keys] under the key index of [sector]/[isKeyA].
  ///
  /// [keys] is read in full before this returns, so passing a view over a
  /// buffer that the next call overwrites is safe. Pass [atCapacity] when the
  /// generator filled its output buffer: the list was cut short and may no
  /// longer contain the real key.
  void add({
    required int sector,
    required bool isKeyA,
    required Uint64List keys,
    bool atCapacity = false,
  }) {
    final label = '$sector${isKeyA ? 'A' : 'B'}';
    if (keys.isEmpty) {
      _skipped.add(label);
      return;
    }
    if (atCapacity) _capped.add(label);
    final chunk = Uint8List(keys.length * cuidDictEntryBytes);
    for (var i = 0; i < keys.length; i++) {
      writeCuidDictEntry(
        chunk,
        i * cuidDictEntryBytes,
        sector: sector,
        isKeyA: isKeyA,
        key: keys[i],
      );
    }
    _bytes.add(chunk);
    _entries += keys.length;
  }

  /// Takes the finished body. The builder must not be used afterwards.
  CuidDictBody build() => CuidDictBody(
    bytes: _bytes.takeBytes(),
    entries: _entries,
    skippedKeys: List.unmodifiable(_skipped),
    cappedKeys: List.unmodifiable(_capped),
  );
}
