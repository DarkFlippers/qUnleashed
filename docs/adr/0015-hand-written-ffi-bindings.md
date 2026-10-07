# 0015. FFI bindings are hand-written, and guarded by comparing source text
Status: Accepted (2026-10-07)

## Context

The app calls three native libraries of its own — `qunleashed_mfkey32`,
`qunleashed_hardnested` and `qunleashed_faaccrack`, under
[`lib/modules/cpp/`](../../lib/modules/cpp/). Every `Struct` and every
`typedef` that reaches them is typed out by hand in
[`lib/services/native.dart`](../../lib/services/native.dart) and in the two
recoverers.

Nothing in the toolchain connects the two sides. Add a field to a C struct and
Dart reads the wrong offsets with no compile error, no link error, and a
plausible-looking answer. That answer is written to the user's device: a seed
recovered from the wrong word is a `.sub` that opens nothing, and a gate that
will not open gives nobody a reason to suspect the app.

Three facts shaped the decision rather than the general problem:

- **The structs are tiny and fixed.** The two progress channels are three and
  four 32-bit words; `faaccrack_result` is a 64-bit key and eight words. They
  change when the C ABI changes, which is rarely and deliberately.
- **The declarations are where the reasoning lives.** Why the channel is polled
  shared memory and not an FFI callback, why the fields are `volatile` and not
  `_Atomic`, what a stop costs and which phases do not read `abort` — all of it
  is written against the individual fields, in
  [`qunleashed_hn_progress.h`](../../lib/modules/cpp/hardnested/qunleashed_hn_progress.h)
  and [`faaccrack.h`](../../lib/modules/cpp/faaccrack/faaccrack.h).
- **Two libraries share three words and differ in the fourth.**
  `qunleashed_hn_progress` is `permille`, `abort`, `started`;
  `faaccrack_progress` adds `threads_started`.

## Decision

Bindings stay hand-written. One Dart mirror, `NativeProgress`, serves both
progress channels and declares the longer shape — all four words — so under
hardnested the fourth is slack the engine cannot reach.

The C structs stay separate. The guard is layered, and each layer closes a hole
the others cannot see:

| Layer | What it pins | Where |
|---|---|---|
| `_Static_assert` per offset | the compiler laid the C struct out as the declaration reads | both headers |
| exported size + release-path check | the shipped binary matches the header it was built from | faaccrack only |
| source-text field comparison | the Dart mirror names the same fields in the same order | `test/native_struct_mirror_test.dart` |
| `sizeOf` and a write-through | the Dart mirror's real layout, the one the engine is handed | `test/native_progress_layout_test.dart` |

The source-text layer carries the asymmetry explicitly: faaccrack's struct must
**equal** the mirror, hardnested's must be a **prefix** of it. A field added to
the hardnested struct would otherwise land on `threads_started` and be read as
it.

## Rejected alternatives (and why)

**A shared C struct.** The obvious way to stop the two sides drifting is for the
two libraries to include one header. They are independent: hardnested is a
ciphertext-only MIFARE attack, faaccrack a KeeLoq seed search, and nothing else
couples them. Making one include the other's header to share three words means
a change to either ABI is a change to both, forever, to avoid one Dart
declaration with four fields.

**Generated bindings (`ffigen`).** Nothing in this project's rules forbids it:
[0005](0005-tolerant-decoding.md)'s objection is to `build_runner` and to a
decoder that throws on the first bad field, neither of which applies to a
fixed-layout struct, and the repository already ships committed generated
protobuf in `flipperlib`. It is rejected on this codebase's own cost test, the
one [0004](0004-ratchet-not-lint.md) applied to `custom_lint`. `ffigen` would
retire about twenty-five lines of struct and typedef declarations. It would
retire none of what `native.dart` actually does — the per-platform library
search, the Apple `DynamicLibrary.process()` case,
`NativeEngineUnavailable` classification, `lookupNativeFunction`,
`spawnAttackIsolate`. In exchange it wants libclang on every machine that
regenerates, and if the guard is to be "regenerate and diff" — the only shape
stronger than what is here — libclang in CI too.

Two costs beyond the trade. It emits one struct per header, so the shared mirror
this ADR is about could not exist. And it carries no comments, so the reasoning
that lives against the fields would move to a wrapper, and "is the wrapper still
aligned with the generated struct" is the same question again one level up.

**What would change the answer:** a fourth native library, or a struct past a
handful of fields. At that point the declarations stop being readable in one
screen and the hand-maintained guard stops being cheaper than the tool.

**Forbidding the read instead of removing the rule.** An earlier draft of
`NativeProgress` said no hardnested caller may read `threadsStarted`. That is a
rule no test and no compiler can see — the field is public, as every `dart:ffi`
struct field is. It was replaced by a contract true on both engines: zero means
no count has been published, hardnested never publishes one, and faaccrack
publishes at least one once the sweep begins. A rule that does not need
enforcing beats an unenforced one. A ratchet in the shape of
`test/unawaited_budget_test.dart` would have worked ([0004](0004-ratchet-not-lint.md)),
and is what to reach for if a future field cannot be reworded this way.

**Two Dart structs, the three-word one nested by value in the four-word one.**
This makes the misuse unrepresentable rather than merely harmless, needs no
codegen, and keeps `sizeOf` at 16. It is the right shape the moment a caller
reads `threadsStarted` — today none does, in `lib/`, `tool/` or `test/` — and it
costs the mirror test a notion of seeing fields through an embedded member.
Deferred, not refused.

## Consequences

- Adding a field to a C struct is a four-file change: the struct, its
  `_Static_assert`s, the Dart mirror, and — for faaccrack — nothing else,
  because the exported size check is already generic.
- A field added to `faaccrack_progress` must be added to `NativeProgress`.
  A field added to `qunleashed_hn_progress` must be added to `NativeProgress`
  **and** to `faaccrack_progress`, or the prefix rule breaks. The test says so
  when it fails.
- `test/native_struct_mirror_test.dart` reads C headers with a regex, so it sees
  only `uint32_t` and `uint64_t` members. Its own "What it cannot see" section
  is part of the guard and is kept current.
- CI compiles no native code except the faaccrack engine probe
  (`.github/scripts/check_faaccrack_engine.sh`), so hardnested's
  `_Static_assert`s first fire on a local build or a release job. On a pull
  request the two test files above are the whole of that library's cover, which
  is why the source-text layer checks that the assertions are present and say
  what they should rather than trusting the compiler to have run.

## Migration: what happens to legacy code

Nothing to migrate. The three duplicated progress mirrors this ADR replaced
(`_HnProgress`, `tool/hn_bench.dart`'s `HnProgress`, `_FaaccrackProgress`) are
already gone. `_FaaccrackResult` stays private to its recoverer: it has one
reader and faaccrack's release-path size check covers it, which is the asymmetry
that made the progress channel the one needing a published mirror.
