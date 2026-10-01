# 0008. A swallowed error is a defect where the UI is left unresolved

Status: Accepted (2026-09-24); the named defects are closed (2026-10-01)

## Context

There are no result types — 0 matches for `class Result`, `sealed class …Result`
or `Either<`. Errors are exceptions: 378 `catch`, of which 23 are typed, and
**49 empty `catch (_) {}`** (42 in the app, 7 in `flipperlib`, four of those
inside an isolate).

The obvious move — remove all 49 — was examined and mostly rejected. A reviewer
read them: most are deliberate best-effort where swallowing is correct. `mkdir`
of a directory that may already exist (`installer.dart:410`,
`install_engine.dart:538-547`), temporary-file cleanup in `finally`
(`atp_source.dart:429`), writing a cache if it works out (six in
`services/archive/storage.dart`), probing `jsonDecode`. Typed failures there
would be noise.

But a subset is a real, expensive defect, and the repository already records
what it costs:

- **#118 / #134** — three firmware surfaces latched forever, each behind a
  catch that recorded nothing in any build. The UI read "Checking…" until the
  app was restarted.
- **#138** — a bare `catch (_) {}` wrapped around a whole loop in
  `manifest_registry.dart`, so one bad entry loses every installed app,
  partially and silently, with nothing logged at any level.
- **`test/log_level_budget_test.dart`** names a third hazard in its own
  comment: a bare catch **games the existing ratchet**, because deleting a
  counted `LogService.info` lowers the number. "The cheapest way to go green is
  to make the code worse."

A second proposal — model failures as sealed hierarchies, as the reference
project does — was withdrawn. The most differentiated failure in the app
already has an answer: `classifyConnectError` → `FlipperConnectErrorKind`,
consumed by an exhaustive `switch`. A sealed type is impossible there in
principle: the classifier matches substrings from platform BLE errors
(`'peer removed pairing'`, `'connectionlimitexceeded'`), and a
`PlatformException` from Android GATT cannot be made a member of a hierarchy
declared here. Classify at the boundary, then switch — that is the right idiom
for this domain, not a stopgap.

## Decision

**Target bare catches on paths where the UI is left in an unresolved state**,
not the count of them.

The shape to look for is #118's: an operation the UI is waiting on fails, the
catch records nothing, and the screen keeps showing a state that will never
change. That subset is a defect regardless of how many others exist.

Extend the AST ratchet in `test/log_level_budget_test.dart` to count bare
catches, so lowering the logging number by deleting a log stops being
profitable. That is what #117 asks for.

Sealed exception hierarchies are **not** adopted. Where a failure needs
differentiated UI, classify it at the boundary into an enum and switch
exhaustively.

## What the sweep found (2026-10-01)

Every defect this ADR names is fixed, and the two issues that carried the
rest - #110 and #120 - are closed.

| | At this ADR | Now |
|---|---|---|
| Bare `catch (_) {}` in the app's `lib/` | 42 | **24** |
| `LogService.info` inside a `catch` | 117 | **49** |
| Tests on `classifyConnectError` | 0 | **19** in flipperlib, 14 here |

Both numbers are ratchets with a per-area budget, and every site left is named
in the budget map with the reason it earns its place. The ratchet on bare
catches is the one the Decision above asked for; it has since caught the thing
it was built for, when a slice lowered two logs to `info` on the argument that
the surface now worked.

**The fix was almost never a new exception type.** Of the defects closed under
this ADR, the shape that recurred was the one [0001](0001-state-management.md)
already prescribed: the UI needed an explicit failed state, and the failure
needed to carry its cause to that state. `FirmwareFetchState` (#134),
`AtpSource.failed`, `ManifestRegistry.failed`, `UpdateRegistry.failed` (#112),
`ArchiveController.lastFailure` (#192, #110) and `LinkService`'s
`autoConnectFailure` (#120) are all that, and none of them is a type for the
error. This ADR and 0001 turned out to be the same instruction read from two
ends, which is why 0001's gate could be answered without Riverpod.

**One field per operation, with a lifetime that outlives the refresh.** The
recurring bug underneath #110 was not a missing catch but a shared field: the
page read `error` after an `await refresh()` that had just nulled it, so the
message rendered with an empty slot. The answer that worked is a second field
cleared at the *start* of each operation rather than at the end, read at the
boundary where the operation finishes.

**Classify at the boundary held, and was extended rather than replaced.**
`FlipperConnectErrorKind` gained `sessionLimit` for this library's own cap on
held links (dart-flipperlib#9), which had been falling through to `unknown`
since the cap existed. A sealed hierarchy would not have helped: that one is
thrown here, but the six around it still come from platform BLE stacks as
substrings.

**What is left is not this ADR's subject.** #103 counts 49 `LogService.info`
calls inside a catch. Every one of them is named, and this ADR's Decision says
in as many words that the count was never the problem - a site whose UI
resolves and whose cause reaches a surface is allowed to keep a quiet log
line. #103 stays open as the record of where they are, not as a debt against
this decision.

## Rejected alternatives (and why)

**Remove all 49.** Most are correct. A 49-file diff with low information
density is hard to review and would replace deliberate best-effort with noise.

**Sealed hierarchies for failures.** Impossible at the boundary that matters
(platform exceptions), and the existing classifier is better suited.

**Result types throughout.** Cost L and fights every other line in the
codebase, which is exception-based end to end.

**Count bare catches as the goal.** The number went 43 → 42 over several days;
it is not growing, and the count was never the problem. The location is.

## Consequences

- Reviews get a specific question — "if this fails, what does the user see?" —
  instead of a style rule.
- The ratchet stops being gameable in one direction, which matters because its
  own comment predicted that hole.
- 24 bare catches stay in the tree, deliberately, and this ADR is why. The
  sweep is finished: every area has been read through once, and every catch
  that is left is named in `kBudget` in `test/bare_catch_budget_test.dart`
  with the reason it earns its place — a `mkdir` of a folder that already
  exists, a temp file removed in a `finally`, a cache entry that is fetched
  again when it is missing, a retry that has not given up yet. The 18 that
  went were the other kind: a screen that kept saying something no longer
  true, and nothing anywhere recording why.
- `classifyConnectError` becomes the named pattern for differentiated failures,
  and it needs tests — it is one of the two modules named in
  [0003](0003-test-flipperlib-first.md). It has them: 19 in flipperlib, and 14
  here over the strings each kind is shown as, which is the half that had none
  and where a kind had been falling through unnoticed.

## Migration: what happens to legacy code

The best-effort catches stay. A bare catch is only converted when it sits on a
path where the UI waits — and then the fix is an explicit failed state
([0001](0001-state-management.md)), not a new exception type.
