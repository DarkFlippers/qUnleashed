# 0006. A registry across features, Navigator within one

Status: Accepted (2026-09-24)

## Context

There is no routing package and no named routes. Two mechanisms coexist:

1. A hand-rolled registry — `enum AppRoute` (10 values), `registerRoute()`,
   `openRoute()`, typed argument classes. `lib/app/routes.dart` is the only
   place that knows about every feature page at once, and it runs from
   `_initCore` before `runApp`.
2. Direct `Navigator.push` inside a feature — 16 call sites, 25
   `MaterialPageRoute`.

That looked like drift worth removing, either by adopting `go_router` or by
routing all 16 through the registry. Both were examined and both were wrong.

**`go_router` wins where there are URLs and deep links.** In this project
`app_links` / `uni_links` / `deepLink` have **0 matches**, `web/` is excluded
from analysis in `analysis_options.yaml` and is not built in CI, and there are
10 routes already collected in one file.

**Routing the 16 through the registry would make things worse**, for reasons
that only show up when the call sites are read:

- `openRoute` takes `Object? args` and the registration casts at runtime
  (`args as PixelEditorArgs`). The 16 pushes are direct constructor calls,
  checked by the compiler. Converting trades a compile-time check for a
  runtime one.
- Half of them carry a **live controller** — `AppDetailPage(controller: _ctrl)`,
  `CategoryPage`, `IrLibFilePage`, `HomeWidgetPickerPage`. `registerAppRoutes()`
  runs before `runApp` and has no access to one. Making it work would mean
  making those controllers global, which contradicts
  [0002](0002-dependencies-are-passed-in.md).
- Others pass callbacks and read a result, need `fullscreenDialog: true`
  (which `openRoute` cannot express), or re-wrap `DeviceScope` for the pushed
  subtree.
- The split is documented as deliberate in both files: a feature never imports
  a sibling feature. That is a boundary, not an inconsistency.

## Decision

**Keep both mechanisms, with the boundary as it stands.** The registry is for
navigation *between* features. `Navigator` is for navigation *within* one.

Fix the one real defect found: `FlipperMapPage` is reachable through two doors
— `AppRoute.archiveMap` (registered with no arguments) and directly from
`key_actions_sheet.dart` with `focusPinPath` and `pickLocationFor`. Teach
`AppRoute.archiveMap` its arguments so both entrances carry the same
information.

## Rejected alternatives (and why)

**`go_router`.** Cost M for a capability the project does not use. Revisit
only if deep links or the web target become real.

**Route everything through the registry.** Trades a compiler check for a
runtime cast, needs global controllers, cannot express `fullscreenDialog`, and
turns `routes.dart` into an import hub for ~14 more files — more coupling, not
less.

**Named routes.** Same runtime-string weakness as above, with no benefit here.

## Consequences

- Two mechanisms stay, and that is now a documented rule rather than something
  a reader has to guess at.
- A new screen inside a feature is a plain `Navigator.push`; a screen another
  feature opens goes in `AppRoute`.
- The registry keeps its single failure mode: an unregistered route throws
  `StateError` at the moment it is opened, which is a runtime failure a test
  may not cover. That is the price of the indirection and it applies to 10
  routes, not 26.

## Migration: what happens to legacy code

Nothing moves. The 16 in-feature pushes are correct as they are.
