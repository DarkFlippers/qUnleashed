# 0011. The device scope sits above the Navigator

Status: Proposed (2026-09-25)

## Context

`DeviceScope` is an `InheritedNotifier<DeviceController>` mounted by
`AppShell` (`lib/app/shell.dart:120`), which is `MaterialApp.home` — route
`/` inside the Navigator. A route pushed with `Navigator.push` is a sibling of
that route, not a descendant of the widget that pushed it, so **everything
reached by a push is outside the scope**. There are 25 `MaterialPageRoute`
sites in `lib/`.

This is not theory. `FirmwareCard._openChangelog`
(`lib/pages/devices/widgets/firmware_card.dart:263`) re-provides the scope by
hand inside its route builder, for exactly this reason — it is the only place
that noticed.

The four slices of [0002](0002-dependencies-are-passed-in.md) landed in #151
to #154 each hit this, and three of the four changed shape because of it:

| Widget | Inside the scope? | What it got |
|---|---|---|
| `FirmwareCard` | yes | reads `DeviceScope.of(context).client` |
| `StorageUsageCards` | yes, through the archive tab | a **required** client parameter |
| `IrFileViewer` | no — pushed | a required parameter, from pages that already held a client |
| `QPageAppBar` | mostly not — 16 builders, most pushed | an **optional** parameter, with the global as fallback |

The last row is the cost. `components` is the one area whose ratchet number
did not fall, because a required parameter would have meant handing a client
to sixteen pages so that one subtitle could be tested.

## Decision

**Move `DeviceScope` above the Navigator**, via `MaterialApp.builder`, and
move ownership of `DeviceController` from `AppShell` to the widget that builds
`MaterialApp`.

```dart
// lib/app/app.dart, in a State rather than the current StatelessWidget
MaterialApp(
  ...
  builder: (context, child) => DeviceScope(notifier: _device, child: child!),
  home: const AppShell(),
)
```

`builder` wraps the Navigator, so every route — pushed or not — is a
descendant. `AppShell` stops creating the controller and reads it from the
scope like everything else.

## Rejected alternatives (and why)

**Re-provide the scope at each push**, the way `_openChangelog` does. It is
25 sites, each of which has to remember, and forgetting is silent — the
widget below simply falls back or crashes at `DeviceScope.of`. The one site
that does it today is evidence that the rest did not think about it, not that
the pattern works.

**Pass the client down from every page.** That is what #154 declined, and the
reason is unchanged: sixteen builders threading a parameter through so one
subtitle can be tested is a worse trade than moving one widget.

**A global, which is what exists.** `FlipperOneClient()` is available
everywhere precisely because it ignores the tree. The point of
[0002](0002-dependencies-are-passed-in.md) is to stop reaching for it; making
the tree answer the same question is the alternative that does not need a
global.

## Consequences

**The controller is created earlier and disposed later.** Today `AppShell`
creates it in a field initialiser and disposes it in `dispose()`, where it
also calls `_ctrl.client.disconnectAll()`. Moving ownership up moves both.
Neither is reached in normal operation — `AppShell` is the root route and is
not popped — so this is a change in where the code lives more than in when it
runs. It still has to be moved deliberately, not dropped.

**`widgetMain()` is unaffected.** The headless isolate never calls `runApp`,
so neither `QUnleashedApp` nor `AppShell` exists there today, and neither will
after. It uses `FlipperOneClient().get()` directly, which
[0002](0002-dependencies-are-passed-in.md) names as a composition root and
expects to survive.

**The `MaterialApp` rebuild path needs care.** `QUnleashedApp` rebuilds its
`MaterialApp` on every theme and locale change, through an `AnimatedBuilder`.
The controller must therefore live in `State`, not in `build` — a controller
constructed in `build` would be replaced on every accent-colour change,
taking its subscriptions and its device with it.

**`FirmwareCard._openChangelog`'s manual re-provide becomes redundant** and
should go in the same change, so the pattern is not copied from it later.

**`QPageAppBar`'s client parameter can become required**, and `components`
stops being the area that could not move. That is the payoff, and it is a
follow-up rather than part of this change.

## Migration: what happens to legacy code

Nothing below changes. `DeviceScope.of(context)` has 11 call sites across 4
files and keeps working; what changes is that it also works in the 25 places
it currently would not. The widgets that took a client parameter in #151-#154
keep it — a parameter is still the clearer contract for a leaf widget, and
this only means the page above it has something to pass.
