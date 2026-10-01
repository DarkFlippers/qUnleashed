# 0002. Dependencies are passed in, not reached for

Status: Accepted (2026-09-24); the client sites are down to their roots
(2026-10-01)

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

## Where the 24 went (2026-10-01)

Six are left, and every one of them is a site this ADR already excludes:

| Area | Site | Why it stays |
|---|---|---|
| `app` | `bootstrap.dart` | Composition root. |
| `main.dart` | `_initCore` | Composition root - the one both entry points share. |
| `pages/apps` | `apps_backend.dart` | Existing singleton, left alone by the Decision above. |
| `pages/flibler` | `project/controller.dart` | Fallback behind `FliblerProjectController.instance`. |
| `pages/tools` | `paint/virtual_display_session.dart` | Two pages share one session; `forTest` is its seam. |
| `services` | `link_service.dart` | Fallback until `bootstrapAmbientServices` has handed it one. |

What moved the other eighteen was not the seam this ADR named. It was
[0011](0011-device-scope-above-the-navigator.md): with `DeviceScope` above the
Navigator, every route builder and every pushed page has a client in its
context, so a `client ?? FlipperOneClient().get()` default had a caller that
could supply one. The parameters were in most cases already there - the
defaults behind them were the whole reach. Making them required is what turns
the ratchet from a number into a rule the compiler keeps.

**The seam in `flipperlib` was not needed for any of this, and is still the
only way the last four go.** Each of them is a singleton or a fallback for
one, and a singleton cannot be handed a client by a caller that does not build
it.

One thing the count does not say, and it is the ratchet's own caveat: a site
removed by threading a client through six constructors and a site removed by
making the widget stop touching the device both lower it by one, and only the
second is what this ADR is after.
[`test/client_reach_budget_test.dart`](../../test/client_reach_budget_test.dart)
records that in its header. Of the eighteen, `widgets/firmware_card.dart` was
the second kind; the rest were the first. What they bought is narrower than
the number looks: eighteen classes now say in their signature that they need a
device, and can be built in a test with a fake.

The metric this ADR originally named - what `resetFirmwareState()` resets by
hand - is not the one being read here.
[0012](0012-the-di-scoreboard-is-the-ratchet.md) replaced it with the ratchet,
for reasons that this slice is another instance of.

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
