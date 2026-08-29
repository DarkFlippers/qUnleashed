/// The per-card candidate dictionary the static-encrypted attack leaves on the
/// device for on-tag verification: `nfc/assets/mf_classic_dict_<cuid>.nfc`, one
/// entry per line. A single owner for the on-device format, so the device
/// write, the UI label and the entry encoding cannot drift apart.
library;

import 'dart:typed_data';

import 'mfkey32_models.dart';

/// The cuid is lowercase hex: the firmware builds the path it opens with
/// `%08lx` (`mf_classic_extra_scenes.c:236`), so an uppercase name is a file it
/// never looks for. `RecoverEntry.cuidHex` uppercases for display only.
String cuidDictFileName(int cuid) => 'mf_classic_dict_${formatCuid(cuid)}.nfc';

String cuidDictPath(int cuid) => '/ext/nfc/assets/${cuidDictFileName(cuid)}';

/// Bytes one entry occupies: 14 hex digits plus the newline, which the firmware
/// counts as the entry's 15th symbol rather than a separator
/// (`keys_dict.c:79-81`, `key_size_symbols = key_size * 2 + 1`).
const cuidDictEntryBytes = 15;

const _hexDigits = '0123456789ABCDEF';

/// Writes one entry - 14 uppercase hex digits and a newline - into [out] at
/// [offset], which must leave [cuidDictEntryBytes] of room.
///
/// The firmware sizes these entries at `sizeof(MfClassicKey) + 1` bytes
/// (`mf_classic_extra_scenes.c:258`): a one-byte key index ahead of the 6-byte
/// [key]. The index is `sector * 2` for key A and one more for key B, and a
/// candidate is only ever tried against the one (sector, key type) it names
/// (`mf_classic_extra_scenes.c:106,160-166`) — so which key a candidate
/// belongs to has to travel with it.
///
/// Throws an [ArgumentError] rather than writing an entry that does not fit, in
/// release builds too, because the width is not self-policing on the device.
/// `keys_dict_read_key_line` cuts every line down to 14 characters *before*
/// checking that it is 14 (`keys_dict.c:44,47`), so only a line of 13 or fewer
/// characters is dropped — which is why a dictionary of bare 12-digit keys
/// reads as empty. An over-wide line is accepted with its tail cut off and
/// lands on an unrelated key index, and a 13-digit line survives too, since the
/// retained newline counts toward the 14. A malformed entry is therefore worse
/// than no dictionary at all.
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
    required this.skippedKeys,
    required this.cappedKeys,
  });

  /// The dictionary body, ready to write to [cuidDictPath].
  final Uint8List bytes;

  /// Sector keys that yielded no candidates at all. The device never asks for
  /// an index with no entries (`mf_classic_extra_scenes.c:93-95`), so it will
  /// not attack these at all — indistinguishable, on screen, from an index
  /// whose candidates were merely all wrong.
  final List<String> skippedKeys;

  /// Sector keys whose candidate list was cut short at the generator's cap, so
  /// the real key may not be among the entries written.
  final List<String> cappedKeys;

  /// Number of entries in [bytes], not of distinct keys: one key value
  /// recovered for two different sector keys is two entries, because the device
  /// only tries a candidate against the key index it is filed under. Derived,
  /// so it cannot drift from what was actually written.
  int get entries => bytes.length ~/ cuidDictEntryBytes;

  bool get isEmpty => bytes.isEmpty;

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
  bool _built = false;

  /// Files every candidate in [keys] under the key index of [sector]/[isKeyA].
  ///
  /// [keys] is copied into a fresh chunk before this returns, so passing a view
  /// over a buffer the next call overwrites is safe. That copy is load-bearing:
  /// the internal [BytesBuilder] is `copy: false` and would otherwise retain
  /// the caller's list by reference. Pass [atCapacity] when the generator hit
  /// its output limit — the list was cut short and may no longer contain the
  /// real key.
  void add({
    required int sector,
    required bool isKeyA,
    required Uint64List keys,
    bool atCapacity = false,
  }) {
    if (_built) throw StateError('CuidDictBuilder was already built');
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
  }

  /// Takes the finished body. Terminal: [BytesBuilder.takeBytes] empties the
  /// buffer, so a second call would hand back a body that reports gaps it no
  /// longer contains the entries for.
  CuidDictBody build() {
    if (_built) throw StateError('CuidDictBuilder was already built');
    _built = true;
    return CuidDictBody(
      bytes: _bytes.takeBytes(),
      skippedKeys: List.unmodifiable(_skipped),
      cappedKeys: List.unmodifiable(_capped),
    );
  }
}
