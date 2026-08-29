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

/// MIFARE Classic tops out at 40 sectors (4K) - the firmware's
/// `MF_CLASSIC_TOTAL_SECTORS_MAX` (`mf_classic.h:27`).
const mifareClassicMaxSectors = 40;

/// Whether [sector] is one a MIFARE Classic card can actually have. One
/// spelling of the bound, so the parser and the model cannot drift apart.
bool isMifareSector(int sector) =>
    sector >= 0 && sector < mifareClassicMaxSectors;

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
      assert(par == null || (par >= 0 && par <= 0xF), 'par is four bits');

  /// Plaintext tag nonce, resolved on-device by the firmware.
  final int nt;

  /// First keystream word, `nt_enc ^ nt`.
  final int ks;

  /// Four parity bits, most-significant first in bits 3..0, or null when the
  /// line did not carry a usable `par` field.
  ///
  /// Only the single-sample attacks read it: static-encrypted uses the low bit
  /// to halve the candidate set, and hardnested consumes the whole nibble. A
  /// weak-nested pair recovers from `nt`/`ks` alone and verifies itself against
  /// its second sample, so it does not need parity at all — which is why the
  /// parser keeps such a line and drops a lone sample without one.
  final int? par;
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
       assert(isMifareSector(sector), 'sector is a MIFARE Classic sector'),
       assert(cuid >= 0 && cuid <= 0xFFFFFFFF, 'cuid is a 32-bit word'),
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

  /// Parity of the first sample, which the single-sample attacks need. The
  /// parser guarantees it is non-null whenever [hasPair] is false.
  int? get par => samples[0].par;

  NestedAttackKind get kind =>
      hasPair ? NestedAttackKind.weakNested : NestedAttackKind.staticEncrypted;

  String get sectorName => sector.toString();

  String get keyName => keyType == NestedKeyType.a ? 'A' : 'B';
}
