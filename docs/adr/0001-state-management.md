# 0001. ChangeNotifier now, Riverpod behind a coverage gate

Status: Accepted (2026-09-24)

## Context

The app has no state-management package. State lives in 29 `ChangeNotifier`
classes, 56 files calling `setState`, and a handful of `ValueNotifier` and
`InheritedNotifier`. `StreamBuilder` is never used, even though the transport
exposes a `Stream`.

Two bugs already filed are the same shape, and both come from a missing state
rather than a wrong one:

- **#112** — the apps layer has no failed state, so every failure renders as
  "nothing to show". Nine of sixteen sites ended in that same sentence.
- **#118** — three firmware surfaces latched a loading state forever, because
  "failed" did not exist as a distinct state.

Riverpod's `AsyncValue` models loading, data and error as one sealed type, so
that class of bug becomes unrepresentable. That is the strongest argument for
adopting it, and it is evidence from this repository rather than theory.

Against it: Flutter's official architecture case study is built on
`ChangeNotifier` and `package:provider`, and states that Riverpod, bloc and
signals are equally viable. The guide is explicitly package-agnostic. So the
current choice matches the neutral benchmark; it is the reference project that
deviates, for its own reasons.

The decisive fact is elsewhere. `flipperlib` — the transport, session, RPC
queue, auto-reconnect and DFU — is 96 `.dart` files with **zero tests**, and
its CI has no `flutter test` step. Rewriting the layer that connection state
travels through, over code with nothing underneath it, is how a reconnect
regression reaches a user instead of CI.

## Decision

Keep `ChangeNotifier` for now.

Adopt Riverpod only after all three of these are true:

1. `flipperlib`'s CI has a `flutter test` step.
2. The RPC queue (`session/queue.dart` — `priority`, `seq`, `interleavable`,
   `holdsTxUntilAnswer`) is covered by tests.
3. `classifyConnectError` is covered by tests.

Those two modules were chosen because they are pure functions over data and
test without a device. See [0003](0003-test-flipperlib-first.md).

Meanwhile, take the value that motivated Riverpod without the framework: where
the UI must show a failure, model it as an explicit state rather than an
absence. `FirmwareFetchState` (a three-state enum, added in #134) is the shape
to copy; #112 is the next place it applies.

## Rejected alternatives (and why)

**Adopt Riverpod now.** Cost is L — 29 `ChangeNotifier` classes, 56 `setState`
files and every consumer. It also needs `build_runner`, which the project does
not use anywhere, and Riverpod 3 moved `StateProvider` and
`StateNotifierProvider` into `legacy.dart`, so most material a contributor
finds online is wrong for it. All of that on top of a layer with no tests
under it.

**A vague precondition ("once there is coverage").** Rejected because nobody
could check it. Either it blocks forever — 96 files are never fully covered —
or one test satisfies it and the guarantee is nil. A condition with no shape
is not a condition.

**Do nothing about #112.** Rejected: the state gap is real whether or not
Riverpod ever arrives, and the enum form already works.

## Consequences

- New code keeps using `ChangeNotifier`; nothing to learn for a contributor
  arriving from a plain Flutter project.
- The gate is checkable, so this ADR can be closed by evidence rather than by
  opinion.
- Work on [0003](0003-test-flipperlib-first.md) is now on the critical path
  for this decision as well as for its own sake.
- If the gate is met and Riverpod is still wanted, the risk assessment is a
  different one and this ADR should be superseded rather than amended.

## Migration: what happens to legacy code

Nothing is rewritten. The 29 existing `ChangeNotifier` classes stay as they
are. The only rule that changes is for new work: a UI that can fail gets an
explicit failed state, not an empty list.
