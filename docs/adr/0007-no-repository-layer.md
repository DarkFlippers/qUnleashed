# 0007. No repository layer; the boundary is "no I/O in build"

Status: Accepted (2026-09-24)

## Context

There are no formal layer boundaries. `package:flipperlib` is imported by 37
files under `lib/pages/`, 5 of them inside a `widgets/` directory. Both the
reference project and Flutter's official guide say a View does not talk to the
transport, so introducing View → ViewModel → Repository → Service looked like
the highest-value change available.

An independent reviewer argued against it, and the argument held:

- **`flipperlib` is not an internal layer.** It is a separate repository with
  a designed public facade (`client/api/{storage,system,gui,gpio,app,ble}.dart`).
  37 imports are 37 imports of a dependency. Nobody proposes wrapping `http`
  or `flutter_map` in a per-feature repository.
- **Many of the 37 pull it in only for a type.**
  `firmware_changelog_page.dart` has exactly one use: `final FlipperClient
  client;`, a constructor parameter its parent supplies. That is already
  correct injection. Removing the import would mean a parallel domain type and
  a mapping — more code, no behaviour change.
- **It conflicts with [0002](0002-dependencies-are-passed-in.md).** A
  repository written in this codebase's idiom is a new singleton;
  `FirmwareRepository` is `extends ChangeNotifier` plus
  `static final instance`. Adding repositories means adding globals while
  another ADR is removing them.
- **A half-finished migration is worse than either end.** It leaves three ways
  to reach the device inside one feature — the new repository, the existing
  controller, and `FlipperOneClient()`. Freshness and cache state then have two
  owners, and #136 is exactly that defect: `FirmwareCard` called
  `ensureDirectory` from `didUpdateWidget` while `DeviceScope` rebuilt on a
  five-second battery poll, producing 12 requests a minute forever against a
  server that was not answering.

The important detail about #136 is that it was fixed with a listener and a
guard, **not** with a new layer.

## Decision

**Do not introduce a repository layer.**

Instead, draw the boundary where the actual defect lives: **no I/O in `build`
or `didUpdateWidget`.** That is the rule #136 would have been caught by.

A repository is introduced only where two callers already share a cache —
which is what `lib/pages/devices/firmware/repository.dart` does today, and why
it exists. That file is the precedent, not a template to replicate per feature.

A cheaper alternative to the same goal remains open: stop `flipperlib`
exposing a global factory as the only way to obtain a client
([0002](0002-dependencies-are-passed-in.md)). Then those 24 call sites become
a visible dependency with no new layer in the app at all.

## Rejected alternatives (and why)

**Full View → ViewModel → Repository → Service.** Cost L, over a layer with
no tests under it ([0003](0003-test-flipperlib-first.md)), and it contradicts
[0002](0002-dependencies-are-passed-in.md) by adding singletons.

**A repository per feature, gradually.** This is the half-finished state that
gives three owners of the cache. "Gradually" does not make it safer; it makes
the dangerous state the normal one for a long time.

**Ban the imports by lint.** Covered and rejected in
[0004](0004-ratchet-not-lint.md): the rule cannot be written with the current
tooling, and it would flag correct constructor injection while missing the one
real smell.

## Consequences

- The UI keeps importing `flipperlib` directly, and that is a documented
  choice rather than an accident.
- One concrete rule replaces a layer: no I/O in `build`/`didUpdateWidget`.
  It is narrow enough to check in review and would have caught the real bug.
- The "five files in `widgets/`" number stops being a target. Two of them are
  correct code; the rest are addressed by
  [0002](0002-dependencies-are-passed-in.md), which measures the right thing.

## Migration: what happens to legacy code

Nothing is wrapped. `FirmwareRepository` stays as the one place where a
repository was earned. New features do not get one by default.
