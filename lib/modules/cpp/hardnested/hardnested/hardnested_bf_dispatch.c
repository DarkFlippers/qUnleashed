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

#if defined(QUNLEASHED_HN_SIMD_VARIANTS)
crack_states_bitsliced_t crack_states_bitsliced_AVX512;
crack_states_bitsliced_t crack_states_bitsliced_AVX2;
crack_states_bitsliced_t crack_states_bitsliced_AVX;
crack_states_bitsliced_t crack_states_bitsliced_SSE2;
bitslice_test_nonces_t bitslice_test_nonces_AVX512;
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

// Whether the OS has agreed to preserve the wide registers across a context
// switch. Asking the CPU alone is not enough: a CPU that implements AVX on an
// OS that does not save YMM would fault on the first instruction, which is
// exactly the crash that makes people distrust runtime dispatch.
static bool os_saves_wide_registers(bool need_zmm)
{
#if defined(_MSC_VER)
    int regs[4];
    __cpuid(regs, 1);
    const bool has_xsave = (regs[2] & (1 << 27)) != 0; // OSXSAVE
    if (!has_xsave)
    {
        return false;
    }
    const uint64_t xcr0 = (uint64_t)_xgetbv(0);
#else
    uint32_t eax, ebx, ecx, edx;
    __asm__ volatile("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(1), "c"(0));
    if ((ecx & (1u << 27)) == 0)
    {
        return false;
    }
    uint32_t xcr0_lo, xcr0_hi;
    __asm__ volatile(".byte 0x0f, 0x01, 0xd0" : "=a"(xcr0_lo), "=d"(xcr0_hi) : "c"(0));
    const uint64_t xcr0 = ((uint64_t)xcr0_hi << 32) | xcr0_lo;
#endif
    // XMM (bit 1) and YMM (bit 2) for AVX; the three opmask/ZMM bits on top of
    // those for AVX-512.
    const uint64_t ymm = 0x6;
    const uint64_t zmm = 0xe6;
    return (xcr0 & (need_zmm ? zmm : ymm)) == (need_zmm ? zmm : ymm);
}

static bool cpu_has(int leaf, int sub_leaf, int reg_index, int bit)
{
#if defined(_MSC_VER)
    int regs[4];
    __cpuidex(regs, leaf, sub_leaf);
    return (regs[reg_index] & (1 << bit)) != 0;
#else
    uint32_t regs[4];
    __asm__ volatile("cpuid"
                     : "=a"(regs[0]), "=b"(regs[1]), "=c"(regs[2]), "=d"(regs[3])
                     : "a"(leaf), "c"(sub_leaf));
    return (regs[reg_index] & (1u << bit)) != 0;
#endif
}

static SIMDExecInstr GetSIMDInstr(void)
{
    // Highest first, and each one only after the OS check it needs. SSE2 is
    // baseline on x86-64, so the scalar variant is never reached on a desktop -
    // it stays in the library for anything that is neither x86-64 nor NEON.
    if (cpu_has(7, 0, 1, 16) && os_saves_wide_registers(true)) // EBX bit 16: AVX512F
    {
        return SIMD_AVX512;
    }
    if (cpu_has(7, 0, 1, 5) && os_saves_wide_registers(false)) // EBX bit 5: AVX2
    {
        return SIMD_AVX2;
    }
    if (cpu_has(1, 0, 2, 28) && os_saves_wide_registers(false)) // ECX bit 28: AVX
    {
        return SIMD_AVX;
    }
    if (cpu_has(1, 0, 3, 26)) // EDX bit 26: SSE2
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
#if defined(__AVX512F__)
    return SIMD_AVX512;
#elif defined(__AVX2__)
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

// determine the available instruction set at runtime and call the correct function
uint64_t crack_states_bitsliced_dispatch(uint32_t cuid, uint8_t *best_first_bytes, statelist_t *p,
                                         uint32_t *keys_found, uint64_t *num_keys_tested,
                                         uint32_t nonces_to_bruteforce, const uint8_t *bf_test_nonce_2nd_byte,
                                         noncelist_t *nonces)
{
#if defined(QUNLEASHED_HN_SIMD_VARIANTS)
    switch (GetSIMDInstrAuto())
    {
    case SIMD_AVX512:
        crack_states_bitsliced_function_p = &crack_states_bitsliced_AVX512;
        break;
    case SIMD_AVX2:
        crack_states_bitsliced_function_p = &crack_states_bitsliced_AVX2;
        break;
    case SIMD_AVX:
        crack_states_bitsliced_function_p = &crack_states_bitsliced_AVX;
        break;
    case SIMD_SSE2:
        crack_states_bitsliced_function_p = &crack_states_bitsliced_SSE2;
        break;
    default:
        crack_states_bitsliced_function_p = &HN_CRACK_VARIANT;
        break;
    }
#else
    crack_states_bitsliced_function_p = &HN_CRACK_VARIANT;
#endif

    // call the most optimized function for this CPU
    return (*crack_states_bitsliced_function_p)(cuid, best_first_bytes, p, keys_found, num_keys_tested, nonces_to_bruteforce, bf_test_nonce_2nd_byte, nonces);
}

void bitslice_test_nonces_dispatch(uint32_t nonces_to_bruteforce, const uint32_t *bf_test_nonce, const uint8_t *bf_test_nonce_par)
{
#if defined(QUNLEASHED_HN_SIMD_VARIANTS)
    switch (GetSIMDInstrAuto())
    {
    case SIMD_AVX512:
        bitslice_test_nonces_function_p = &bitslice_test_nonces_AVX512;
        break;
    case SIMD_AVX2:
        bitslice_test_nonces_function_p = &bitslice_test_nonces_AVX2;
        break;
    case SIMD_AVX:
        bitslice_test_nonces_function_p = &bitslice_test_nonces_AVX;
        break;
    case SIMD_SSE2:
        bitslice_test_nonces_function_p = &bitslice_test_nonces_SSE2;
        break;
    default:
        bitslice_test_nonces_function_p = &HN_TEST_VARIANT;
        break;
    }
#else
    bitslice_test_nonces_function_p = &HN_TEST_VARIANT;
#endif

    // call the most optimized function for this CPU
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
