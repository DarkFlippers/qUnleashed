# 0002. Dependencies are passed in, not reached for

Status: Accepted (2026-09-24)

## Context

There is no DI container. Dependencies arrive three ways: 28 hand-rolled
singletons of the form `static final X instance`, the `FlipperOneClient()`
factory singleton with **24 call sites** in `lib/` outside the modules, and
`InheritedNotifier` (`DeviceScope`, `cardlist.dart`).

Both benchmarks disagree with this. The reference project uses Riverpod
providers; Flutter's own case study uses `package:provider`. Both pass
dependencies in rather than reaching into global state.

The cost is already being paid, and it shows up in tests rather than in
production. `test/firmware_fixture.dart` has a `resetFirmwareState()` that
manually resets **seven** process-wide singletons between tests, and its own
doc comment records what happened before it existed — including a test that
passed vacuously because `setThemeMode` early-returns on an unchanged mode.
Issue #139 is the same family.

An independent reviewer made two corrections worth keeping:

- The metric "28 singletons" does not cover the two *known* breakages. In
  `flibler_project_test.dart` the culprit is `SharedPreferences.getInstance()`
  — and that test already injects its controller. In
  `logging_history_test.dart` it is `FlutterError.onError`. So counting
  `static final instance` declarations measures the wrong thing.
- 27 of the 28 have a private constructor, so a second instance is impossible
  by construction, and injection gives that up.

The second point is true but weaker than it sounds: a private constructor
guards against an *accidental* second instance, not against the thing
injection is for, which is handing a test a different one.

## Decision

**New code takes its dependencies as parameters.** Existing singletons are
left alone.

The target is not the count of singletons but **process state that leaks
between tests**. A change earns its place here if it removes something
`resetFirmwareState()` has to reset by hand.

Two specific pieces follow:

- `FlipperOneClient()` gets a seam in `flipperlib`, where the factory is
  declared. This is possible — the submodule belongs to the same organisation.
  It is the global almost every feature reaches for, so it is the highest-value
  single target.
- The composition root is `_initCore` in `lib/main.dart`. Anything assembled
  there exists on **both** entry points.

That last point is a constraint, not a detail. `widgetMain()` is a headless
isolate started by a home-screen widget; the graph assembled in `_runApp` does
not exist there. A dependency wired in the wrong place breaks a path that is
never run locally and is not covered by CI.

## Rejected alternatives (and why)

**A DI container (`get_it`, or Riverpod's providers).** Riverpod is deferred
behind [0001](0001-state-management.md)'s gate; `get_it` would add a package
for a problem constructor parameters already solve, in a project that is
otherwise plain Flutter.

**Migrate all 28 singletons.** Cost L, and the benefit is asymmetric: the pain
appears in tests, and tests are written for new code. Converting old singletons
buys little and touches everything.

**Count singletons as the metric.** Rejected per the reviewer's correction —
it tracks neither known failure.

## Consequences

- A contributor writing a new class passes what it needs in. No framework to
  learn.
- Two idioms coexist for a long time, and that is accepted. `FirmwareCard`
  already takes controllers from both `DeviceScope` and singletons.
- `resetFirmwareState()` is the scoreboard: it should shrink over time, and
  growing is a signal.
- Changing `flipperlib`'s factory is a cross-repository change and needs a PR
  there first.

## Migration: what happens to legacy code

Nothing is converted on its own schedule. A singleton is replaced only when a
change is already touching that code for another reason, and the test it
enables is written in the same change. See
[0004](0004-ratchet-not-lint.md) for how new direct reaches are caught.
