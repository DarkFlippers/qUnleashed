# 0012. The DI scoreboard is the ratchet, not `resetFirmwareState()`

Status: Proposed (2026-09-26)

Amends [0002](0002-dependencies-are-passed-in.md). The decision there stands;
its metric does not.

## Context

[0002](0002-dependencies-are-passed-in.md) says the target of the DI work is
not the count of singletons but **process state that leaks between tests**,
and names its scoreboard:

> `resetFirmwareState()` is the scoreboard: it should shrink over time, and
> growing is a signal.

Eight slices later — #151 to #165, 18 new test files — that number has not
moved. `resetFirmwareState()` reset ten things before the work started and
resets the same ten now. By its own metric, nothing happened.

The ratchet [0004](0004-ratchet-not-lint.md) put on `FlipperOneClient()` says
otherwise:

| Area | Before #151 | Now |
|---|---|---|
| `pages/devices` | 2 | 1 |
| `pages/archive` | 4 | 3 |
| `pages/tools` | 9 | 8 |
| `components` | 2 | 1 |
| `services` | 3 | 1 |
| **Total** | **24** | **18** |

And six widgets and services that could not be tested at all now have tests,
because each slice ended with a seam and the first cases through it.

## Why the metric missed it

**It measures one fixture.** `resetFirmwareState()` belongs to the firmware
suite. A change that makes the infrared viewer or the connection list
testable cannot move it, however much leakage it removes — and three of the
new files carry a reset preamble of their own (`DeviceSettings.reset()`, then
emptying `KnownDevicesStore`) which that number does not see.

**Removing a reach does not remove a reset.** The two are different problems.
`DeviceController` taking a client (#151) removed a reach; the singletons it
still reads are untouched, so the fixture is unchanged. Meanwhile the reset
burden did not shrink, it *spread*: what used to be absent because the code
was untestable is now written out per file.

**A growing reset list can be progress.** #161's fixture resets
`DeviceSettings` per case because a singleton caches its load. That is three
lines of new reset code standing where twelve cases of auto-connect
behaviour had none. Read as the metric asks, that is a regression.

## Decision

**The scoreboard is `test/client_reach_budget_test.dart`.** It counts
`FlipperOneClient()` per area, it fails when a number rises, and it moved six
times while the old metric moved none.

`resetFirmwareState()` stays as what it is — a fixture — and stops being read
as a measure of anything.

## Rejected alternatives (and why)

**Keep the old metric and accept that it is slow to move.** It did not move
slowly; it could not move at all. A metric that cannot register the work
being done against it is not conservative, it is wrong.

**Count reset lines across all of `test/`.** It would fall when a test is
deleted and rise when a hard thing is finally tested, which is backwards in
both directions.

**Count singletons.** Rejected in [0002](0002-dependencies-are-passed-in.md)
for reasons that still hold: it tracks neither known failure.

## Consequences

- One scoreboard instead of two, and it is one CI already enforces.
- The remaining 18 are named in the ratchet's budget map with what kind of
  site each is. Two are composition roots and expected to survive; the rest
  are controllers and one service fallback.
- `resetFirmwareState()`'s own doc still records what happened before it
  existed, which is worth keeping — it is the case for the decision, not a
  measure of its progress.

## Migration: what happens to legacy code

Nothing. This changes what is read, not what is written.
