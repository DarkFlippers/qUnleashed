//-----------------------------------------------------------------------------
// Copyright (C) Proxmark3 contributors. See AUTHORS.md for details.
// Ported from the Proxmark3 project for the hardnested engine:
// https://github.com/RfidResearchGroup/proxmark3
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// See LICENSE.txt for the text of the license.
//-----------------------------------------------------------------------------
// Picking the brute-force implementation for the CPU this is running on.
//
// Its own translation unit because the core is compiled several times - once
// per instruction set - and exactly one copy of the pointers, the detection and
// the entry points may exist. It used to live at the bottom of the core, which
// was only safe while the core was compiled once.
//
// What it replaces: a `GetSIMDInstr` that returned `SIMD_NONE` unconditionally
// and a dispatch that assigned the scalar variant whatever the CPU could do.
// The vendoring note called that an intentional trade-off, since on MSVC the
// only variant that compiled *was* the scalar one, and on GCC/Clang the single
// variant already carried the compiler's baseline. With the variants actually
// built, the detection has to be real or they are dead weight in the library.
//-----------------------------------------------------------------------------

#include "hardnested_bf_core.h"

#include <stdbool.h>
#include <stdint.h>

#if defined(QUNLEASHED_HN_SIMD_VARIANTS) && defined(_MSC_VER)
#include <intrin.h>
#endif

typedef uint64_t crack_states_bitsliced_t(uint32_t, uint8_t *, statelist_t *, uint32_t *, uint64_t *, uint32_t, const uint8_t *, noncelist_t *);
typedef void bitslice_test_nonces_t(uint32_t, const uint32_t *, const uint8_t *);

crack_states_bitsliced_t HN_CRACK_VARIANT;
bitslice_test_nonces_t HN_TEST_VARIANT;

// One per object the build produces. No AVX512: see the note on the variant
// list in CMakeLists.txt - unmeasured, more lane padding wasted per bucket, and
// it downclocks on the client parts most likely to run this.
#if defined(QUNLEASHED_HN_SIMD_VARIANTS)
crack_states_bitsliced_t crack_states_bitsliced_AVX2;
crack_states_bitsliced_t crack_states_bitsliced_AVX;
crack_states_bitsliced_t crack_states_bitsliced_SSE2;
bitslice_test_nonces_t bitslice_test_nonces_AVX2;
bitslice_test_nonces_t bitslice_test_nonces_AVX;
bitslice_test_nonces_t bitslice_test_nonces_SSE2;
#endif

crack_states_bitsliced_t crack_states_bitsliced_dispatch;
bitslice_test_nonces_t bitslice_test_nonces_dispatch;

// pointers to functions:
crack_states_bitsliced_t *crack_states_bitsliced_function_p = &crack_states_bitsliced_dispatch;
bitslice_test_nonces_t *bitslice_test_nonces_function_p = &bitslice_test_nonces_dispatch;

static SIMDExecInstr intSIMDInstr = SIMD_AUTO;

void SetSIMDInstr(SIMDExecInstr instr)
{
    intSIMDInstr = instr;

    crack_states_bitsliced_function_p = &crack_states_bitsliced_dispatch;
    bitslice_test_nonces_function_p = &bitslice_test_nonces_dispatch;
}

#if defined(QUNLEASHED_HN_SIMD_VARIANTS)

// MSVC and x86 only, because that is the only configuration the build compiles
// variants for - CMakeLists.txt gates on both. An earlier draft carried a
// hand-written inline-asm cpuid/xgetbv path for GCC/Clang that no build ever
// compiled, which is the kind of dead code that gets trusted the day someone
// enables variants elsewhere. When that day comes, the thing to call is
// __builtin_cpu_supports, which performs the XCR0 check itself.
#if !defined(_MSC_VER) || !(defined(_M_X64) || defined(_M_IX86))
#error "the SIMD variants are built for MSVC on x86 only"
#endif

// Whether the OS has agreed to preserve the wide registers across a context
// switch. Asking the CPU alone is not enough: a CPU that implements AVX on an
// OS that does not save YMM faults on the first instruction, which is the
// crash that makes people distrust runtime dispatch.
static bool os_saves_ymm(void)
{
    int regs[4];
    __cpuid(regs, 1);
    // OSXSAVE, checked before xgetbv is executed - xgetbv itself faults on a
    // CPU that does not have it.
    if (((unsigned)regs[2] & (1u << 27)) == 0)
    {
        return false;
    }
    // XMM (bit 1) and YMM (bit 2), both, which is what AVX needs.
    const uint64_t ymm = 0x6;
    return ((uint64_t)_xgetbv(0) & ymm) == ymm;
}

static bool cpu_has(int leaf, int sub_leaf, int reg_index, int bit)
{
    int regs[4];
    // CPUID with EAX above the highest supported leaf returns that leaf's data
    // rather than zeros, so an unguarded leaf-7 read on an older part answers a
    // different question. Every CPU that could pass the AVX gates below also
    // has leaf 7, so this is belt and braces - the alternative is a guarantee
    // resting on the OS check happening to be evaluated first.
    __cpuid(regs, 0);
    if (regs[0] < leaf)
    {
        return false;
    }
    __cpuidex(regs, leaf, sub_leaf);
    // Unsigned, because bit 31 of a signed int is implementation-defined.
    return ((unsigned)regs[reg_index] & (1u << bit)) != 0;
}

static SIMDExecInstr GetSIMDInstr(void)
{
    // Highest first, and each one only after the OS check it needs. SSE2 is
    // baseline on x86-64, so on the only build that defines
    // QUNLEASHED_HN_SIMD_VARIANTS the scalar variant is unreachable in
    // practice; it stays as the `default:` below, which resolves to this
    // translation unit's own HN_CRACK_VARIANT - the MSVC scalar object.
    if (cpu_has(7, 0, 1, 5) && os_saves_ymm()) // leaf 7, EBX bit 5: AVX2
    {
        return SIMD_AVX2;
    }
    if (cpu_has(1, 0, 2, 28) && os_saves_ymm()) // leaf 1, ECX bit 28: AVX
    {
        return SIMD_AVX;
    }
    if (cpu_has(1, 0, 3, 26)) // leaf 1, EDX bit 26: SSE2
    {
        return SIMD_SSE2;
    }
    return SIMD_NONE;
}

#else

// No variants were built, so there is nothing to choose between: the one the
// compiler produced is the one that exists. Reporting it honestly rather than
// SIMD_NONE, because on GCC/Clang that single variant does carry the platform's
// baseline vectors - it is only MSVC's that is genuinely scalar.
static SIMDExecInstr GetSIMDInstr(void)
{
#if defined(__AVX2__)
    return SIMD_AVX2;
#elif defined(__AVX__)
    return SIMD_AVX;
#elif defined(COMPILER_HAS_SIMD_NEON)
    return SIMD_NEON;
#elif defined(__SSE2__)
    return SIMD_SSE2;
#else
    return SIMD_NONE;
#endif
}

#endif

SIMDExecInstr GetSIMDInstrAuto(void)
{
    SIMDExecInstr instr = intSIMDInstr;
    if (instr == SIMD_AUTO)
        return GetSIMDInstr();

    return instr;
}

// Picks the pair, and it has to be a pair. Each variant object is a separate
// translation unit with its own copy of the file-static nonce tables
// (bitsliced_encrypted_nonces, bs_ones and the rest), so bitslice_test_nonces_X
// fills variant X's tables and crack_states_bitsliced_X reads variant X's. Two
// independent switches would have let an edit to one case list and not the
// other mix the ISAs, and that failure is silent: the crack reads an all-zero
// nonce table and reports no key - a clean verdict about the user's card.
static void hn_select_variants(void)
{
#if defined(QUNLEASHED_HN_SIMD_VARIANTS)
    switch (GetSIMDInstrAuto())
    {
    case SIMD_AVX2:
        crack_states_bitsliced_function_p = &crack_states_bitsliced_AVX2;
        bitslice_test_nonces_function_p = &bitslice_test_nonces_AVX2;
        break;
    case SIMD_AVX:
        crack_states_bitsliced_function_p = &crack_states_bitsliced_AVX;
        bitslice_test_nonces_function_p = &bitslice_test_nonces_AVX;
        break;
    case SIMD_SSE2:
        crack_states_bitsliced_function_p = &crack_states_bitsliced_SSE2;
        bitslice_test_nonces_function_p = &bitslice_test_nonces_SSE2;
        break;
    default:
        crack_states_bitsliced_function_p = &HN_CRACK_VARIANT;
        bitslice_test_nonces_function_p = &HN_TEST_VARIANT;
        break;
    }
#else
    crack_states_bitsliced_function_p = &HN_CRACK_VARIANT;
    bitslice_test_nonces_function_p = &HN_TEST_VARIANT;
#endif
}

// Each dispatcher re-points the pointer it was reached through and then calls
// it. That is the memoization, not an indirection worth removing: the pointers
// start at these functions, so detection runs once per process rather than once
// per call.
uint64_t crack_states_bitsliced_dispatch(uint32_t cuid, uint8_t *best_first_bytes, statelist_t *p,
                                         uint32_t *keys_found, uint64_t *num_keys_tested,
                                         uint32_t nonces_to_bruteforce, const uint8_t *bf_test_nonce_2nd_byte,
                                         noncelist_t *nonces)
{
    hn_select_variants();
    return (*crack_states_bitsliced_function_p)(cuid, best_first_bytes, p, keys_found, num_keys_tested, nonces_to_bruteforce, bf_test_nonce_2nd_byte, nonces);
}

void bitslice_test_nonces_dispatch(uint32_t nonces_to_bruteforce, const uint32_t *bf_test_nonce, const uint8_t *bf_test_nonce_par)
{
    hn_select_variants();
    (*bitslice_test_nonces_function_p)(nonces_to_bruteforce, bf_test_nonce, bf_test_nonce_par);
}

// Entries to dispatched function calls
uint64_t crack_states_bitsliced(uint32_t cuid, uint8_t *best_first_bytes, statelist_t *p, uint32_t *keys_found, uint64_t *num_keys_tested, uint32_t nonces_to_bruteforce, uint8_t *bf_test_nonce_2nd_byte, noncelist_t *nonces)
{
    return (*crack_states_bitsliced_function_p)(cuid, best_first_bytes, p, keys_found, num_keys_tested, nonces_to_bruteforce, bf_test_nonce_2nd_byte, nonces);
}

void bitslice_test_nonces(uint32_t nonces_to_bruteforce, uint32_t *bf_test_nonce, uint8_t *bf_test_nonce_par)
{
    (*bitslice_test_nonces_function_p)(nonces_to_bruteforce, bf_test_nonce, bf_test_nonce_par);
}
