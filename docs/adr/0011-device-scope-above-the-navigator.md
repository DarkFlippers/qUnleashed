# 0011. The device scope sits above the Navigator

Status: Accepted (2026-09-25)

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
goes in the same change, so the pattern is not copied from it later.

**`wrapWithDevice` in `test/firmware_fixture.dart` has to move with it.** It
wrapped `home`, which is the shape being abandoned - so every case that opens
a route would have gone on testing a tree the app no longer has. It provides
through `builder` now, for the same reason the app does.

**`QUnleashedApp` disposes only a controller it built.** The optional
`device` parameter is a test seam, and a caller that supplies one owns it;
disposing it here tore down a fixture the test was still holding, and the
failure landed in a teardown rather than in a body.

**`QPageAppBar`'s client parameter can become required**, and `components`
stops being the area that could not move. That is the payoff, and it is a
follow-up rather than part of this change.

## Migration: what happens to legacy code

Nothing below changes. `DeviceScope.of(context)` has 11 call sites across 4
files and keeps working; what changes is that it also works in the 25 places
it currently would not. The widgets that took a client parameter in #151-#154
keep it — a parameter is still the clearer contract for a leaf widget, and
this only means the page above it has something to pass.

## Addendum: a second accessor (2026-10-25, #344)

This decision weighed **reach** — which widgets can see the scope — and not
**rebuild scope**, which is what the 11 call sites above grew into: 39, of
which **30 wanted nothing but `.client`**.

That is not a misuse of `of`. It is the only accessor this ADR left, and a
listening read was the only way to ask. The cost is that `.client` cannot
change — `DeviceController._client` is `final`, and the controller is
`late final` in the one state that builds the scope — so 30 readers were
subscribed to a notifier that had nothing to tell them, while
`device_info_watch.dart` polls every five seconds and the controller notifies
on any non-empty patch without comparing it.

**The read's position mattered less than it looked.** Thirteen of the 30 read
it inside a `build`, and twelve of those put the dependency on the page's own
element and so dragged the page body along. But nothing clears
`Element._dependencies` on a rebuild — only `activate`, `_ensureDeactivated`
and `unmount` touch it — so a listening read from a gesture callback is a
standing subscription too, for the element's whole life. That is what made
`firmware_card.dart`'s changelog push the sharpest of the 30 rather than the
mildest: it is a callback, it reached the client through a local (which is why
the first sweep missed it), and one tap subscribed the device screen's
heaviest card to the poll until the screen went away.

#339 is this defect as a crash rather than as cycles — one of the two tickers
that reached that page's body, the five-second one.

So there are two accessors now:

```dart
static DeviceController of(BuildContext context);   // live state
static FlipperClient clientOf(BuildContext context); // no dependency
```

`clientOf` is an option this ADR never considered, and it is not in tension
with the migration note above. `QPageAppBar` keeps its required `client`
parameter; only how the page obtains the value changes. The alternative —
passing the client down from every page — is still the one #154 declined, for
the reason given there. Nor is a *second scope* carrying only the client
worth it: it would make the wrong read unwritable, but at the price of an
invariant nothing can check (that its client is the controller's) and of
exactly the second ambient scope this ADR argued down to one.

**Returning the client rather than the controller narrows what a
non-listening read can reach**, which is why the accessor has that return
type. `info`, `dfuPresent`, `connectionState` and `deviceLoading` live on the
controller, and a non-listening read of any of them in a `build` would be a
silent staleness bug.

It does not close the door, and saying it did would be the easy over-claim:
`FlipperClient` has its own `isConnected` and `deviceInfoCache`, so
`clientOf(context).isConnected` compiles and is that bug. What the type buys
is that the obvious stale reads are out of reach and the two that remain sit
on an object whose own streams are the right answer — `connectionStream` and
`deviceInfoUpdates`, which is what `QPageAppBar` already does.

`test/device_scope_listen_test.dart` holds the rest as a ratchet: the
client-only listening reads at zero, and a per-area census of every listening
read, because the zero-budget rule cannot see a controller taken into a local
and that census can.

The **nine** reads that keep `of` are not all live-state readers, and the
census budget says which is which. **Four want the dependency**: they read
live state in a `build` — `app/shell.dart`, two in `pages/devices/page.dart`,
and `firmware_update_button.dart`'s `dfuPresent`. **Five do not**: they are
callbacks, where a dependency is standing and useless. Four of those are
action calls through the controller — `synchronize()`, `playAlert()`,
`buildExportDump()`, `setRecovering()` — and the fifth, `_openFullInfo`, reads
`info` once to populate a sheet.

So the accessor pair is one short. There are three needs here, not two: the
client with no dependency, live state read in a `build`, and **the controller
object for a callback or a `Listenable`-taking widget, which wants no
dependency either**. A `notifierOf` is the obvious next step and deliberately
not taken here, because a non-listening controller read is the staleness bug
`clientOf`'s return type exists to prevent — the mitigation would have to be
the name and the census rather than the type, and that wants its own decision
rather than a line in this addendum. `app/shell.dart:207` is the site where it
would pay: the listening read there is in `build`, so the `ListenableBuilder`
below it narrows nothing, and the app's root scaffold rebuilds whole on every
poll tick.
