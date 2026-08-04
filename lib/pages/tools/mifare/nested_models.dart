/// Parsed representation of the Flipper `.nested.log` file produced by the
/// firmware's nested nonce collector.
///
/// The firmware resolves the plaintext tag nonce on-device, so each sample
/// carries a plaintext nonce [nt] and the first keystream word [ks]
/// (`ks = nt_enc ^ nt`). A line has either:
///   * two samples with distinct nonces — a weak-PRNG nested collection,
///     uniquely recoverable, or
///   * one sample (or two identical nonces) — an FM11RF08S static-encrypted
///     nonce, which needs a per-CUID candidate dictionary verified against the
///     tag on the device (handled by a later step).
library;

enum NestedKeyType { a, b }

enum NestedAttackKind {
  /// Two samples with distinct nonces — uniquely recoverable on its own.
  weakNested,

  /// Single static-encrypted sample — under-constrained without extra data.
  staticEncrypted,
}

class NestedSample {
  const NestedSample({required this.nt, required this.ks, required this.par})
    : assert(nt >= 0 && nt <= 0xFFFFFFFF, 'nt is a 32-bit word'),
      assert(ks >= 0 && ks <= 0xFFFFFFFF, 'ks is a 32-bit word'),
      assert(par >= 0 && par <= 0xF, 'par is four bits');

  /// Plaintext tag nonce, resolved on-device by the firmware.
  final int nt;

  /// First keystream word, `nt_enc ^ nt`.
  final int ks;

  /// Four parity bits, most-significant first in bits 3..0.
  final int par;
}

class NestedNonce {
  NestedNonce({
    required this.sector,
    required this.keyType,
    required this.cuid,
    required List<NestedSample> samples,
    this.dist,
  }) : assert(
         samples.isNotEmpty && samples.length <= 2,
         'a nested line carries one or two samples',
       ),
       samples = List.unmodifiable(samples);

  final int sector;
  final NestedKeyType keyType;

  /// Card UID (the `cuid` field), used as the crypto1 feed-in `uid ^ nt`.
  final int cuid;

  /// The line's one or two samples. Unmodifiable; the 1–2 cardinality
  /// invariant is enforced at construction.
  final List<NestedSample> samples;

  /// PRNG distance recorded by the firmware, or null when the line omits it.
  final int? dist;

  /// True only when there are two samples with *distinct* nonces — the case a
  /// weak-nested key is uniquely recoverable from. Two identical nonces add no
  /// extra constraint, so such a line is treated as static-encrypted instead.
  bool get hasPair => samples.length >= 2 && samples[0].nt != samples[1].nt;

  NestedAttackKind get kind =>
      hasPair ? NestedAttackKind.weakNested : NestedAttackKind.staticEncrypted;

  String get sectorName => sector.toString();

  String get keyName => keyType == NestedKeyType.a ? 'A' : 'B';
}
