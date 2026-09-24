# Architecture decision records

One file per decision, with the reasoning that produced it and the
alternatives that were rejected. They came out of the review in
[`../architecture-review.md`](../architecture-review.md), which compares this
codebase against a reference project and the official Flutter guide, and
records an independent reviewer's counter-arguments alongside the replies.

A decision to *not* do something is recorded too. Those are the ones most
likely to be proposed again.

| # | Decision | Verdict in one line |
|---|---|---|
| [0001](0001-state-management.md) | State management | `ChangeNotifier` stays; Riverpod is gated on [0003](0003-test-flipperlib-first.md) |
| [0002](0002-dependencies-are-passed-in.md) | Dependency injection | new code takes dependencies as parameters; existing singletons stay |
| [0003](0003-test-flipperlib-first.md) | Testing `flipperlib` | a `flutter test` step and coverage of the queue and `classifyConnectError` |
| [0004](0004-ratchet-not-lint.md) | Architectural rules | ratchet tests on `analyzer`, not lint plugins |
| [0005](0005-tolerant-decoding.md) | Feed decoding | hand-written and tolerant, with one shared mechanism; no codegen |
| [0006](0006-navigation.md) | Navigation | registry across features, `Navigator` within one; no `go_router` |
| [0007](0007-no-repository-layer.md) | Layers | no repository layer; the rule is no I/O in `build` |
| [0008](0008-swallowed-errors.md) | Swallowed errors | target the paths where the UI is left unresolved, not the count |
| [0009](0009-absence-is-null.md) | Sentinels | absence is `null`; `sha256` becomes `String?`, `timestamp` is deleted |
| [0010](0010-declared-sdk-window.md) | SDK versions | declare the floor CI covers, and accept the reformat it causes |

## Reading order

[0003](0003-test-flipperlib-first.md) first. It is the precondition for
[0001](0001-state-management.md), and the fact behind it —
96 files of transport, session and reconnect with zero tests — is what makes
several of the other verdicts come out the way they do.

## Format

```markdown
# NNNN. <Title>
Status: Accepted (<date>)
## Context
## Decision
## Rejected alternatives (and why)
## Consequences
## Migration: what happens to legacy code
```

A decision that is later reversed gets a new ADR that supersedes the old one.
The old file stays, with its status changed — the reasoning that turned out to
be wrong is worth more than a clean directory.
