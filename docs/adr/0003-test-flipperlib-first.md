# 0003. flipperlib is tested before it is changed

Status: Accepted (2026-09-24)

## Context

The architecture review counted tests in `test/` and concluded the project was
well covered: 691 tests, 51 files, against a reference project with 4.

That count was wrong in scope. `flipperlib` and `dartufbt` are git submodules,
but they belong to the same organisation — changes to them are ordinary work,
not somebody else's repository. Counting everything the organisation owns:

| Part | `.dart` files | Test files |
|---|---|---|
| app (`lib/` without `modules/`) | 324 | 51 |
| `flipperlib` | 96 | **0** |
| `dartufbt` | 31 | 1 |

`flipperlib`'s CI runs `dart format --set-exit-if-changed` and
`flutter analyze`. It has **no `flutter test` step at all**.

What is uncovered is not peripheral. It is the priority queue
(`interleavable`, `holdsTxUntilAnswer`, `seq`), auto-reconnect with
`reconnectSettle`, the file transfer that restarts after a session is
restored, the two transports with per-platform implementations, and DFU.

This inverts the cost-versus-risk reasoning used elsewhere in the review.
Several verdicts rested on "rewriting the layer reconnect runs through is
dangerous because a regression would not be caught" — and that is literally
true, not rhetorically.

## Decision

**Add a `flutter test` step to `flipperlib`'s CI, and cover the queue and
`classifyConnectError` first.**

Those two are chosen deliberately: both are pure functions over data. They
need no device, no BLE stack and no transport mock. `FakeFlipperClient` in
`test/firmware_fixture.dart` already demonstrates the seam exists.

This is also the gate that unblocks [0001](0001-state-management.md).

It was the stated precondition for the API migration in issue #144 as well.
That migration landed first, in #127, through `client.dart` and `session.dart`
with nothing underneath it — which is the argument for this ADR rather than
against it.

The goal is **not** "cover 96 files". It is to stop the two most intricate
pieces of logic in the product from being unverifiable.

## Rejected alternatives (and why)

**Cover `flipperlib` broadly before changing anything.** 96 files of
transport and platform code, much of it needing a real device. It would not
finish, and an unfinishable precondition is the same as no precondition.

**Test it from the app instead.** The app's suite exercises `flipperlib`
incidentally through firmware and archive tests, but it cannot reach the queue
ordering rules or the reconnect state machine, and a failure there surfaces as
a confusing app-level failure rather than a named one.

**Leave it and rely on review.** Three review rounds on PR #140 found two
critical defects that came from the *interaction* of two separately correct
mechanisms. Neither was visible by reading; both were caught by mutation runs.
`flipperlib` has nothing equivalent.

## Consequences

- A CI step is cost S and locks the result in — once it exists, a future test
  cannot silently stop running.
- The first tests are cost M and land in a repository that has never had any,
  so the test harness itself has to be set up.
- [0001](0001-state-management.md) depends on this.
- Work happens in `DarkFlippers/dart-flipperlib` and arrives here as a
  submodule bump.

## Migration: what happens to legacy code

No existing code changes. This ADR adds tests and a CI step; it does not
refactor what it covers. If a test cannot be written without restructuring the
code under it, that restructuring is a separate change with its own reasoning —
and it should wait until there is at least one test to protect it.
