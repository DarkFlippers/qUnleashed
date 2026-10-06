//-----------------------------------------------------------------------------
// Copyright (C) 2016, 2017 by piwi
//
// This code is licensed to you under the terms of the GNU GPL, version 2 or,
// at your option, any later version. See the LICENSE.txt file for the text of
// the license.
//-----------------------------------------------------------------------------
// Implements a card only attack based on crypto text (encrypted nonces
// received during a nested authentication) only. Unlike other card only
// attacks this doesn't rely on implementation errors but only on the
// inherent weaknesses of the crypto1 cypher. Described in
//   Carlo Meijer, Roel Verdult, "Ciphertext-only Cryptanalysis on Hardened
//   Mifare Classic Cards" in Proceedings of the 22nd ACM SIGSAC Conference on
//   Computer and Communications Security, 2015
//-----------------------------------------------------------------------------
//
// brute forcing is based on @aczids bitsliced brute forcer
// https://github.com/aczid/crypto1_bs with some modifications. Mainly:
// - don't rollback. Start with 2nd byte of nonce instead
// - reuse results of filter subfunctions
// - reuse results of previous nonces if some first bits are identical
//
//-----------------------------------------------------------------------------
// aczid's Copyright notice:
//
// Bit-sliced Crypto-1 brute-forcing implementation
// Builds on the data structures returned by CraptEV1 craptev1_get_space(nonces, threshold, uid)
/*
Copyright (c) 2015-2016 Aram Verstegen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

#ifndef HARDNESTED_BF_CORE_H__
#define HARDNESTED_BF_CORE_H__

#include "hardnested_bruteforce.h" // statelist_t

#if (defined(__i386__) || defined(__x86_64__)) && \
    (!defined(__APPLE__) ||                       \
     (defined(__APPLE__) && (__clang_major__ > 8 || __clang_major__ == 8 && __clang_minor__ >= 1)))
#define COMPILER_HAS_SIMD_X86
#if defined(COMPILER_HAS_SIMD_X86) && ((__GNUC__ >= 5) && (__GNUC__ > 5 || __GNUC_MINOR__ > 2))
#define COMPILER_HAS_SIMD_AVX512
#endif
#endif

// ARM64 mandates implementation of NEON
#if defined(__arm64__) || defined(__aarch64__)
#define COMPILER_HAS_SIMD_NEON
#define arm_has_neon() (true)
// ARMv7 or older, NEON is optional and autodetection is difficult
#elif defined(__ARM_NEON)
#define COMPILER_HAS_SIMD_NEON
#define arm_has_neon() (false)
#endif

// Set by the build for every translation unit when it compiles the per-ISA
// variants with a second toolchain. Without it the dispatcher is compiled by
// MSVC, whose own predefined macros say nothing about what the *variants* were
// built for - so the enum below would not even have a name for AVX2 while
// four objects implementing it sat in the same library.
#if defined(QUNLEASHED_HN_SIMD_VARIANTS) && !defined(COMPILER_HAS_SIMD_X86)
#define COMPILER_HAS_SIMD_X86
#define COMPILER_HAS_SIMD_AVX512
#endif

// Which variant the translation unit including this is being compiled as.
//
// One source of truth for the names, because two places need to agree on them:
// the core, which defines the pair, and the dispatcher, which has to be able to
// name the baseline the same toolchain produced when no variants were built.
#if defined(__AVX512F__)
#define HN_CRACK_VARIANT crack_states_bitsliced_AVX512
#define HN_TEST_VARIANT bitslice_test_nonces_AVX512
#elif defined(__AVX2__)
#define HN_CRACK_VARIANT crack_states_bitsliced_AVX2
#define HN_TEST_VARIANT bitslice_test_nonces_AVX2
#elif defined(__AVX__)
#define HN_CRACK_VARIANT crack_states_bitsliced_AVX
#define HN_TEST_VARIANT bitslice_test_nonces_AVX
#elif defined(__ARM_NEON) || defined(__aarch64__)
#define HN_CRACK_VARIANT crack_states_bitsliced_NEON
#define HN_TEST_VARIANT bitslice_test_nonces_NEON
#elif defined(__SSE2__)
#define HN_CRACK_VARIANT crack_states_bitsliced_SSE2
#define HN_TEST_VARIANT bitslice_test_nonces_SSE2
#else
#define HN_CRACK_VARIANT crack_states_bitsliced_NOSIMD
#define HN_TEST_VARIANT bitslice_test_nonces_NOSIMD
#endif

typedef enum
{
    SIMD_AUTO,
#if defined(COMPILER_HAS_SIMD_AVX512)
    SIMD_AVX512,
#endif
#if defined(COMPILER_HAS_SIMD_X86)
    SIMD_AVX2,
    SIMD_AVX,
    SIMD_SSE2,
    SIMD_MMX,
#endif
#if defined(COMPILER_HAS_SIMD_NEON)
    SIMD_NEON,
#endif
    SIMD_NONE,
} SIMDExecInstr;
void SetSIMDInstr(SIMDExecInstr instr);

uint64_t crack_states_bitsliced(uint32_t cuid, uint8_t *best_first_bytes, statelist_t *p, uint32_t *keys_found, uint64_t *num_keys_tested, uint32_t nonces_to_bruteforce, uint8_t *bf_test_nonce_2nd_byte, noncelist_t *nonces);
void bitslice_test_nonces(uint32_t nonces_to_bruteforce, uint32_t *bf_test_nonce, uint8_t *bf_test_nonce_par);

#endif
