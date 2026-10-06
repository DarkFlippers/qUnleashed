// Drives the committed engine through its library entry point and checks the
// contract the header promises.
//
// Why this exists, and why it is cheap: the engine's own equivalence script
// (`verify_obf.sh`, see ../BUILD_NOTES.md) cannot live in this repository - it
// needs the readable source - and it drives the *command line* anyway, which is
// not the path the app uses. Everything below exercises `FAACCRACK_SEARCH`
// directly, needs no CMake, no dispatcher, no Dart and no private source, and
// finishes in well under a second.
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
//  * Anything about the dispatcher or the per-ISA variant names. This compiles
//    one variant, whichever the host's flags select.
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

// A fix with hops whose counters cannot be consecutive, so the sweep runs the
// whole space and can be interrupted rather than finishing first.
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

    const int status = FAACCRACK_SEARCH(FAACCRACK_MODE_FAAC_SLH, UNSOLVABLE_FIX,
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

        const int status = FAACCRACK_SEARCH(want->mode, want->fix, want->hops, 3, 2,
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
        snprintf(label, sizeof label, "%s says how many hops backed it", want->name);
        check(label, got.hops_used == 3);
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
             FAACCRACK_SEARCH(FAACCRACK_MODE_GENIUS, 0, hops, 2, 1, &progress, NULL),
             FAACCRACK_BAD_ARGS);
    check_eq("zero threads is refused",
             FAACCRACK_SEARCH(FAACCRACK_MODE_GENIUS, 0, hops, 2, 0, &progress, &result),
             FAACCRACK_BAD_ARGS);
    check_eq("a negative thread count is refused",
             FAACCRACK_SEARCH(FAACCRACK_MODE_GENIUS, 0, hops, 2, -1, &progress, &result),
             FAACCRACK_BAD_ARGS);
    check_eq("a mode below the first is refused",
             FAACCRACK_SEARCH(FAACCRACK_MODE_MIN - 1, 0, hops, 2, 1, &progress, &result),
             FAACCRACK_BAD_ARGS);
    check_eq("a mode past the last is refused",
             FAACCRACK_SEARCH(FAACCRACK_MODE_MAX + 1, 0, hops, 2, 1, &progress, &result),
             FAACCRACK_BAD_ARGS);
    check_eq("null hops are refused",
             FAACCRACK_SEARCH(FAACCRACK_MODE_GENIUS, 0, NULL, 2, 1, &progress, &result),
             FAACCRACK_BAD_ARGS);
    check_eq("no hops at all is refused",
             FAACCRACK_SEARCH(FAACCRACK_MODE_GENIUS, 0, hops, 0, 1, &progress, &result),
             FAACCRACK_BAD_ARGS);
    check_eq("one hop is refused",
             FAACCRACK_SEARCH(FAACCRACK_MODE_GENIUS, 0, hops,
                              FAACCRACK_MIN_HOPS - 1, 1, &progress, &result),
             FAACCRACK_BAD_ARGS);
    check_eq("more hops than the engine takes is refused",
             FAACCRACK_SEARCH(FAACCRACK_MODE_GENIUS, 0, hops,
                              FAACCRACK_MAX_HOPS + 1, 1, &progress, &result),
             FAACCRACK_BAD_ARGS);
    // A null channel on a path that returns without sweeping. It shows the null
    // is not dereferenced during validation, which is as much as can be checked
    // cheaply - see the note at the top of this file.
    check_eq("a null progress channel does not crash validation",
             FAACCRACK_SEARCH(FAACCRACK_MODE_MAX + 1, 0, hops, 2, 1, NULL, &result),
             FAACCRACK_BAD_ARGS);

    // The accepting side of each bound, so the refusals above are known to be
    // about the bound rather than about the call being malformed some other
    // way - and, since the self-test probe left the gate taken and released,
    // these are also what would fail with BUSY if it had leaked.
    check_eq("the fewest hops allowed is accepted",
             FAACCRACK_SEARCH(FAACCRACK_MODE_GENIUS, UNSOLVABLE_FIX, hops,
                              FAACCRACK_MIN_HOPS, 1, &progress, &result),
             FAACCRACK_STOPPED);
    check_eq("the most hops allowed is accepted",
             FAACCRACK_SEARCH(FAACCRACK_MODE_GENIUS, UNSOLVABLE_FIX, hops,
                              FAACCRACK_MAX_HOPS, 1, &progress, &result),
             FAACCRACK_STOPPED);
    for (uint32_t mode = FAACCRACK_MODE_MIN; mode <= FAACCRACK_MODE_MAX; mode++) {
        char label[64];
        snprintf(label, sizeof label, "mode %u is accepted", mode);
        check_eq(label,
                 FAACCRACK_SEARCH(mode, UNSOLVABLE_FIX, hops, 2, 1, &progress, &result),
                 FAACCRACK_STOPPED);
    }

    // The result is zeroed before the busy gate, so no path except a null
    // result hands back a previous search's find.
    memset(&result, 0xAB, sizeof result);
    (void)FAACCRACK_SEARCH(FAACCRACK_MODE_GENIUS, UNSOLVABLE_FIX, hops, 2, 1,
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
    // engine was written to avoid. `permille` is no use as the signal: it is
    // integer thousandths of 65536 chunks, so it stays 0 for the first sixty-odd
    // and waiting for it to move would cost most of a second.
    PROBE_SLEEP_MS(25);

    // While that sweep is in flight, a second search must be turned away.
    struct faaccrack_progress other_progress;
    struct faaccrack_result other;
    memset(&other_progress, 0, sizeof other_progress);
    report->concurrent_status =
        FAACCRACK_SEARCH(FAACCRACK_MODE_GENIUS, UNSOLVABLE_FIX, unsolvable, 2, 1,
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
    const int status = FAACCRACK_SEARCH(FAACCRACK_MODE_FAAC_SLH, UNSOLVABLE_FIX,
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

// Which variant the host's flags selected, so a run says what it tested.
#define PROBE_STRINGIFY_(x) #x
#define PROBE_STRINGIFY(x) PROBE_STRINGIFY_(x)

int main(void) {
    printf("faaccrack ABI probe: %s\n", PROBE_STRINGIFY(FAACCRACK_SEARCH));
    probe_selftests();
    probe_known_answers();
    probe_refusals();
    probe_stop();
    printf("\n%s (%d checks, %d failed)\n", failures ? "PROBE FAILED" : "PROBE PASSED",
           checks, failures);
    return failures ? 1 : 0;
}
