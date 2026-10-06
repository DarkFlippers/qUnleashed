// Picking the seed-search implementation for the CPU this is running on, and
// holding the one gate that makes "one search at a time" true.
//
// Its own translation unit because the engine is compiled several times - once
// per instruction set - and exactly one copy of the selection and the gate may
// exist. The engine's own busy flag is a static inside its translation unit, so
// there is one per compiled variant; that is enough to stop a second call into
// the *same* variant, and nothing at all once a build carries five. This file
// is the only place in the library that is compiled once, which is why the gate
// belongs here.
//
// Modelled on hardnested/hardnested_bf_dispatch.c, which does the same job for
// the MIFARE brute force. The probe for AVX support is the same shape and for
// the same reason: a CPU that implements AVX on an OS that does not preserve
// the wide registers faults on the first instruction, so `cpuid` alone is not
// enough and `xgetbv` has to agree.
#include "faaccrack.h"

#include <stdint.h>

#if defined(_MSC_VER)
#include <intrin.h>
#endif

// A runtime choice is only possible where the build actually compiled more than
// one engine object, which the CMake says with FAACCRACK_MULTI_VARIANT. The
// Apple pod does not: CocoaPods compiles one unity translation unit per
// architecture, so an Intel Mac has the baseline object and nothing else - and
// a dispatcher that referenced the other four would not link.
//
// On arm64 there is nothing to choose between either way: NEON is part of the
// baseline, so the single object is already the right one.
#if defined(FAACCRACK_MULTI_VARIANT) &&                                         \
    (defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86))
#define FAACCRACK_DISPATCH_X86 1
#endif

#if defined(FAACCRACK_DISPATCH_X86)

static int cpu_has(int leaf, int sub_leaf, int reg_index, int bit) {
    // CPUID with EAX above the highest supported leaf returns that leaf's data
    // rather than zeros, so an unguarded leaf-7 read on an older part answers a
    // different question. The sibling dispatcher carries the same guard for the
    // same reason; every CPU that could pass the AVX gates also has leaf 7, so
    // this is belt and braces rather than a case anyone has hit.
#if defined(_MSC_VER)
    int regs[4];
    __cpuid(regs, 0);
    if (regs[0] < leaf) return 0;
    __cpuidex(regs, leaf, sub_leaf);
    // Unsigned, because bit 31 of a signed int is implementation-defined.
    return ((unsigned)regs[reg_index] & (1u << bit)) != 0;
#else
    uint32_t regs[4];
    __asm__ volatile("cpuid"
                     : "=a"(regs[0]), "=b"(regs[1]), "=c"(regs[2]), "=d"(regs[3])
                     : "a"(0), "c"(0));
    if (regs[0] < (uint32_t)leaf) return 0;
    __asm__ volatile("cpuid"
                     : "=a"(regs[0]), "=b"(regs[1]), "=c"(regs[2]), "=d"(regs[3])
                     : "a"(leaf), "c"(sub_leaf));
    return (regs[reg_index] & (1u << bit)) != 0;
#endif
}

// Whether the OS saves the registers a variant would use. Without this a CPU
// that reports AVX on a kernel that does not preserve YMM faults the first time
// the engine touches one.
static int os_saves_wide_registers(int need_zmm) {
#if defined(_MSC_VER)
    int regs[4];
    __cpuid(regs, 1);
    if ((regs[2] & (1 << 27)) == 0) return 0;  // OSXSAVE
    const uint64_t xcr0 = (uint64_t)_xgetbv(0);
#else
    uint32_t eax, ebx, ecx, edx;
    __asm__ volatile("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx)
                     : "a"(1), "c"(0));
    if ((ecx & (1u << 27)) == 0) return 0;
    uint32_t xcr0_lo, xcr0_hi;
    __asm__ volatile(".byte 0x0f, 0x01, 0xd0" : "=a"(xcr0_lo), "=d"(xcr0_hi) : "c"(0));
    const uint64_t xcr0 = ((uint64_t)xcr0_hi << 32) | xcr0_lo;
#endif
    // XMM (bit 1) and YMM (bit 2) for AVX; the opmask and ZMM bits on top for
    // AVX-512.
    const uint64_t want = need_zmm ? 0xe6u : 0x6u;
    return (xcr0 & want) == want;
}

#endif  // FAACCRACK_DISPATCH_X86

// Chosen once. The answer cannot change while the process runs, and a search
// that re-probed would pay for `cpuid` on a path that is otherwise one call.
//
// Two threads racing here compute the same pair, so the *values* are safe - but
// their publication is not automatically. `chosen` is what every reader tests
// for initialisation, so it is written last, after `chosen_name`: a reader that
// sees a non-null pointer has therefore also seen the name. Without that order
// a caller can skip initialisation and return a null name, which on the Dart
// side reaches `toDartString()` and scans from address zero - a segfault, not
// an exception. The two isolates that touch these are different threads.
static const char *chosen_name;
static faaccrack_search_fn *chosen;

// Picks the variant this CPU can run, highest first, and names it.
//
// The name is set here rather than worked out afterwards by comparing the
// pointer against every variant: that comparison would have to mention all five
// symbols, and a build only ever contains the subset its platform compiled - on
// x86 there is no NEON object to refer to.
static void select_variant(void) {
#if defined(FAACCRACK_DISPATCH_X86)
    if (cpu_has(7, 0, 1, 16) && os_saves_wide_registers(1)) {  // EBX bit 16: AVX512F
        chosen_name = "AVX512";
        chosen = faaccrack_search_AVX512;
    } else if (cpu_has(7, 0, 1, 5) && os_saves_wide_registers(0)) {  // EBX bit 5: AVX2
        chosen_name = "AVX2";
        chosen = faaccrack_search_AVX2;
    } else if (cpu_has(1, 0, 2, 28) && os_saves_wide_registers(0)) {  // ECX bit 28: AVX
        chosen_name = "AVX";
        chosen = faaccrack_search_AVX;
    } else {
        // SSE2 is part of the x86-64 baseline, so this is the floor rather than
        // a fallback - there is no scalar variant to degrade to.
        chosen_name = "SSE2";
        chosen = faaccrack_search_SSE2;
    }
#else
    // One object, and this translation unit was compiled with the same flags
    // that produced it, so the header's own cascade names it.
    chosen_name = FAACCRACK_VARIANT_NAME;
    chosen = FAACCRACK_SEARCH;
#endif
}

const char *faaccrack_variant_name(void) {
    if (!chosen) select_variant();
    // Never null, whatever happens above: this crosses to Dart, where a null
    // is scanned from address zero rather than reported.
    return chosen_name ? chosen_name : "unknown";
}

// One search at a time, for the whole library rather than per variant.
//
// A real test-and-set rather than a read followed by a write: two callers
// arriving together would otherwise both see it clear and both proceed, which
// is the exact case this gate exists for. The engine's own per-variant flag
// would still turn the second away *if* it landed on the same variant - and
// since the dispatcher selects once per process it normally would - but relying
// on that makes the guarantee depend on a coincidence.
//
// `long` and the compiler's own intrinsic rather than C11 atomics, because this
// file is compiled by whatever builds the library, MSVC included, where
// `_Atomic` is not dependable.
static volatile long busy;

static int take_gate(void) {
#if defined(_MSC_VER)
    return _InterlockedExchange(&busy, 1) != 0;
#else
    return __atomic_exchange_n(&busy, 1L, __ATOMIC_ACQ_REL) != 0;
#endif
}

static void release_gate(void) {
#if defined(_MSC_VER)
    _InterlockedExchange(&busy, 0);
#else
    __atomic_store_n(&busy, 0L, __ATOMIC_RELEASE);
#endif
}

int faaccrack_search(uint32_t mode, uint32_t fix, const uint32_t *hops, uint32_t nhop,
                     int threads, struct faaccrack_progress *progress,
                     struct faaccrack_result *result) {
    if (!chosen) select_variant();

    if (take_gate()) return FAACCRACK_BUSY;
    const int status = chosen(mode, fix, hops, nhop, threads, progress, result);
    release_gate();
    return status;
}
