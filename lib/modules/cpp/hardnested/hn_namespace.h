//-----------------------------------------------------------------------------
// Namespace this lib's vendored crapto1/crypto1/bucketsort symbols with an `hn_`
// prefix. They are identical (Proxmark3-derived) to the crapto1 in
// qunleashed_mfkey32, and on Apple every FFI library is linked into the single
// Runner binary - without renaming, the 17 shared symbols (crypto1_word,
// lfsr_recovery32, ...) would be duplicate-symbol link errors.
//
// Force-included into every hardnested source (see CMakeLists.txt / the Apple
// podspec), so both the definitions and all internal callers are renamed
// consistently. The only exported symbol - qunleashed_hardnested_recover - is
// not touched, so the FFI surface is unchanged.
//-----------------------------------------------------------------------------
#ifndef QUNLEASHED_HN_NAMESPACE_H
#define QUNLEASHED_HN_NAMESPACE_H

#define crypto1_bit hn_crypto1_bit
#define crypto1_byte hn_crypto1_byte
#define crypto1_create hn_crypto1_create
#define crypto1_deinit hn_crypto1_deinit
#define crypto1_destroy hn_crypto1_destroy
#define crypto1_get_lfsr hn_crypto1_get_lfsr
#define crypto1_init hn_crypto1_init
#define crypto1_word hn_crypto1_word
#define lfsr_common_prefix hn_lfsr_common_prefix
#define lfsr_prefix_ks hn_lfsr_prefix_ks
#define lfsr_recovery32 hn_lfsr_recovery32
#define lfsr_recovery64 hn_lfsr_recovery64
#define lfsr_rollback_bit hn_lfsr_rollback_bit
#define lfsr_rollback_byte hn_lfsr_rollback_byte
#define lfsr_rollback_word hn_lfsr_rollback_word
#define prng_successor hn_prng_successor
#define bucket_sort_intersect hn_bucket_sort_intersect

#endif // QUNLEASHED_HN_NAMESPACE_H
