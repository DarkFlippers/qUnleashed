# faaccrack (SubGHz rolling-code seed recovery)

Recovers the per-installation **seed** of a FAAC SLH, Genius, BFT or Erreka
remote from a fixed code and two or more consecutive hops, so the remote can be
rebuilt as a transmittable `.sub` rather than replayed. CPU only, no GPU, no
server. See DarkFlippers/qUnleashed#142.

The Flipper side is MMX's `seed_capturer` app, which only listens and writes the
fix and hops to `/ext/apps_data/subghz_seed_captures/*.txt`. It solves nothing
itself, exactly as `.nested.log` collection does for hardnested.

## State of this directory

**Nothing builds the engine yet** - there is no CMakeLists here, no dispatcher,
no FFI bridge, and nothing in `lib/` references it. Where the sections below
describe a dispatcher or a bridge, they describe the shape those will take,
copied from hardnested's, not a build that has run.

| | |
|---|---|
| `faaccrack.h` | the ABI. Hand-written, readable, and the canonical account of what the entry point promises |
| `faaccrack.c` | the engine. **Generated and obfuscated** - see below |
| `keep.txt` | the names the obfuscator must not rename, read by the regeneration command |
| `test/faaccrack_abi_probe.c` | a C probe that calls the entry point; `.github/scripts/check_faaccrack_engine.sh` builds and runs it |
| `BUILD_NOTES.md` | this: provenance, regeneration, build wiring |

The file list is also an allowlist: `test/faaccrack_obfuscation_test.dart` fails
on anything else appearing here, which is the guard against the private engine
source arriving under some other name.

### Remaining work

1. **A known-answer vector per mode**, and it is cheaper than it first looked.
   The sweep walks upward from seed zero, so a synthetic capture built around a
   *low* seed solves in milliseconds rather than the minutes a real capture
   needs - which means it belongs in the per-PR script rather than a nightly
   bench. One fixture closes three gaps at once: the mode numbering, which
   nothing currently couples to the header; that a real search finds a real
   seed; and `round_trip_ok` end to end. `lrkey` is the right thing to assert
   on, being key-derived and therefore mode-specific. Generating it needs the
   private kit once; the fixture it produces holds no secret, only a fix, hops
   and the expected answer.
2. `faaccrack_dispatch.c`, `faaccrack_bridge.c`, `CMakeLists.txt` and the Apple
   pod. None exist. The dispatcher also has to carry the single process-wide
   busy gate, because the engine's own is per compiled variant - `faaccrack.h`
   says why. `test/hardnested_sources_wired_test.dart` should be parameterised
   over both libraries at that point rather than copied: faaccrack will have the
   identical "a source in neither build list" problem.
3. Dart: the FFI binding, a parser for the capture `.txt`, the `.sub` writer and
   the UI. The progress struct will be the *third* hand-written Dart mirror of
   the same three words (`_HnProgress` in `hardnested_recoverer.dart` is
   private, which is why `tool/hn_bench.dart` already has a second); publishing
   one of them in `mifare_native.dart` is the way not to add a third.
4. A shared SIMD capability header under `lib/modules/cpp/`. The cascade in
   `faaccrack.h` re-derives tests that `hardnested/hardnested_bf_core.h` already
   centralises, and that copy carries two quirks this one does not - an
   Apple-clang version guard, and a workaround for clang reporting `__GNUC__` 4
   which once silently dropped AVX-512 from half of that library.

## Origin and what is public

The engine is a CPU port of a CUDA seed search, written by **xMasterX (MMX)**,
with Erreka added. It is bitsliced: the 32-bit KeeLoq state is held transposed
as 32 bit-planes of `VBITS` lanes, so one pass of the cipher advances `VBITS`
candidate seeds at once and the round function is about 18 bitwise operations
with no shifts and no table lookups.

**`faaccrack.c` is generated.** The readable source (`faaccrack.orig.c`), the
obfuscator (`cobf.py`) and the author's equivalence script (`verify_obf.sh`)
carry the four manufacture keys in readable form and **must not be added to this
repository.**

`.gitignore` names all three, unanchored, so they are ignored wherever they
land - but that is a convenience, not the guard: it does not survive `git add
-f`, a rename, or the keys arriving pasted into some other file. The guard is
the allowlist over this directory described above, which does not have to
predict what the file would be called.

There is no durable copy of that kit in any repository we control. It lives with
its author (xMasterX / MMX); if that contact is lost, this engine has to be
re-ported from scratch. That risk was accepted to keep the keys out of here.

The banner at the top of `faaccrack.c` points twice at `README_faaccrack.md`,
the engine's own CLI documentation. That file ships with the kit and is not
here; this document is the substitute, and the banner's reference is stale by
design.

### What the obfuscation does, and what it does not

It drops comments, renames every identifier the file owns to a confusable junk
name, moves every string into one XOR'd blob decoded by a constructor before
`main`, and turns every integer literal into an XOR pair the compiler folds at
build time.

The repo's `test/faaccrack_obfuscation_test.dart` asserts the structural
properties; its test names are the list, and its header says what each one can
and cannot see.

Be clear about what they show. They show **the literal-splitting and
string-blob passes ran over the whole file** - which is what makes the four
manufacture keys, the KeeLoq NLF constant, the Faac `0x544D` ending and the
round count absent in their own spelling. They do not show that any particular
value is unrecoverable: anyone who can build this can recover every constant
from the binary. Obfuscation raises the cost of reading the keys out of the
*source*; that is all it was ever for.

### Regenerating

```sh
python3 cobf.py faaccrack.orig.c -o faaccrack.c \
        --banner faaccrack.banner.txt \
        --keep "$(grep -v '^#' keep.txt | grep . | paste -sd,)"
./verify_obf.sh -O3 -funroll-loops
```

The list lives in `keep.txt`, not in this document, so that the thing passed to
the generator is the thing under review rather than a transcript of it. It was
in here once: a human edited prose and separately retyped a 32-name flag, and a
wrapped line would have quietly shortened the list without shortening the
engine. `test/faaccrack_engine_abi_test.dart` reads the same file and holds it
to the header and the engine.

**Why the list exists.** `cobf.py` builds its reserved-name set by preprocessing
the source's own `#include <...>` lines - **angle brackets only**. `faaccrack.h`
is quote-included, so it contributes nothing, and every name the engine spells
from it has to be named there or it gets renamed.

**A miss is loud, with two exceptions.** For a name the header declares and the
engine uses, a miss means the engine defines a differently-spelled function or
field than the header declares, and the compile or the link fails. The
exceptions are `VBITS` and `NLF12`, which the header does *not* declare: they
are the engine's own build-time macros, and if either is renamed the file still
compiles, links, passes its self-tests and solves correctly - while `-DVBITS=256`
and `-DNLF12=1` silently stop doing anything. A dead retuning knob that reports
success is exactly the failure the `--keep` test exists to catch. The `lanes`
field is the only runtime evidence `VBITS` is still live.

**Names the header owns but the engine never spells** are absent on purpose, and
the test holds a named reason for each. Adding a field to `faaccrack.h`
therefore means asking whether the engine reads it, not adding it to `keep.txt`
reflexively.

Two traps worth knowing before regenerating:

* **`cobf.py` needs a working `cc` on PATH and only *warns* when it has none.**
  With no reserved set it renames `printf` and `uint32_t` along with everything
  else, while still reporting a plausible byte count. That total failure is loud
  at the next step - nothing compiles - but check the run printed no
  `header preprocess failed` rather than relying on it. A *partial* reserved set
  (a `cc` that resolves some headers and not others) is the genuinely silent
  case, and only `verify_obf.sh` catches it.
* **No Windows toolchain ships a `cc.exe`,** and Python's `subprocess` will not
  start a `cc.bat` - CreateProcess only tries `.exe`. Regenerate on Linux, macOS
  or WSL. The threads note below is a second reason.

`verify_obf.sh` builds both sources, runs six searches - one per mode, a second
Genius run with one fewer hop, and a no-solution case - writes a `.sub` for each
and diffs everything with timings normalised out. A mismatch fails the script, so
a broken obfuscation cannot ship by accident. It needs a compiler that can link,
which the Android NDK alone cannot provide on Windows (no `lld-link`, no MinGW
sysroot); install LLVM, or use any Linux box.

## The ABI

`faaccrack.h` is the canonical account - who writes each field, what each status
means, which invariants are enforced and which are only documented. It is not
repeated here, because the two drifted apart within one commit the last time
they overlapped.

One thing belongs in this document rather than that one: **the four
`FAACCRACK_MODE_*` numbers are hard-coded inside the generated engine and are
not derived from the header.** Renumbering one here changes nothing there, the
build stays green, and a user attacking Erreka gets BFT's key and is told no
seed exists. Nothing in this repository can enforce the coupling without the
readable source. The bench's known-answer vector per mode is the only guard, and
`lrkey` is the right thing to assert on, being key-derived and therefore
mode-specific.

### What it will not do

It recovers the **seed**, not the manufacture key. Both keys are compiled in,
from the Flipper keystore, for four manufacturers only. A target using any other
manufacture key yields no seed - and the engine cannot tell that apart from a
capture with a missed press, or from the wrong mode being passed. `faaccrack.h`
spells out what the caller must therefore not say to the user.

## Threads

Real pthreads on Linux, Android, macOS, iOS and MinGW (winpthreads). clang-cl
and MSVC ship no `<pthread.h>`, so the engine includes `"pthread_shim.h"` -
unanchored, and the file lives with the hardnested library, so **this library's
build will need that directory on the include path.** The probe script already
passes it. The shim covers `pthread_t`, `pthread_create` and `pthread_join`,
which is all the engine uses.

That include is quoted, so by the rule above `cobf.py` reserves nothing from it.
The shim's names survive only because the POSIX `<pthread.h>` is angle-included
in the other branch and spells them identically - a third reason regeneration
has to happen on a POSIX host.

Hoisting the shim to `lib/modules/cpp/` shared by both libraries would be
tidier, and cheaper than it looks: the include is unanchored, so nothing in the
generated engine would change, and on hardnested's side it is one line in
`CMakeLists.txt` plus one in the podspec. The Apple unity build needs no edit at
all - it lists `.c` sources, and this is a header.

The real reason it is left alone: hardnested resolves it today with **no build
configuration whatsoever**, because a quoted include resolves relative to the
including file and its two users sit beside it. Hoisting would make a
Windows-only, MSVC/clang-cl-only compile branch depend on an include path, on
the one platform whose native build is exercised only in the tagged-release job,
in exchange for nothing behavioural. If it does move, the shim's own header
should name the libraries that include it, or it becomes an orphan neither owns.

## SIMD

One source, compiled once per instruction set, with the winner picked at
runtime - the shape hardnested uses. The variant's symbol name comes from
`faaccrack.h`, from the compiler's own `__AVX2__`-style macros, so the same file
becomes `faaccrack_search_AVX2`, `_AVX512`, `_NEON` and the rest without a
second source. Checked by hand before any CMake existed: compiling the one file
with different `-m` flags gives one object per flag, each exporting exactly one
of those symbols and no other name but `main`.

Unlike hardnested there is **no scalar fallback to degrade to**: the engine is
built on GCC/Clang vector extensions, which MSVC cannot compile at all. So
clang-cl will be *required* on Windows rather than looked up, and an unsupported
target has to fail at the `#error` in the header rather than compile - a
`vector_size` type scalarises for any target, so without that a fall-through
platform would build a library exporting a name no dispatcher has an entry for.

A Windows CI job without the component therefore fails rather than degrading.
hardnested's CMake looks clang-cl up and warns when it is missing; a Windows
release build log from that library shows clang-cl being invoked on the hosted
`windows-latest` image, so the component is there today - but nothing in this
repository asserts it, and the first Windows build of *this* library is the real
check. Locally: the VS "C++ Clang tools for Windows" component, or standalone
LLVM.

`-Wno-psabi` on the x86 variants below AVX-512, because passing a 512-bit vector
by value has an unstable ABI without `avx512f` and clang says so twice per
variant. It cannot matter here - the vector type never crosses a translation
unit, and every function taking one is static and inlined - and the warning
would otherwise bury real ones.

The library objects compile with `main` renamed away, so the shipped
`.dll`/`.so` exports the variant entries and the bridge and no `main`. The probe
script does the same, which is the first evidence the trick works.

## Retuning

`-DVBITS=256` or `-DVBITS=1024` changes the lane count, `-DNLF12=1` selects a
12-operation NLF network instead of the 15-operation one. Both were measured by
the author and both were *slower* on the hardware he had: the short NLF by ~25%
(two gate levels deeper, and this loop is latency-bound), narrower vectors by
~40% (the op count per lane-block is fixed, so you get fewer lanes for it).

He did not record the machine, the compiler or the date, and nothing here
re-measures them. Treat both figures as the reason the defaults are the defaults,
not as numbers to plan against. They are knobs for hardware that schedules
differently, not suggestions - and check `lanes` in the result if you use one,
because the `--keep` note above explains how `-DVBITS` can be silently ignored.
