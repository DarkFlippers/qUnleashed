// Seed recovery for FAAC SLH, Genius, BFT and Erreka rolling codes: the ABI
// between the obfuscated search engine and everything that calls it.
//
// Three parties have to agree on this file: the engine (`faaccrack.c`, which is
// generated - see BUILD_NOTES.md), the dispatcher that picks an instruction set
// (`faaccrack_dispatch.c`), and the bridge the app calls
// (`faaccrack_bridge.c`).
//
// Only the engine is obfuscated. The other two are written by hand and stay
// readable.
//
// No Flipper or Dart type, header or assumption appears below - the same header
// serves the engine's command-line build. `.sub` is named in comments only to
// say what a field is for; nothing here writes one.
#ifndef QUNLEASHED_FAACCRACK_H
#define QUNLEASHED_FAACCRACK_H

#include <stddef.h>
#include <stdint.h>

// ---- the job ---------------------------------------------------------------

// Which remote is being attacked. The numbering reaches the engine's CLI as
// argv[1], so it is ABI rather than an internal detail.
//
// These four numbers are hard-coded inside the generated engine and are not
// derived from here; BUILD_NOTES.md says what that costs and what guards it.
#define FAACCRACK_MODE_FAAC_SLH 1
#define FAACCRACK_MODE_BFT      2
#define FAACCRACK_MODE_GENIUS   3
#define FAACCRACK_MODE_ERREKA   4

// The range the engine validates against, from the names above so that adding a
// mode does not mean editing two numbers that have to stay in step. Unlike the
// four, the engine does read these.
#define FAACCRACK_MODE_MIN FAACCRACK_MODE_FAAC_SLH
#define FAACCRACK_MODE_MAX FAACCRACK_MODE_ERREKA

// Hops the engine accepts in one job.
//
// Two is the floor because the acceptance test compares each decrypted counter
// with the one before it, so a single hop has nothing to be checked against -
// and one hop fits far too many seeds to be an answer at all.
#define FAACCRACK_MIN_HOPS 2
#define FAACCRACK_MAX_HOPS 16

// The largest counter step between two supplied hops that still verifies.
//
// The acceptance test needs the decrypted counters to march in one direction,
// but not to be adjacent: a capture that missed a few presses still solves
// entire, so long as no single step between the hops it did keep exceeds this.
// A step of zero is not a step - the same frame supplied twice is refused like
// any other break in the march.
//
// A macro so that this file, the engine and the caller spell the figure once.
// No caller branches on it: the app's window ladder offers the same windows
// whatever this says. What it buys is that the figure the documentation and the
// user-facing wording are written against is pinned to the one the engine
// enforces - `test/faaccrack_engine_abi_test.dart` fails when they part - so a
// drop from MMX that moves it cannot leave the comments written against it, or
// the figures derived from it below, describing a limit that is no longer in
// force. The user-facing wording deliberately names no number, so it needs no
// tripwire.
//
// **What it cost.** Per pair of hops the old test accepted two counter steps
// (plus or minus one); this one accepts sixteen magnitudes with the direction
// fixed once for the whole capture. Accepted counter sequences therefore go
// from 2^(n-1) to 2*16^(n-1) - a factor of 2*8^(n-1), so sixteen times more at
// two hops and a hundred and twenty-eight times more at three. The two rules
// are *not* nested: the single direction rejects the counter that walks back
// and forth, which the old per-pair test took, while the wide step takes gaps
// the old test refused. The direction clause is real tightening and does not
// pay for the step.
#define FAACCRACK_MAX_COUNTER_GAP 16

// Hops below which an answer should be shown as unconfirmed rather than offered
// for transmission: with two, a false positive over the whole 2^32 space is
// conceivable.
//
// Three used to put it near 1e-7, under the adjacency rule. With
// FAACCRACK_MAX_COUNTER_GAP in force read it as order 1e-5 - that macro carries
// the arithmetic.
//
// The line stays at three anyway, deliberately. One in roughly a hundred
// thousand recoveries handing back a remote that does not open the gate is a
// cost a user can see and retry; requiring four hops would refuse to write a
// file for the three-hop captures that are the common case, which is a cost
// every user pays.
//
// Whose call that is: this repository's, not MMX's. No translation unit of the
// engine reads this macro - it is not in `keep.txt` and the generated source
// does not spell it - so it is policy living in a hand-written header, and its
// only consumer is `SeedController.canSave` through `seedHopsConfident`. Moving
// it is one edit here and one there, with no engine drop involved.
#define FAACCRACK_HOPS_CONFIDENT 3

// Workers the engine will start. More is accepted and silently clamped, which
// matters to a caller building an estimate - see `threads_started`.
#define FAACCRACK_MAX_THREADS 256

// ---- status ----------------------------------------------------------------

// Why a search ended. Zero is success; every negative is a different answer to
// "why not", and each one leads somewhere different in a UI.
//
// An enum so the names are one declared set and the C side gets `-Wswitch`.
// That is as far as C can take it: the return type stays `int`, and a Dart
// `switch` over an FFI `int` is never exhaustive. The bridge has to map these to
// a Dart enum and switch on that, with a test pinning the mapping - the shape
// `hardnestedResultFor` already uses. Nothing derives that mapping from here;
// this project has no code generation.
//
// Retryability, because the UI has to choose a button:
//   STOPPED, BUSY                      - retry as-is
//   NOT_FOUND, UNVERIFIED              - retry only with a different capture
//   BAD_ARGS, SELFTEST_*               - do not retry; this build or this app
//                                        is wrong, and SELFTEST_* should
//                                        disable the feature rather than offer
//                                        a retry
//
// The numbers for the five conditions hardnested also has are deliberately the
// same as `qunleashed_hardnested_bridge.c` uses, so the two Dart mappings cannot
// disagree about what -3 or -4 mean. -1 is that bridge's out-of-memory and does
// not occur here: this engine performs no heap allocation on any path.
enum faaccrack_status {
    // A seed came back, every hop checked out, and the rebuilt frame reproduced
    // the captured hop. The only status under which a `.sub` may be written.
    FAACCRACK_OK = 0,

    // The caller passed something impossible: a mode outside
    // FAACCRACK_MODE_MIN..MAX, a null `hops` or `result`, `threads` below 1, or
    // `nhop` outside FAACCRACK_MIN_HOPS..FAACCRACK_MAX_HOPS.
    //
    // Two of those are the user's situation rather than a bug - a capture with
    // one press, or one left collecting through more than FAACCRACK_MAX_HOPS -
    // so a bridge must check both in Dart and say so in words the user can act
    // on. What reaches here should only ever be this app passing garbage.
    FAACCRACK_BAD_ARGS = -2,

    // The caller set `abort`, either before the call or during the sweep.
    FAACCRACK_STOPPED = -3,

    // A search is already running. Sequential searches are fine; the
    // dispatcher releases its gate when each one returns.
    //
    // The engine has a gate of its own, but it is a static in a translation
    // unit the build compiles once per instruction set, so there is one per
    // variant and none for the library. The dispatcher is the only translation
    // unit compiled once, which is why it owns the real one.
    FAACCRACK_BUSY = -4,

    // A seed decrypted every hop to ordered counters, but re-encrypting the
    // rebuilt frame did not reproduce the last captured hop.
    //
    // Its own status rather than a flag, because the thing a caller must not do
    // is write a key file, and a status is what every caller already switches
    // on. `result` is filled in - `frame_plain` beside `last_plain` is the
    // diagnosis - and the seed is worth showing. The file is not.
    FAACCRACK_UNVERIFIED = -5,

    // The whole space was swept and nothing matched.
    //
    // **Not a verdict on the remote.** For one of the four supported
    // manufacturers, with hops from one remote and no gap in them wider than
    // FAACCRACK_MAX_COUNTER_GAP, a seed exists and an exhaustive sweep finds it.
    // So this always means one of: the remote is a brand this engine has no key
    // for, the wrong mode was passed, the hops came from two different remotes,
    // enough presses were missed in one place to exceed that gap, or the capture
    // was mis-parsed. The engine cannot tell those apart, so a caller must not
    // render it as "unrecoverable".
    //
    // The useful move is still to retry over contiguous subsets of the capture,
    // which is what drops a gap too wide to tolerate instead of letting it
    // poison every hop; `hops_used` says how many backed the answer that came
    // out.
    FAACCRACK_NOT_FOUND = -10,

    // One of the engine's three startup checks failed, and which one is the
    // status: the engine's own `stderr` line reaches nobody, since Android
    // sends it to /dev/null, iOS to a log no in-app reader sees, and a Windows
    // release build has no console.
    //
    // All three mean a build-integration fault rather than anything about the
    // user's remote - a bad regeneration, a wrong -DVBITS, or a miscompiled
    // per-ISA object. They run per search, so a build that fails them fails
    // every search forever.
    FAACCRACK_SELFTEST_NLF = -20,      // the bitwise NLF network != the table
    FAACCRACK_SELFTEST_KEELOQ = -21,   // the published KeeLoq vector
    FAACCRACK_SELFTEST_SHUFFLE = -22,  // the Erreka seed shuffle
};

// The self-test codes as a range, so a bridge has one place to collapse them.
// A fourth check added to the engine would otherwise land in a caller's
// catch-all and be reported as a generic fault, losing the one thing these
// codes exist to carry.
#define FAACCRACK_SELFTEST_FIRST FAACCRACK_SELFTEST_SHUFFLE
#define FAACCRACK_SELFTEST_LAST  FAACCRACK_SELFTEST_NLF

// ---- the progress channel --------------------------------------------------

// A window into a running search, and the only way to stop one.
//
// `qunleashed_hn_progress.h` in the hardnested lib is the canonical account of
// why this is polled shared memory rather than an FFI callback, and why the
// fields are `volatile` rather than `_Atomic`. Three of the four fields are the
// same words, and the app reads both channels through one hand-written mirror:
// `NativeProgress` in lib/services/native.dart declares all four, so under
// hardnested the last one is slack it never touches.
//
// The two C structs stay separate even so; the reasoning and the alternatives
// are in `docs/adr/0015-hand-written-ffi-bindings.md`. What the shared mirror
// does couple is the order: this struct has to stay equal to it and
// hardnested's a prefix of it, so a field added *there* would land on
// `threads_started` and be read as it. `test/native_struct_mirror_test.dart`
// refuses both halves of that.
//
// What differs between the two channels, and is therefore documented here:
//
//  * `threads_started`, which that channel has no equivalent of.
//  * `abort` is read once per claimed chunk, where that engine reads its own at
//    a bucket boundary.
//  * `started` is set before the workers launch and latches; hardnested's is
//    set when a percentage is first published. Do not carry semantics across.
//  * There is no detach: this channel is passed per call, not installed.
//
// The `volatile` matters more here than there, because the engine is a single
// translation unit - the `abort` test and the loop it guards are always visible
// to the optimiser together. Never observed: a probe with the qualifier
// stripped, built at -O3 with the clang current in late 2026, still stopped
// about 20 ms after the flag was set. It stays for the five instruction sets,
// the other compilers, and the Apple unity build this will need.
//
// **Who clears what.** The caller owns this memory and must zero it before each
// search. The engine sets `permille`, `started` and `threads_started` once the
// arguments validate, and never clears `abort` - so a channel reused after a
// Stop returns FAACCRACK_STOPPED without starting anything. On BAD_ARGS and
// BUSY the engine does not write here at all. A caller that allocates one of
// these per search avoids all of it.
struct faaccrack_progress {
    // Engine -> caller. Thousandths of the seed space handed out, 0..1000. Not
    // quite the same as tested: chunks are claimed in batches and the threads
    // in flight finish at different times. Over thousands of chunks the
    // difference does not show.
    volatile uint32_t permille;

    // Caller -> engine. Set non-zero to stop; the engine never clears it. Read
    // once per claimed chunk, so a stop costs at most one chunk rather than the
    // rest of the sweep.
    volatile uint32_t abort;

    // Engine -> caller. Set when validation and the self-tests have passed and
    // the sweep is about to begin - deliberately not "the workers are running",
    // which this cannot claim. It latches, so it is not a liveness signal. It
    // exists so a caller can tell "nothing has begun" from "zero percent of
    // something that has".
    volatile uint32_t started;

    // Engine -> caller. Workers that actually started, set alongside `started`,
    // and published before the sweep is waited on rather than after.
    //
    // May be fewer than the `threads` asked for, or 1 if none could be created
    // and the calling thread swept alone. A thread that will not start is
    // survivable - chunks are claimed from a shared counter rather than split
    // up front - but it is not invisible, and this is what makes it so: the
    // caller supplied `threads` in order to show an estimate, and without this
    // the search could run on a third of them with nothing saying so.
    volatile uint32_t threads_started;
};

// ---- the result ------------------------------------------------------------

// What a search found.
//
// Meaningful only on FAACCRACK_OK and FAACCRACK_UNVERIFIED. The engine zeroes
// `*result` on entry - before taking the busy gate, so a caller never reads a
// previous search's seed out of it - and zero is a legal value for every field,
// so the status is the only thing that says this struct means anything.
//
// Everything a Flipper `.sub` needs is here, because the engine does no file
// I/O: the caller writes the file.
struct faaccrack_result {
    // The 64-bit key the seed derives, which is what actually decrypts the hops.
    // Diagnostic, and the right thing for a known-answer test to assert on: it
    // is key-derived and therefore mode-specific, so it fails if the mode
    // numbering ever drifts. Two seeds differing only in bits the derivation
    // discards share one of these.
    //
    // Unsigned here and signed in Dart, which has no unsigned 64-bit integer:
    // a key with the top bit set arrives negative there, so anything formatting
    // it has to say so rather than printing a minus sign.
    //
    // First because it is the only 64-bit member, which leaves the eight 32-bit
    // ones packed behind it with no padding.
    uint64_t lrkey;

    // The recovered seed. For Erreka this is the unshuffled form with bits 25
    // and 26 set: the derivation masks them off, so any value there yields the
    // same `lrkey` and the seed is only recoverable to 2^30. It still decodes
    // and transmits, which is what matters.
    uint32_t seed;

    // The last hop decrypted under `lrkey`, and the counter inside it. The
    // counter is 20 bits for Faac and Genius, 16 for BFT and Erreka - a width
    // that depends on the mode, which is not in this struct.
    uint32_t last_plain;
    uint32_t counter;

    // The plaintext the frame was rebuilt from, and the rolling half that came
    // out of encrypting it under `lrkey` - not the captured hop copied back. A
    // `.sub` carrying `frame_hop` is transmittable rather than a replay.
    //
    // `frame_plain` is not `last_plain`: what goes into the plaintext differs
    // per protocol and only partly comes from the decrypt. It is here because a
    // mismatch is the one failure worth being able to read, and the two numbers
    // side by side are what identify it.
    uint32_t frame_plain;
    uint32_t frame_hop;

    // Whether `frame_hop` came back equal to the last captured hop. The rebuild
    // is independent of the capture, so this is the check that the plaintext
    // layout was right for this protocol.
    //
    // A diagnostic. The gate on writing a file is FAACCRACK_OK, so a caller
    // cannot get this wrong by forgetting to read a field.
    uint32_t round_trip_ok;

    // How many hops the acceptance test ran over - an echo of the `nhop` passed
    // in, not a second measurement. Here for a caller that retries over subsets
    // of a capture; compare against FAACCRACK_HOPS_CONFIDENT.
    uint32_t hops_used;

    // Candidate seeds the engine advances per pass of the cipher: the `VBITS`
    // it was compiled with, 512 unless the build overrode it. A build constant
    // rather than a property of this search, and the only runtime evidence that
    // a `-DVBITS` was not silently dropped (BUILD_NOTES.md).
    //
    // Not the instruction set: the same 512-lane source compiles for SSE2 or
    // AVX-512 and the lane count does not change, only what a pass costs.
    uint32_t lanes;
};

// The layout, pinned where every variant, the dispatcher and the bridge all
// compile it for free.
//
// This is the one hole the build cannot cover. A name missing from `keep.txt`
// fails the C compile or the link (BUILD_NOTES.md), but nothing protects the
// Dart mirror: add a field and Dart reads wrong offsets with no compile error,
// no link error, and a plausible-looking seed. These make the C side's half
// loud, and the bridge exports the size so the Dart side can assert against it.
#define FAACCRACK_LAYOUT_CHANGED "faaccrack layout changed - update the Dart mirror"
_Static_assert(sizeof(struct faaccrack_progress) == 16, FAACCRACK_LAYOUT_CHANGED);
_Static_assert(offsetof(struct faaccrack_progress, permille) == 0, FAACCRACK_LAYOUT_CHANGED);
_Static_assert(offsetof(struct faaccrack_progress, abort) == 4, FAACCRACK_LAYOUT_CHANGED);
_Static_assert(offsetof(struct faaccrack_progress, started) == 8, FAACCRACK_LAYOUT_CHANGED);
_Static_assert(offsetof(struct faaccrack_progress, threads_started) == 12,
               FAACCRACK_LAYOUT_CHANGED);

// Every field, not only the size and a couple of offsets. Six 32-bit fields of
// one struct could otherwise permute among themselves with every assertion here
// and every size check on the Dart side still passing - and swapping `seed`
// with `last_plain`, which the comments above invite by documenting them
// together, hands a caller a wrong seed under a successful status.
_Static_assert(sizeof(struct faaccrack_result) == 40, FAACCRACK_LAYOUT_CHANGED);
_Static_assert(offsetof(struct faaccrack_result, lrkey) == 0, FAACCRACK_LAYOUT_CHANGED);
_Static_assert(offsetof(struct faaccrack_result, seed) == 8, FAACCRACK_LAYOUT_CHANGED);
_Static_assert(offsetof(struct faaccrack_result, last_plain) == 12, FAACCRACK_LAYOUT_CHANGED);
_Static_assert(offsetof(struct faaccrack_result, counter) == 16, FAACCRACK_LAYOUT_CHANGED);
_Static_assert(offsetof(struct faaccrack_result, frame_plain) == 20, FAACCRACK_LAYOUT_CHANGED);
_Static_assert(offsetof(struct faaccrack_result, frame_hop) == 24, FAACCRACK_LAYOUT_CHANGED);
_Static_assert(offsetof(struct faaccrack_result, round_trip_ok) == 28,
               FAACCRACK_LAYOUT_CHANGED);
_Static_assert(offsetof(struct faaccrack_result, hops_used) == 32, FAACCRACK_LAYOUT_CHANGED);
_Static_assert(offsetof(struct faaccrack_result, lanes) == 36, FAACCRACK_LAYOUT_CHANGED);

// ---- the entry point -------------------------------------------------------

// The signature every variant has, written once so the dispatcher's table and
// the engine's definition cannot drift apart.
typedef int faaccrack_search_fn(uint32_t mode, uint32_t fix, const uint32_t *hops,
                                uint32_t nhop, int threads,
                                struct faaccrack_progress *progress,
                                struct faaccrack_result *result);

// Every instruction set the engine is compiled for, in the order a dispatcher
// should prefer them.
//
// A list rather than hand-written `extern` declarations, so the cascade below
// and this set can be held to each other by a test. The CMake and the
// dispatcher still name the variants themselves, so adding one is three edits -
// the list does not change that, it just makes a mismatch loud.
//
// No AVX-512, and the reason is measured rather than theoretical: client Intel
// parts downclock under 512-bit integer work, so a dispatcher preferring it
// unconditionally can be slower than AVX2 on the machines most likely to run
// this. The hardnested lib shipped it, took it back out, and wrote that down;
// this engine's inner loop is pure 512-bit bitwise work, so it is if anything
// more exposed. AVX2 is the width the engine's author measured.
#define FAACCRACK_VARIANTS(X) X(AVX2) X(AVX) X(NEON) X(SSE2)

#define FAACCRACK_DECLARE_VARIANT_(v) faaccrack_search_fn faaccrack_search_##v;
FAACCRACK_VARIANTS(FAACCRACK_DECLARE_VARIANT_)
#undef FAACCRACK_DECLARE_VARIANT_

// Which variant the including translation unit is being compiled as, from the
// compiler's own capability macros.
//
// `__arm64__` as well as `__aarch64__`, because Apple defines only the first.
// The sibling lib centralises the same tests into `COMPILER_HAS_SIMD_*`
// (hardnested/hardnested_bf_core.h) and carries two quirks this cascade does
// not - an Apple-clang version guard and a workaround for clang reporting
// `__GNUC__` 4 - so the two should become one shared capability header; see
// BUILD_NOTES.md for why that hoist is not in this commit.
//
// A target with AVX-512 and not AVX2 does not exist, so the absence of an
// AVX-512 branch costs nothing: -mavx512f implies -mavx2, and such a build
// names itself AVX2 and runs the AVX2 object.
//
// No fallback: the engine is built on vector extensions, so there is nothing to
// degrade to, and an unsupported target must fail here rather than compile. A
// `vector_size` type scalarises for any target, so without this `#error` a
// fall-through platform would build a library exporting a variant name no
// dispatcher has an entry for, and ship with no reachable engine.
// `FAACCRACK_VARIANT_NAME` is the same choice as a string, for a build that
// compiled only one object - the Apple pod - where the dispatcher cannot name
// the others without referencing symbols that do not exist.
#if defined(__AVX2__)
#define FAACCRACK_SEARCH faaccrack_search_AVX2
#define FAACCRACK_VARIANT_NAME "AVX2"
#elif defined(__AVX__)
#define FAACCRACK_SEARCH faaccrack_search_AVX
#define FAACCRACK_VARIANT_NAME "AVX"
#elif defined(__aarch64__) || defined(__arm64__) || defined(__ARM_NEON) || \
    defined(_M_ARM64)
#define FAACCRACK_SEARCH faaccrack_search_NEON
#define FAACCRACK_VARIANT_NAME "NEON"
// `_M_X64` and `_M_IX86_FP` as well as `__SSE2__`, because MSVC compiles the
// dispatcher and the bridge even where clang-cl compiles the engine, and MSVC
// does not define the GCC/Clang spelling. SSE2 is unconditional on x86-64.
#elif defined(__SSE2__) || defined(_M_X64) || (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
#define FAACCRACK_SEARCH faaccrack_search_SSE2
#define FAACCRACK_VARIANT_NAME "SSE2"
#else
#error "faaccrack: no SIMD variant for this target - the engine needs SSE2, AVX, AVX2, AVX-512 or NEON"
#endif

// Searches the whole seed space for a seed that decrypts every hop to counters
// running in one direction, no two of them further apart than
// FAACCRACK_MAX_COUNTER_GAP, under the manufacture key `mode` selects. Returns
// a `faaccrack_status`.
//
// `fix` is the remote's fixed code exactly as captured: the top 32 bits of the
// 64-bit frame, not part of the search space. Its layout differs by protocol -
// for Faac and Genius the serial is the top 28 bits and the button the low
// nibble, for BFT and Erreka the other way round - and the engine masks it
// accordingly, so it wants the whole word as captured rather than either half.
// For KeeLoq protocols the frame goes out LSB first and has to be reversed
// before `fix` and `hops` line up with the halves quoted here; the Flipper-side
// capture app does that already.
//
// `hops` must be *presses of one remote in the order they were sent*, and
// `nhop` in FAACCRACK_MIN_HOPS..FAACCRACK_MAX_HOPS. The acceptance test requires
// the decrypted counters to run in one direction with no step wider than
// FAACCRACK_MAX_COUNTER_GAP, so a capture that missed a few presses still solves
// as a whole. A caller holding more hops than the maximum, or a capture with a
// wider gap than that in it, should try contiguous subsets.
//
// That test is what keeps a false positive unlikely rather than impossible, and
// the tolerance did weaken it - by the factor under FAACCRACK_MAX_COUNTER_GAP,
// which is also why the confidence threshold's estimate moved.
//
// Order still matters even though both directions verify. Every *per-hop* field
// of `result` - `last_plain`, `counter`, `frame_plain`, `frame_hop` and the
// round trip - is taken from the last hop supplied, so a capture handed over
// oldest-last solves and then describes a remote several presses behind the
// counter the receiver has already seen: a file the firmware accepts and the
// gate ignores. `seed` and `lrkey` do not depend on the order.
//
// `threads` must be at least 1 and is clamped to FAACCRACK_MAX_THREADS. The
// engine never asks the OS how many CPUs there are: that is a different call on
// every platform, and the caller already needs the figure to estimate the wait.
// Read `threads_started` for how many it got.
//
// `progress` may be null, in which case the search cannot be stopped at all.
// `result` may not be null. Both are the caller's to allocate, zero and outlive
// the call. One search at a time - see FAACCRACK_BUSY, which is per variant.
//
// An outside caller wants the bridge's entry point, not this one.
faaccrack_search_fn FAACCRACK_SEARCH;

// ---- the dispatcher --------------------------------------------------------

// The same search, on whichever variant this CPU can run, with one busy gate
// for the whole library rather than one per compiled variant.
//
// `faaccrack_dispatch.c` is the only translation unit the build compiles once,
// which is why the gate lives there. Everything inside the library calls this
// rather than FAACCRACK_SEARCH.
faaccrack_search_fn faaccrack_search;

// Which variant was selected - "AVX2", "NEON" and so on, or "unknown".
//
// Worth having because the difference between the fastest and slowest variant
// is several-fold, so a machine that is unexpectedly slow is answered by this
// one string. It is not derivable from the result: `lanes` is the lane count
// the source was compiled with, which is the same for every variant.
const char *faaccrack_variant_name(void);

#endif  // QUNLEASHED_FAACCRACK_H
