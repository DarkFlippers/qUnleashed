// Drives the committed engine through its library entry point and checks the
// contract the header promises.
//
// Why this exists, and why it is cheap: the engine's own equivalence script
// (`verify_obf.sh`, see ../BUILD_NOTES.md) cannot live in this repository - it
// needs the readable source - and it drives the *command line* anyway, which is
// not the path the app uses. Everything below exercises `FAACCRACK_SEARCH`
// directly, and needs no CMake, no dispatcher, no Dart and no private source.
//
// Every assertion about a capture that *solves* costs milliseconds. A capture
// the engine must *refuse* has no cheap form - it sweeps the whole seed space -
// so the three refusals are stopped as soon as the engine's own progress counter
// proves they went past the seed in question. The whole file then runs in about
// 700 ms on a developer machine, bounded at five seconds per refusal against an
// engine that publishes no progress at all. The group that does it explains why
// that bound is the assertion rather than a timeout.
//
// The assertion that earns the file is the first one. A call with valid
// arguments and `abort` already set runs the engine's three internal
// known-answer checks - the NLF network against its table, the published KeeLoq
// vector, the Erreka shuffle - and then returns before sweeping anything. So a
// regeneration whose literal-splitting pass corrupted the NLF constant, the
// round count or a manufacture key fails here, in milliseconds, with no fixture
// and nothing secret in this file. Nothing else in the repository calls those
// checks.
//
// What it cannot see:
//
//  * Whether the mode numbers are *right*, only that they have not changed. The
//    known-answer vectors below were generated from this same engine, so they
//    pin drift rather than initial correctness. A vector captured from a real
//    Erreka remote would be stronger and remains the eventual goal.
//  * A valid call with `progress == NULL`. The header allows it, but without a
//    channel there is no way to stop a sweep, so exercising it would mean
//    waiting out the whole seed space. Only the refusal path is covered below.
//  * The per-instruction-set choice. This links one variant, whichever the
//    host's flags select, and calls it through the dispatcher - so the
//    dispatcher's gate is covered and its cpuid cascade is not.
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32) && !defined(__MINGW32__)
#include "pthread_shim.h"
#define PROBE_SLEEP_MS(ms) Sleep(ms)
#define PROBE_NOW_MS() ((uint64_t)GetTickCount64())
#else
#include <pthread.h>
#include <time.h>
#define PROBE_SLEEP_MS(ms)                                                  \
    do {                                                                    \
        struct timespec ts_ = {(ms) / 1000, ((long)(ms) % 1000) * 1000000L}; \
        nanosleep(&ts_, NULL);                                              \
    } while (0)
// Monotonic, not wall clock: the only thing timed here is how long a stop takes
// to land, and an NTP step during a CI run would otherwise fail that assertion
// for a reason that has nothing to do with the engine.
static uint64_t PROBE_NOW_MS(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
}
#endif

#include "faaccrack.h"

static int checks;
static int failures;

// Printed per group, so the script can hold each one to its own figure. A
// single floor over the total let the known-answer group - the only thing that
// pins the four mode numbers - be deleted while the count stayed comfortably
// above it.
static void group_done(const char *name, int before) {
    printf("PROBE GROUP %s %d\n", name, checks - before);
}

static void check(const char *what, int ok) {
    // Counted as well as reported, so the script can refuse a run that somehow
    // asserted nothing. A probe whose checks were all skipped would otherwise
    // exit 0 and leave CI green.
    checks++;
    printf("%-52s %s\n", what, ok ? "ok" : "FAILED");
    if (!ok) failures++;
}

static void check_eq(const char *what, int got, int want) {
    if (got != want) printf("  (got %d, wanted %d)\n", got, want);
    check(what, got == want);
}

// A fix with hops that no seed resolves to counters the acceptance test will
// take, so the sweep runs the whole space and can be interrupted rather than
// finishing first.
//
// What that takes is now a weaker statement than it was. These two hops used to
// have to miss a step of exactly plus or minus one; they now have to miss every
// step from 1 to FAACCRACK_MAX_COUNTER_GAP, in either direction - a target 16
// times wider per candidate seed, and at two hops there is no direction clause
// to help. It still holds, but the margin behind this fixture shrank when the
// tolerance landed. If a future widening breaks it, the symptom is the stop
// group going green for the wrong reason - a solved capture rather than an
// interrupted sweep - which `permille < 1000` catches.
#define UNSOLVABLE_FIX 0xA0DC9330u
static const uint32_t unsolvable[2] = {0x29389EF7u, 0x40101499u};

// ---- the self-tests, via the one path that runs them without sweeping -------

static void probe_selftests(void) {
    struct faaccrack_progress progress;
    struct faaccrack_result result;
    memset(&progress, 0, sizeof progress);
    // Pre-set: validation and the three known-answer checks run, then the
    // engine sees this and leaves before claiming a chunk.
    progress.abort = 1;

    const int status = faaccrack_search(FAACCRACK_MODE_FAAC_SLH, UNSOLVABLE_FIX,
                                        unsolvable, 2, 1, &progress, &result);

    // STOPPED and not SELFTEST_* is the whole assertion: the cipher, the NLF
    // table and the shuffle all still compute what they did when the engine was
    // ported.
    check_eq("the cipher self-tests pass (stopped, not selftest)", status,
             FAACCRACK_STOPPED);
    check("an abort set beforehand stops it starting", progress.started == 0);
    check("and publishes no progress", progress.permille == 0);
    check("and starts no workers", progress.threads_started == 0);
}

// ---- a real recovery, per mode ---------------------------------------------

// A capture each mode must still solve, with the answer it must give.
//
// Generated from this engine (the generator is scratch tooling that includes
// the readable source, so it is not in the repository; ../BUILD_NOTES.md says
// how). Nothing here is secret: a fix and three hops are ciphertext a receiver
// sees anyway, and `lrkey` is derived from the seed below it.
//
// The seeds are deliberately small. The sweep walks upward from zero, so each
// of these is found in the first block claimed - milliseconds, which is what
// lets a real recovery run on every pull request instead of in a nightly bench.
//
// What this pins that nothing else can: the four mode numbers. The engine
// compares its own obfuscated literals rather than the header's macros, so
// renumbering a mode leaves every other guard green while a user attacking
// Erreka gets BFT's key and is told no seed exists. `lrkey` is key-derived and
// therefore mode-specific, which is why it is asserted and not just the seed.
// It is also the only end-to-end check that a search finds a seed at all, and
// the only one of `round_trip_ok`.
struct known_answer {
    uint32_t mode;
    uint32_t fix;
    uint32_t hops[3];
    uint32_t seed;
    uint64_t lrkey;
    uint32_t counter;
    const char *name;
};

static const struct known_answer known_answers[] = {
    {1, 0x12345674u, {0xB3EF9ABBu, 0x3F5E4CF5u, 0x698DCAEEu}, 0x00000123u,
     0xE98257905E0F8621ull, 0x00113u, "FAAC_SLH"},
    {2, 0x200342E2u, {0x2F62BE4Bu, 0x1895D794u, 0x367AEB49u}, 0x00000456u,
     0x45963EF292AAA132ull, 0x1236u, "BFT"},
    {3, 0xA0DC9330u, {0x293AC619u, 0x1EECA414u, 0xCBCEFBA6u}, 0x00000789u,
     0x558E9CCBC5945217ull, 0x00224u, "Genius"},
    // Erreka searches a shuffled form of the seed and two of its bits never
    // reach the cipher, so this is the value the engine reports back.
    {4, 0x20345678u, {0x4AB86AACu, 0x04C40F30u, 0xA1988133u}, 0x0600A0BCu,
     0x96928E898CC2353Dull, 0x4323u, "Erreka"},
};

static void probe_known_answers(void) {
    for (size_t i = 0; i < sizeof known_answers / sizeof known_answers[0]; i++) {
        const struct known_answer *want = &known_answers[i];
        struct faaccrack_progress progress;
        struct faaccrack_result got;
        memset(&progress, 0, sizeof progress);

        const int status = faaccrack_search(want->mode, want->fix, want->hops, 3, 2,
                                            &progress, &got);

        char label[80];
        snprintf(label, sizeof label, "%s recovers its seed", want->name);
        check_eq(label, status, FAACCRACK_OK);
        if (status != FAACCRACK_OK) continue;

        snprintf(label, sizeof label, "%s seed is %08X", want->name, want->seed);
        check(label, got.seed == want->seed);
        snprintf(label, sizeof label, "%s derives the right key", want->name);
        check(label, got.lrkey == want->lrkey);
        snprintf(label, sizeof label, "%s rebuilds the captured frame", want->name);
        check(label, got.round_trip_ok == 1);
        snprintf(label, sizeof label, "%s reports its counter", want->name);
        check(label, got.counter == want->counter);
        // The rolling half that goes into the .sub. Nothing else asserts its
        // value, and it is the field a caller writes to the user's device.
        snprintf(label, sizeof label, "%s rebuilds the captured hop", want->name);
        check(label, got.frame_hop == want->hops[2]);
        // The documented evidence that a -DVBITS was not silently dropped by
        // the obfuscator - BUILD_NOTES calls this the only such evidence, and
        // until now nothing read it.
        snprintf(label, sizeof label, "%s reports the compiled lane count",
                 want->name);
        check(label, got.lanes == 512);
        snprintf(label, sizeof label, "%s says how many hops backed it", want->name);
        check(label, got.hops_used == 3);
    }
}

// ---- the gap tolerance -----------------------------------------------------

// Captures of one remote whose recovered counters are not adjacent -
// FAACCRACK_MAX_COUNTER_GAP is what lets these solve entire, rather than only
// over whichever window of the capture the caller guessed at.
//
// Same provenance as the table above and the same small seeds: generated from
// this engine, found in the first block the sweep claims, nothing secret. The
// counter asserted is the *last* hop's, which is the one a `.sub` is written
// from, so a tolerance that silently dropped a hop would show up here.
//
// Five rows, because the test has that many things to get wrong. Gaps inside
// the limit; a gap of exactly the limit, which pins the edge from below; a
// capture at FAACCRACK_MIN_HOPS, the last rung of the caller's window ladder
// and the only vector in this file that solves on two hops; one handed over in
// reverse, which pins the second of the two direction flags, since every other
// vector here runs upward and a regeneration that lost the reverse case would
// otherwise tell a user with a backwards capture that no seed exists - that row
// is also where the header's warning is checked, because it reports the counter
// of the *oldest* press; and a BFT capture, whose step is compared under a
// 16-bit CNT_MASK against 20 bits for Faac and Genius, which is a second path
// through the same test rather than a second manufacturer.
struct gapped_answer {
    uint32_t mode;
    uint32_t fix;
    uint32_t hops[3];
    uint32_t nhop;
    uint32_t seed;
    uint32_t counter;
    const char *name;
};

static const struct gapped_answer gapped_answers[] = {
    // Steps of nine then seven - eight presses missing, then six.
    {3, 0xA0DC9330u, {0x293AC619u, 0xC3174969u, 0x56687900u}, 3, 0x00000789u,
     0x00232u, "a gapped capture"},
    // Steps of exactly the limit, twice.
    {3, 0xA0DC9330u, {0x293AC619u, 0x56687900u, 0xBDC2C0C1u}, 3, 0x00000789u,
     0x00242u, "a gap of exactly the limit"},
    // The two ends of the row above. At two hops the direction half of the test
    // is vacuous - any pair runs one way - so this pins the step magnitude and
    // `hops_used`, not the direction.
    {3, 0xA0DC9330u, {0x293AC619u, 0x56687900u}, 2, 0x00000789u, 0x00232u,
     "a gapped two-hop capture"},
    // The Genius row of the known-answer table, backwards. Solves, and reports
    // 0x00222 where the forward order reports 0x00224: two presses behind the
    // counter the receiver has already seen.
    {3, 0xA0DC9330u, {0xCBCEFBA6u, 0x1EECA414u, 0x293AC619u}, 3, 0x00000789u,
     0x00222u, "a capture in reverse"},
    // Steps of nine then seven again, on the narrow counter.
    {2, 0x200342E2u, {0x2F62BE4Bu, 0xDEF96F59u, 0x34CD15E7u}, 3, 0x00000456u,
     0x1244u, "a gapped BFT capture"},
};

// Captures the test must *refuse*, one per clause of it. Hops only: the fix and
// the mode come from `gapped_answers[0]` at the call site, because what makes
// these cheap is that they are the same remote the rows above solve for - its
// seed is in the first block the sweep claims, so an engine that wrongly
// accepted would answer in milliseconds. Spelling the fix again here would let
// a regenerated table leave these three pointed at a remote nothing else uses,
// where all six checks would still pass.
//
//  * a step one press past the limit - the step-too-wide half of the test;
//  * counters that go up and then back down, every step adjacent. The one shape
//    the old pairwise test accepted and this one does not, so it is the only
//    check that the direction clause exists at all: every other refusal here is
//    rejected on width alone, and a regeneration that dropped the direction
//    half would otherwise pass this entire file;
//  * the same hop twice, so a step of zero - the other half, which is what a
//    capture app that wrote one press twice would produce.
struct refused_capture {
    uint32_t hops[3];
    const char *name;
};

static const struct refused_capture refused_captures[] = {
    {{0x293AC619u, 0xAAA0F389u, 0xB811F847u}, "a gap one press past the limit"},
    {{0x293AC619u, 0x1EECA414u, 0x293AC619u}, "counters that reverse"},
    {{0x293AC619u, 0x293AC619u, 0x1EECA414u}, "the same hop twice"},
};

// Watches a sweep that is *supposed* not to finish, and stops it as soon as it
// has gone far enough to prove the point.
//
// Far enough is one thousandth of the seed space, because the seed these
// captures would wrongly solve for sits in the first block claimed - so a sweep
// that has published any progress at all has already been past it and refused
// it. That is the whole assertion, and taking it from the engine's own counter
// rather than from a wall-clock budget is what makes it machine-independent: a
// slow runner takes longer to get there and the check is just as sharp, where a
// timed budget on a slow enough runner passes without proving anything.
//
// `deadline_ms` is only a backstop against an engine that publishes nothing at
// all - a wedged sweep would otherwise hang CI rather than fail it - and
// reaching it is a failure, not a pass.
//
// Separate from `stopper` below, which waits on `threads_started` instead and
// makes assertions of its own about the stop landing.
struct sweep_watch {
    struct faaccrack_progress *channel;
    unsigned deadline_ms;
    // Caller -> watcher: the search returned, so there is nothing left to stop.
    // Set before the join. Without it an engine that wrongly solved in
    // milliseconds would leave this thread polling until the backstop.
    volatile int search_returned;
    int reached;   // progress was published, which is the assertion
    int gave_up;   // the backstop fired first
};

static void *stop_once_swept(void *arg) {
    struct sweep_watch *w = arg;
    const uint64_t deadline = PROBE_NOW_MS() + w->deadline_ms;
    for (;;) {
        if (w->channel->permille >= 1) {
            w->reached = 1;
            break;
        }
        if (w->search_returned) break;
        if (PROBE_NOW_MS() > deadline) {
            w->gave_up = 1;
            break;
        }
        PROBE_SLEEP_MS(1);
    }
    w->channel->abort = 1;
    return NULL;
}

static void probe_gaps(void) {
    for (size_t i = 0; i < sizeof gapped_answers / sizeof gapped_answers[0]; i++) {
        const struct gapped_answer *want = &gapped_answers[i];
        struct faaccrack_progress progress;
        struct faaccrack_result got;
        memset(&progress, 0, sizeof progress);

        const int status = faaccrack_search(want->mode, want->fix, want->hops,
                                            want->nhop, 2, &progress, &got);

        char label[96];
        snprintf(label, sizeof label, "%s solves", want->name);
        check_eq(label, status, FAACCRACK_OK);
        if (status != FAACCRACK_OK) continue;

        snprintf(label, sizeof label, "%s gives the right seed", want->name);
        check(label, got.seed == want->seed);
        snprintf(label, sizeof label, "%s reports the last counter", want->name);
        check(label, got.counter == want->counter);
        snprintf(label, sizeof label, "%s rebuilds the captured frame", want->name);
        check(label, got.round_trip_ok == 1);
        snprintf(label, sizeof label, "%s used every hop it was given", want->name);
        check(label, got.hops_used == want->nhop);
    }

    // A refusal costs what a rejection costs - the whole seed space, which is
    // minutes at the two threads asked for below - so each is stopped as soon as
    // the engine's own counter says it has swept past the seed these captures
    // would wrongly solve for. `stop_once_swept` has the reasoning.
    for (size_t i = 0; i < sizeof refused_captures / sizeof refused_captures[0];
         i++) {
        const struct refused_capture *want = &refused_captures[i];
        struct faaccrack_progress running;
        struct faaccrack_result result;
        memset(&running, 0, sizeof running);
        struct sweep_watch watch = {&running, 5000u, 0, 0, 0};

        pthread_t watcher;
        if (pthread_create(&watcher, 0, stop_once_swept, &watch) != 0) {
            check("the watcher thread starts", 0);
            return;
        }
        // The fix and the mode of the row these were generated against, so the
        // table cannot be regenerated out from under them. Mode 3 arrives here
        // as the table's own literal, which is deliberate: the engine
        // hard-codes the four numbers, so a macro would still pass after a
        // renumbering had sent another manufacturer's key.
        const int status =
            faaccrack_search(gapped_answers[0].mode, gapped_answers[0].fix,
                             want->hops, 3, 2, &running, &result);
        watch.search_returned = 1;
        pthread_join(watcher, 0);

        char label[96];
        snprintf(label, sizeof label, "%s is swept past and refused", want->name);
        check(label, watch.reached && !watch.gave_up);
        // Pairs with the progress. An engine that wrongly accepted answers OK
        // from the first block, before any progress is published, so the two
        // together are what make this neither vacuous nor timing-dependent.
        snprintf(label, sizeof label, "%s ends as stopped, not solved", want->name);
        check_eq(label, status, FAACCRACK_STOPPED);
    }
}

// ---- argument refusals, against the engine rather than the CLI -------------

static void probe_refusals(void) {
    struct faaccrack_progress progress;
    struct faaccrack_result result;
    memset(&progress, 0, sizeof progress);
    // So that a call which is *accepted* still returns at once.
    progress.abort = 1;

    const uint32_t hops[FAACCRACK_MAX_HOPS + 1] = {0};

    check_eq("a null result is refused",
             faaccrack_search(FAACCRACK_MODE_GENIUS, 0, hops, 2, 1, &progress, NULL),
             FAACCRACK_BAD_ARGS);
    check_eq("zero threads is refused",
             faaccrack_search(FAACCRACK_MODE_GENIUS, 0, hops, 2, 0, &progress, &result),
             FAACCRACK_BAD_ARGS);
    check_eq("a negative thread count is refused",
             faaccrack_search(FAACCRACK_MODE_GENIUS, 0, hops, 2, -1, &progress, &result),
             FAACCRACK_BAD_ARGS);
    check_eq("a mode below the first is refused",
             faaccrack_search(FAACCRACK_MODE_MIN - 1, 0, hops, 2, 1, &progress, &result),
             FAACCRACK_BAD_ARGS);
    check_eq("a mode past the last is refused",
             faaccrack_search(FAACCRACK_MODE_MAX + 1, 0, hops, 2, 1, &progress, &result),
             FAACCRACK_BAD_ARGS);
    check_eq("null hops are refused",
             faaccrack_search(FAACCRACK_MODE_GENIUS, 0, NULL, 2, 1, &progress, &result),
             FAACCRACK_BAD_ARGS);
    check_eq("no hops at all is refused",
             faaccrack_search(FAACCRACK_MODE_GENIUS, 0, hops, 0, 1, &progress, &result),
             FAACCRACK_BAD_ARGS);
    check_eq("one hop is refused",
             faaccrack_search(FAACCRACK_MODE_GENIUS, 0, hops,
                              FAACCRACK_MIN_HOPS - 1, 1, &progress, &result),
             FAACCRACK_BAD_ARGS);
    check_eq("more hops than the engine takes is refused",
             faaccrack_search(FAACCRACK_MODE_GENIUS, 0, hops,
                              FAACCRACK_MAX_HOPS + 1, 1, &progress, &result),
             FAACCRACK_BAD_ARGS);
    // A null channel on a path that returns without sweeping. It shows the null
    // is not dereferenced during validation, which is as much as can be checked
    // cheaply - see the note at the top of this file.
    check_eq("a null progress channel does not crash validation",
             faaccrack_search(FAACCRACK_MODE_MAX + 1, 0, hops, 2, 1, NULL, &result),
             FAACCRACK_BAD_ARGS);

    // The accepting side of each bound, so the refusals above are known to be
    // about the bound rather than about the call being malformed some other
    // way - and, since the self-test probe left the gate taken and released,
    // these are also what would fail with BUSY if it had leaked.
    check_eq("the fewest hops allowed is accepted",
             faaccrack_search(FAACCRACK_MODE_GENIUS, UNSOLVABLE_FIX, hops,
                              FAACCRACK_MIN_HOPS, 1, &progress, &result),
             FAACCRACK_STOPPED);
    check_eq("the most hops allowed is accepted",
             faaccrack_search(FAACCRACK_MODE_GENIUS, UNSOLVABLE_FIX, hops,
                              FAACCRACK_MAX_HOPS, 1, &progress, &result),
             FAACCRACK_STOPPED);
    for (uint32_t mode = FAACCRACK_MODE_MIN; mode <= FAACCRACK_MODE_MAX; mode++) {
        char label[64];
        snprintf(label, sizeof label, "mode %u is accepted", mode);
        check_eq(label,
                 faaccrack_search(mode, UNSOLVABLE_FIX, hops, 2, 1, &progress, &result),
                 FAACCRACK_STOPPED);
    }

    // The result is zeroed before the busy gate, so no path except a null
    // result hands back a previous search's find.
    memset(&result, 0xAB, sizeof result);
    (void)faaccrack_search(FAACCRACK_MODE_GENIUS, UNSOLVABLE_FIX, hops, 2, 1,
                           &progress, &result);
    check("a refused search leaves no stale seed behind",
          result.seed == 0 && result.lrkey == 0 && result.round_trip_ok == 0);
}

// ---- stop latency and the busy gate, with a sweep actually running ----------

// What the stopper thread saw, read by the main thread after joining it.
//
// Deliberately not `check()` from inside the thread: that increments a plain
// `int` while the main thread is inside the search and may also be reporting,
// so a failure observed here could be lost - a red probe quietly going green,
// which is the one outcome a guard must not have.
struct stopper_report {
    struct faaccrack_progress *channel;
    int threads_seen;
    int concurrent_status;
    int gave_up_waiting;
};

static void *stopper(void *arg) {
    struct stopper_report *report = arg;

    // Wait for the sweep to be provably under way rather than sleeping a fixed
    // interval and hoping. A loaded runner that takes longer than a blind sleep
    // allowed would otherwise fail an assertion about the engine for a reason
    // that is about the machine.
    const uint64_t deadline = PROBE_NOW_MS() + 5000u;
    while (report->channel->threads_started == 0) {
        if (PROBE_NOW_MS() > deadline) {
            report->gave_up_waiting = 1;
            break;
        }
        PROBE_SLEEP_MS(1);
    }
    report->threads_seen = (int)report->channel->threads_started;

    // Then let it run a little. Without this the abort arrives while the
    // workers are claiming their first chunk, which proves the flag is read but
    // not that it is read *again* - and reading it once is exactly the bug this
    // engine was written to avoid.
    //
    // A fixed wait rather than waiting for `permille` to move, because this
    // group wants the abort to land *early* - the assertion below is that a stop
    // arrives in under two seconds. The gaps group does wait on `permille` and
    // measures it at about 110 ms at these two threads, so the two are different
    // needs rather than a premise that changed.
    PROBE_SLEEP_MS(25);

    // While that sweep is in flight, a second search must be turned away.
    struct faaccrack_progress other_progress;
    struct faaccrack_result other;
    memset(&other_progress, 0, sizeof other_progress);
    report->concurrent_status =
        faaccrack_search(FAACCRACK_MODE_GENIUS, UNSOLVABLE_FIX, unsolvable, 2, 1,
                         &other_progress, &other);

    report->channel->abort = 1;
    return NULL;
}

static void probe_stop(void) {
    struct faaccrack_progress running;
    struct faaccrack_result result;
    memset(&running, 0, sizeof running);

    struct stopper_report report;
    memset(&report, 0, sizeof report);
    report.channel = &running;

    pthread_t stop_thread;
    if (pthread_create(&stop_thread, 0, stopper, &report) != 0) {
        check("the stopper thread starts", 0);
        return;
    }

    // Two workers rather than many: the assertions are about the stop landing
    // and the count being reported, and a CI runner has few cores to oversubscribe.
    const int asked = 2;
    const uint64_t began = PROBE_NOW_MS();
    const int status = faaccrack_search(FAACCRACK_MODE_FAAC_SLH, UNSOLVABLE_FIX,
                                        unsolvable, 2, asked, &running, &result);
    const uint64_t elapsed = PROBE_NOW_MS() - began;
    pthread_join(stop_thread, 0);

    printf("stopped after %llums at %u permille, %u workers, status %d\n",
           (unsigned long long)elapsed, running.permille, running.threads_started,
           status);

    check("the sweep started within five seconds", report.gave_up_waiting == 0);
    check_eq("a stop is reported as stopped", status, FAACCRACK_STOPPED);
    // The point of reading `abort` per claimed chunk rather than per sweep. Two
    // seconds is loose on purpose - a loaded CI core is not a benchmark - and
    // still orders of magnitude under the whole-space sweep this interrupted.
    check("a stop lands within two seconds", elapsed < 2000);
    check("the sweep published progress", running.started == 1);
    check("and stopped before the end", running.permille < 1000);
    check("and reported the workers it got",
          report.threads_seen >= 1 && report.threads_seen <= asked);
    check_eq("a concurrent search is refused as busy", report.concurrent_status,
             FAACCRACK_BUSY);
}

int main(void) {
    // The header already carries this choice as a string.
    printf("faaccrack ABI probe: %s\n", faaccrack_variant_name());
    int mark = checks;
    probe_selftests();
    group_done("selftests", mark);
    mark = checks;
    probe_known_answers();
    group_done("known-answers", mark);
    mark = checks;
    probe_gaps();
    group_done("gaps", mark);
    mark = checks;
    probe_refusals();
    group_done("refusals", mark);
    mark = checks;
    probe_stop();
    group_done("stop", mark);
    printf("\n%s (%d checks, %d failed)\n", failures ? "PROBE FAILED" : "PROBE PASSED",
           checks, failures);
    return failures ? 1 : 0;
}
