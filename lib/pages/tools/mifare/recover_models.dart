import 'mfkey32_models.dart';

/// Where a recovered key's nonces came from.
enum RecoverSource {
  /// `.mfkey32.log` — the key a *reader* used against an emulated card.
  reader,

  /// `.nested.log` — keys read off a physical *tag*.
  tag,
}

/// Which attack / tag type produced an entry. `staticNonce` and `weakNested`
/// both solve with the same crapto1 nested math; they differ only by whether the
/// tag's nonce advances (`dist != 0` = weak, `dist == 0` = static).
enum RecoverKind {
  mfkey32,
  weakNested,
  staticNonce,
  staticEncrypted,
  hardnested,
}

/// One row of the grouped recovery summary (grouped in the UI by
/// source → card (cuid) → sector/key).
class RecoverEntry {
  const RecoverEntry({
    required this.source,
    required this.kind,
    required this.cuid,
    this.sectorName,
    this.keyName,
    this.key,
    this.isNew,
    this.candidateCount,
    this.note,
  });

  final RecoverSource source;
  final RecoverKind kind;
  final int cuid;

  /// Sector / key labels for a concrete key result. Null for a per-card
  /// static-encrypted candidate summary.
  final String? sectorName;
  final String? keyName;

  /// Recovered 12-hex-digit key, or null when not resolved to one key
  /// (static-encrypted candidates, or a failed / too-few-nonces hardnested group).
  final String? key;

  /// Whether [key] was new to the user + system dictionaries (true) or already
  /// known (false); null when there is no resolved key. Decided at recovery time
  /// so the "new / already in dict" tag is correct during progress, not only in
  /// the final summary.
  final bool? isNew;

  /// Static-encrypted: number of candidate keys written to `mf_classic_dict_<cuid>.nfc`.
  final int? candidateCount;

  /// Extra context (e.g. "too few nonces — collect more", or a write failure).
  final String? note;

  String get cuidHex => formatCuid(cuid).toUpperCase();
}
