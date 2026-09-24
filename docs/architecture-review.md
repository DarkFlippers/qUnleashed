# Architecture review against a reference project

> Inputs: `docs/architecture.md` (as-is, `11107c0`); the reference is
> `C:\Projects\Ralliva\app\CLAUDE.md` together with that project's structure;
> the neutral benchmark is <https://docs.flutter.dev/app-architecture>.
> There was no earlier analysis of this project.
>
> Verdicts are `KEEP` / `MIGRATE` / `NOT WORTH IT` (the reference is better,
> but the price is not justified). Cost: S ≤ 10 files, M ≤ 50, L > 50.

## First, something about the reference

Ralliva is **39 `.dart` files in `lib/` and 4 test files**. qUnleashed is
**454 and 51**. That is not the same project done more tidily: it is an
eleven-fold difference, and with it a difference in domain. Ralliva has no
device, no two transports, no native C/C++, no desktop targets and no
home-screen widget with its own isolate entry point.

So the reference says a great deal about things qUnleashed does not have (Dio,
OAuth, tokens, themes generated from a design repo) and almost nothing about
what is hardest here — the session, the RPC queue, reconnect, DFU.

**And one correction that changes a verdict.** Flutter's official architecture
case study (`docs.flutter.dev/app-architecture/case-study`) is built on
`ChangeNotifier` and `package:provider`, not on Riverpod, and says plainly:

> "The UI of this app leans heavily on view models and `ChangeNotifier`, but
> it could've easily been written with streams, or with other libraries such
> as `riverpod`, `flutter_bloc`, and `signals`."

The guide itself is package-agnostic: "These recommendations are guidelines,
not steadfast rules." So Riverpod is Ralliva's choice for Ralliva's own
reasons (compile-checked lookups, `AsyncValue`), not an industry standard
qUnleashed has drifted away from.

## Summary table (before the counter-arguments)

> These are the **first-pass** verdicts. Four of them changed after the
> "Counter-arguments" section; the ones in force are in the final table at the
> end of this file.

| # | Area | Now | Reference | Verdict | Cost | Risk |
|---|---|---|---|---|---|---|
| 1 | Structure | feature-first `pages/` + layer `services/` | `ui/` `data/` `domain/` `routing/` `config/` | **KEEP** | L (454) | — |
| 2 | State | `ChangeNotifier` + `setState` | Riverpod 3 (`Notifier`) | **NOT WORTH IT** | L (85+) | connection state, lifecycle |
| 3 | DI | 28 global singletons | Riverpod providers | **MIGRATE** (new code only) | L if all | testability already suffers |
| 4 | Routing | hand-rolled registry + `Navigator` | `go_router` | **NOT WORTH IT** | M (26) | no deep links exist |
| 5 | Layers | no boundaries, 37 UI files reach the transport | View→VM→Repo→Service | **MIGRATE** (gradually) | L | highest value |
| 6 | BLE / transport | `flipperlib`: transport/session/client | no equivalent | **KEEP** | — | — |
| 7 | Device files | protobuf + 14 operations | no equivalent | **KEEP** | — | — |
| 8 | Errors | exceptions only, 49 silent `catch` | sealed failure hierarchies | **MIGRATE** (targeted) | M | silent catches hide regressions |
| 9 | Serialization | 135 hand-written `fromJson` | `json_serializable` | **NOT WORTH IT** | L | see §9 — there is direct evidence |
| 10 | Platform code | Kotlin widget, FFI, 4 desktops | AppDelegate and that is all | **KEEP** | — | — |
| 11 | Tests | 691 tests, 51 files | 4 files | **KEEP** | — | — |
| 12 | Dependencies | 44 direct | 10 direct | **KEEP** | — | — |
| 13 | Lint | `flutter_lints` + 1 rule | + `riverpod_lint` | **MIGRATE** (a different rule) | S | — |

## The areas where the verdict is not obvious

### 2. State management — **NOT WORTH IT**

The reference uses Riverpod 3 with `riverpod_lint`, arguing that "a missing
dependency is a build error, not a crash when a user taps a button."

That argument is strong, but it is about **DI**, not about state. The state
container itself (`ChangeNotifier`) matches the official case study. Migrating
would touch 29 `ChangeNotifier` classes, 56 files using `setState` and all of
their consumers — and that is the same layer device connection state travels
through.

**The risk is specific, not abstract:** three review rounds on PR #140 this
week showed that bugs in this code do not live where anyone is looking. Two of
the critical findings in round two came out of the **interaction** between two
separately correct mechanisms. Rewriting the layer reconnect runs through
produces exactly that class of defect, and none of it is caught by reading.

What Riverpod would buy here is taken by area 3, separately and more cheaply.

### 3. DI — **MIGRATE, but for new code only**

This is a real divergence from **both** benchmarks: Ralliva (Riverpod) and the
official case study (`package:provider`) both pass dependencies in rather than
reaching for global state. qUnleashed has 28 `static final X instance`.

A full migration is L. But the value is asymmetric: the pain of a singleton
shows up in a **test**, and tests are written for new code. So the rule "new
dependencies are passed in, existing singletons are left alone" captures most
of the benefit at cost S.

Evidence from this week: `test/firmware_fixture.dart` has a
`resetFirmwareState()` that manually resets **seven** process-wide singletons
between tests. That is the price already being paid.

### 4. Routing — **NOT WORTH IT**

`go_router` wins where there are URLs and deep links. In qUnleashed:

- `app_links` / `uni_links` / `deepLink` — **0 matches**;
- `web/` is excluded in `analysis_options.yaml` and **is not built in CI**;
- there are 10 routes and they are already collected in one place
  (`app/routes.dart`).

So the cost is M for a capability the project does not use. The hand-rolled
registry does exactly what it was built for: a feature never imports a sibling
feature.

**What would be worth doing instead** — remove the mixed state: 16 direct
`Navigator.push` calls inside features live by a different rule than the
registry. That needs no `go_router`.

### 5. Layers — **MIGRATE, gradually**

The most valuable area. The reference and the official guide agree: a View
does not talk to the transport. In qUnleashed `package:flipperlib` is imported
by 37 files under `lib/pages/`, 5 of them inside `widgets/`.

What that already costs is visible in one place: `FirmwareCard` both reads and
writes the active firmware, takes controllers from two different sources, and
three review rounds spent a noticeable share of their effort on its wiring.

**"Gradually" is not politeness.** A full move to
View→ViewModel→Repository→Service is L and carries the same risk as §2. The
working form is: a repository appears where a feature **already** has a
controller (today that is `devices`), and every new feature is written that way
from the start.

`lib/pages/devices/firmware/repository.dart` already exists and does exactly
this — a layer between UI and the network with its own state and error
classification. The pattern is in the tree; it is simply not stated as a rule.

### 8. Errors — **MIGRATE, targeted**

The reference models failures as sealed hierarchies and insists that a 4xx
must throw, with the repository translating a transport error into a domain
outcome. qUnleashed has 0 result types, 378 `catch`, of which 23 are typed and
**49 are empty `catch (_) {}`**.

A full move to result types is L and would fight the rest of the code. But two
pieces come cheaply:

1. **The 49 `catch (_) {}`.** Each hides something nobody will learn about.
   Issue #138 already records one in `manifest_registry.dart` that loses every
   installed app, partially and silently.
2. **A sealed hierarchy for one feature's failures** where the UI has to show
   different text. `FirmwareFetchState` (a three-state enum) is already the
   seed of that approach.

### 9. Serialization — **NOT WORTH IT**, and there is direct evidence

The reference uses `json_serializable` without `freezed`. Against 135
hand-written `fromJson` that looks like an obvious win.

There is evidence against it from this week. Issue #133 was precisely a
hand-written decoder defect: one changed field killed the whole document. But
**a generated decoder has the same flaw by default**: `json_serializable`
throws on the first bad field, which is exactly the behaviour PR #140 spent a
week removing. Reading entry by entry and keeping what parses is not something
codegen does, and it would have to be written by hand **on top of** the
generated code.

Also: `pubspec.yaml` has no `build_runner` at all, and both live feeds are
third-party with no schema versioning.

What is worth taking from #133 is not codegen but the **pattern**: `_each`,
`_text`, `_presentation` and a list of what was skipped. Issues #137 and #138
already name the places where the same defect remains.

### 13. Lint — **MIGRATE, but a different rule**

`riverpod_lint` without Riverpod is meaningless. But the reference's idea — a
rule that catches an architectural mistake during analysis — does apply:
qUnleashed has `flutter_lints` plus one rule (`unawaited_futures`).

What is useful here is not riverpod_lint but an import restriction that makes
area 5 self-checking: banning `package:flipperlib` inside
`lib/pages/**/widgets/**`. That is cost S and it extinguishes the existing
violations while stopping new ones appearing.

## What the reference does not cover at all

These are the hardest parts of qUnleashed, and Ralliva has neither an answer
nor a question for them:

- the session with its priority queue, `interleavable`, `holdsTxUntilAnswer`;
- auto-reconnect, and the file transfer that restarts after it;
- two isolate entry points (`main` / `widgetMain`) and the foreground service;
- DFU and firmware flashing;
- FFI into `lib/modules/cpp` (hardnested, mfkey32);
- 4 desktop targets.

For those the benchmark should not be Ralliva but this project's own ADRs.

---

# Counter-arguments (independent reviewer)

> Run as a separate subagent that saw only `docs/architecture.md` and the list
> of proposed migrations — none of the reasoning in this file. Its task was to
> argue against each proposal. Its conclusions are below, followed by my
> replies where I disagree.

## Corrections to the input numbers

I verified all three and accepted them; `docs/architecture.md` was corrected.

1. **`flipperlib`, `dartufbt` and `nfc-tools` are git submodules, separate
   repositories** (`.gitmodules`). So of the 49 empty `catch (_) {}`, **42 are
   in this repository and 7 are elsewhere**.
2. **A lint rule on `widgets/` catches 5 files, not 3.** My glob was one level
   deep (`lib/pages/*/widgets/`); the deeper ones are
   `archive/browser/widgets/storage_card.dart` and
   `tools/infrared/widgets/ir_file_viewer.dart`.
3. **The most important global does not have the `static final X instance`
   shape.** `FlipperOneClient()` is a factory singleton with **24 call sites**
   in `lib/` outside the modules.

## Its conclusions, proposal by proposal

**1. DI — "yes, but the target is wrong."** There is evidence of harm in the
repository (`resetFirmwareState()`, a test that passed vacuously, #139). But
the metric "28 singletons" covers neither of the two known breakages: in
`flibler_project_test.dart` the culprit is `SharedPreferences.getInstance()`
(and that test **already injects** its controller), and in
`logging_history_test.dart` it is `FlutterError.onError`. Separately: 27 of
the 28 have a private constructor, so a second instance is impossible by
construction, and injection removes that guarantee. The danger is the two
entry points: the graph assembled in `_runApp` does not exist in
`widgetMain()`.

**2. Layers — "mostly a matter of taste, and the most dangerous."**
`flipperlib` is not an internal layer but a separate repository with a designed
facade (`client/api/*.dart`); 37 imports are 37 imports of a dependency. Some
of them pull `flipperlib` in **only for a constructor type**, which is already
correct injection. Above all: a repository in the house idiom is a new
singleton, so proposals 1 and 2 conflict. A half-finished state leaves **three
owners of the cache** in one feature, and #136 is precisely that class of
defect.

**3. Errors — "split it in two."** The 49 catches are mostly a matter of taste:
most are deliberate best-effort (`mkdir` of a directory that may exist,
cleaning up temporary files in `finally`, writing a cache if it works out).
Sealed exception hierarchies — **against**: the most differentiated failure in
the app already has an answer, and it is `classifyConnectError` →
`FlipperConnectErrorKind` with an exhaustive `switch`. A sealed type is
**impossible in principle** there, because the classifier matches substrings
from platform BLE errors, and a `PlatformException` from Android GATT cannot
be made a member of your own hierarchy.

**4. Lint — "the rule cannot be written with what the project has."**
`flutter_lints` has no directory-scoped import restriction and `custom_lint` is
not in `pubspec.yaml`. So the price is a new analyzer plugin and a CI step, for
5 sites, two of which are correct constructor injection. The real smell —
`final FlipperClient _client = FlipperOneClient().get();` in
`firmware_card.dart:34` — is not what the rule catches.

**5. Routing — "no, and it would make things worse."** The registry takes
`Object? args` and casts at runtime, so converting trades a compiler check for
a runtime one. Half of the 16 pushes carry a **live controller**, and
`registerAppRoutes()` runs inside `_initCore` before `runApp` and has no access
to one. There are also callbacks whose result is read, `fullscreenDialog: true`
(which `openRoute` cannot express) and a `DeviceScope` re-wrap for the pushed
subtree. The split between cross-feature and in-feature navigation is a
deliberate boundary, written in the docs of both files.

## My replies

**I agree entirely — 3 of 5.**

- **Routing (5).** The argument dismantles my proposal with facts I had not
  checked: a live controller in half the pushes, and `routes.dart` running
  before `runApp`. My "remove the mixed state" would have made things worse.
  **Withdrawn.** What remains is the one real defect it found itself:
  `FlipperMapPage` is reachable through two doors, and the registry entrance
  cannot carry arguments.
- **Sealed hierarchies (3b).** `classifyConnectError` matches substrings from
  platform errors — a sealed type at the boundary with Android GATT is
  impossible. I had not checked that. **Withdrawn.**
- **Lint (4).** I wrote "cost S" without checking whether such a rule can be
  written at all. `custom_lint` is not in the project. Its alternative — a
  ratchet test on `analyzer` counting `FlipperOneClient()` under `lib/pages/**`
  — is better than mine: it catches the real defect rather than the location of
  an import, needs no new package, and repeats a pattern the repo already has
  (`test/log_level_budget_test.dart`). **Adopting its form.**

**I partly disagree — 2 of 5.**

- **DI (1).** Its refinement of the target is right and I am taking it. But I
  do not accept "27 of 28 have a private constructor, so injection removes a
  guarantee": a private constructor protects against an *accidental* second
  instance, not against the thing injection is for — being able to hand a test
  a different one. The cost of that guarantee is already visible:
  `resetFirmwareState()` resets seven singletons by hand, and that is exactly
  where one test passed vacuously. Its warning about `widgetMain()` is stronger
  than this argument and deserves its own ADR.

- **Empty catches (3a).** "Most are deliberate best-effort" it proved by
  reading, and I accept that. But "the backlog is not growing: 43 → 42" is one
  data point over a few days, which is not a trend. The conclusion does not
  change either way: the target should not be the number but the subset "a bare
  catch on a path where the UI is left in an unresolved state" — the shape of
  #118/#134, which has already cost three shipped bugs.

**Its observation outside the question**, worth recording separately: of ~850
commits exactly one came from an outside contributor, and there is no
`CONTRIBUTING.md`. If the concern is the barrier to entry for an open-source
project, that is a cheaper lever than any of the five migrations.

---

# Final verdict table

After the counter-arguments. Changed rows are marked **(changed)**.

| # | Area | Verdict | What exactly | Cost |
|---|---|---|---|---|
| 1 | Structure | **KEEP** | — | — |
| 2 | State | **NOT WORTH IT** | `ChangeNotifier` matches the official case study | — |
| 3 | DI | **MIGRATE** *(changed)* | target is not "28 singletons" but process state leaking between tests; composition root in `_initCore`; a separate ADR for the two entry points | M |
| 4 | Routing | **NOT WORTH IT** *(changed)* | leave the 16 pushes alone; fix only the arguments on `AppRoute.archiveMap` | S |
| 5 | Layers | **NOT WORTH IT overall** *(changed)* | instead of a layer, ban I/O in `build`/`didUpdateWidget`; a repository only where two callers already share a cache | M |
| 6 | Transport | **KEEP** | — | — |
| 7 | Device files | **KEEP** | — | — |
| 8 | Errors | **MIGRATE** *(narrowed)* | only bare catches on paths with unresolved UI state (#117/#118); sealed exception hierarchies withdrawn | M |
| 9 | Serialization | **NOT WORTH IT** | codegen throws on the first bad field — that is defect #133 | — |
| 10 | Platform code | **KEEP** | — | — |
| 11 | Tests | **KEEP** | — | — |
| 12 | Dependencies | **KEEP** | — | — |
| 13 | Lint | **MIGRATE** *(different form)* | not `custom_lint` but a ratchet test on `analyzer` counting `FlipperOneClient()` under `lib/pages/**` | S |

**Outside the table, as a result of the review:** `CONTRIBUTING.md` — one
outside commit out of ~850 and no description of how to start.

---

# Revision: the submodules are ours

`flipperlib` and `dartufbt` belong to the same organisation
(`DarkFlippers/dart-flipperlib`, `DarkFlippers/dart-ufbt`), so changes to them
are possible — a PR in their own repository and a submodule bump here. Only
`lib/modules/cpp/nfc-tools` (`flipperdevices`, and C rather than Dart) stays
out of reach.

That removes the premise two arguments above rested on, and **opens a finding
that was not visible at all**.

## What changes

### Area 11, Tests — **KEEP → MIGRATE. This is now the most valuable area.**

My verdict of "691 tests against the reference's 4, keep it" counted only
`test/` in this repository. Counting all the code the organisation owns:

| Part | `.dart` files | Test files |
|---|---|---|
| app (`lib/` without `modules/`) | 324 | 51 |
| `flipperlib` | 96 | **0** |
| `dartufbt` | 31 | 1 |

`flipperlib`'s CI runs `dart format` and `flutter analyze`; **it has no
`flutter test` step**. What is left uncovered is exactly the code holding the
priority queue, `interleavable`, `holdsTxUntilAnswer`, auto-reconnect with
`reconnectSettle`, the file transfer that restarts after a session is restored,
and DFU.

This inverts the cost-versus-risk balance for everything else in this document:
every argument of the form "rewriting the layer reconnect runs through is
dangerous" rested on there being nothing to catch the breakage — and that is
literally true.

**What to do:** not "cover 96 files", but start with what has already broken.
The queue and the error classifier (`classifyConnectError`) are pure functions
over data and test without a device. `FakeFlipperClient` in
`test/firmware_fixture.dart` already shows the seam exists. Adding a
`flutter test` step to the submodule's CI is S, and it locks the result in.

### Area 3, DI — the argument against is withdrawn

The reviewer's strongest objection was: "the most important global stays out of
reach — `FlipperOneClient()` in 24 places, and it cannot be fixed by a PR in
this repository." The second half is false. The seam can be made in
`flipperlib`, where the factory is declared.

The verdict stays **MIGRATE**, but the value is higher than I estimated: the
target now includes the global almost every feature reaches for.

### Area 8, Errors — all 49 are ours, and 4 of them are in an isolate

All 7 "foreign" empty catches are in `flipperlib`, not in `nfc-tools`. The
reviewer's correction — "42 in this repository" — is technically right, but the
conclusion drawn from it ("a PR here will not remove them") is not.

Four of the seven are in `transport/usb/isolate.dart`, and that place deserves
a separate mention: inside an isolate a swallowed error is invisible **by
construction**, because there is no zone for it to surface into. Three of them
(`port.close()`, `port.dispose()`) are correct best-effort — there the reviewer
is right.

### Area 5, Layers — same verdict, but another option appears

The argument that "`flipperlib` is a separate repository with a designed
facade, and 37 imports are just imports of a dependency" loses its first half.
The facade is ours.

That does **not** bring back the repository-layer proposal — the remaining
objections hold without it (some of the 37 imports pull in only a constructor
type; a repository in the house idiom is a new singleton; a half-finished state
gives three owners of the cache). But it opens a cheaper alternative: stop
`flipperlib` exposing a global factory as the only way to get a client, and
those 24 call sites become a visible dependency with no new layer in the app at
all.

## Updated final table

| # | Area | Verdict | Cost |
|---|---|---|---|
| 11 | **Tests (submodules)** | **MIGRATE — highest priority** *(changed)* | S for the CI step, M for the first tests |
| 3 | DI | **MIGRATE** — the target includes `FlipperOneClient()` | M |
| 8 | Errors | **MIGRATE** — bare catches on paths with unresolved state | M |
| 13 | Lint | **MIGRATE** — a ratchet, not a plugin | S |
| 1, 6, 7, 10, 12 | Structure, transport, device files, platform, dependencies | **KEEP** | — |
| 2, 4, 5, 9 | State, routing, layers, serialization | **NOT WORTH IT** | — |

Outside the table: there is no `CONTRIBUTING.md`, and one outside commit out of
~850.
