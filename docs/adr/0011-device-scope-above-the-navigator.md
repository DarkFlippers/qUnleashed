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

The **nine** reads that kept `of` after this change were not all live-state
readers, and the census budget said which was which. **Four wanted the
dependency**: they read live state in a `build` — `app/shell.dart`, two in
`pages/devices/page.dart`, and `firmware_update_button.dart`'s `dfuPresent`.
**Five did not**: they were callbacks, where a dependency is standing and
useless. Four of those were action calls through the controller —
`synchronize()`, `playAlert()`, `buildExportDump()`, `setRecovering()` — and
the fifth, `_openFullInfo`, took one snapshot of `info` to populate a sheet.

So the accessor pair was one short. There are three needs here, not two: the
client with no dependency, live state read in a `build`, and **the controller
object for a callback or a `Listenable`-taking widget, which wants no
dependency either**.

A third accessor for that was **deliberately not taken in this change**: a
non-listening controller read is the staleness bug `clientOf`'s return type
exists to prevent, so its mitigation would have to be a name and a ratchet
rather than a type, and that wanted deciding on its own rather than as a line
here. The answer came the next day, and is the addendum below; the figures in
this paragraph are what `lib/` held before it.

## Addendum: the third accessor (2026-10-26, #407)

`notifierOf` landed, and the split across `lib/` is now 30 `clientOf`, 6
`notifierOf`, 3 `of`.

```dart
static DeviceController notifierOf(BuildContext context) =>
    context.getInheritedWidgetOfExactType<DeviceScope>()!.notifier!;
```

**It is the accessor with nothing to hide behind,** and that is the whole of
the decision. `clientOf`'s return type narrows the surface — `info`,
`dfuPresent`, `connectionState` and `deviceLoading` are not reachable on a
client, while `isConnected` and `deviceInfoCache` are, which the addendum above
is careful to say. `notifierOf` narrows nothing: it hands back the controller
and with it every read that one keeps out of reach. What stands in for the
type is the name, its doc comment, and two rules in
`test/device_scope_listen_test.dart` — a guard at zero on live state read off
the result, and a census of every call, so each site is declared and says what
it does with the controller.

The guard is syntactic, so it sees `notifierOf(c).info` and not a controller
taken into a local first. `pages/devices/page.dart`'s `_openFullInfo` sits in
exactly that hole: it reads `info` once, through a local, to fill a sheet that
is then pushed and static. What covers it is its census budget line, not the
guard — which is the same division of labour that found the `firmware_card.dart`
site in #344, and the reason the censuses exist beside the guards rather than
instead of them.

### What it was for

`app/shell.dart` was the site that paid. Its read was `of`, in `build`, so the
shell's own element was a dependent and **the `ListenableBuilder` beneath that
read narrowed nothing** — the thing it was meant to protect was being rebuilt
from above it. The other half was that the `IndexedStack` holding every
mounted tab was constructed *inside* that builder, so even a rebuild starting
at the builder produced a new instance and re-ran every page's `build`. It is
passed through `ListenableBuilder.child` now, and `Element.updateChild` skips
a child whose widget is the identical instance.

The sharp edge is the wide layout: `FlipperRootScaffold.build` ignores
`deviceLabel` entirely when `isWide`, so on a desktop window the poll was
rebuilding the whole app for a value nothing displayed.

`test/shell_rebuild_test.dart` holds both halves. It drives
`DeviceController.setRecovering` rather than a connection event, because both
controllers listen to `connectionStream` — the archive controller notifies on
every event, the device controller on every event that is not `connecting` —
so a connection event is the one notification a rebuild witness cannot
attribute to a source.

At the time this was written the archive side of that was a `setState` in
`_AppShellState` that did not ask what changed — a second path to the same
waste, filed as #410 rather than fixed here, with the note that which of the
two cost more was not measured. It was fixed next; see below.

## Addendum: the builder takes a status, not a controller (2026-10-26, #410)

Not a decision about `DeviceScope`, but it changes the widget the two addenda
above describe, so the description would otherwise go stale.

#410 supposed the shell read no *value* off the archive controller, in which
case its listener could simply go. It reads one: `_deviceLabel` consults
`ArchiveController.syncStatus` for the `connected` case. Dropping the
notification would have stopped the bottom bar following a sync — **lagging,
not freezing**, because the device controller is in the same merge and
notifies on every five-second info tick, so the label is recomputed within
about five seconds anyway, longer across the ticks a sync's own `storageBusy`
makes the watcher skip. What the subscription buys is the label moving when
the sync does.

**The rate question the paragraph above left open is answered the other way
round.** The archive controller notifies from forty-one places, and
`_downloadPending` reaches four of them per file it downloads — the `checking`
tick, `publish(0)`, `publish(1.0)` and the completion tick, three of them past
the throttle, which only guards `0 < p < 1` — plus one throttled progress
notification per 150 ms of transfer. So the archive was the larger of the two
sources, not the poll.

### Why the subscription is on one enum and not on the controller

The first fix moved the listener off `_AppShellState`, where its `setState`
re-ran `build` and constructed a new `IndexedStack`, onto the
`ListenableBuilder` that already held the device's — `Listenable.merge([device,
_archiveController])`. That stopped the pages rebuilding, which is what #410
asked for, and left the nav bar being rebuilt by all forty-one notify sites
for one enum it reads.

`syncStatus` has **exactly one reader in `lib/`**, so the narrower fix was
available and is the one taken. `ArchiveController` holds it in a
`ValueNotifier` and exposes it as a `ValueListenable`; the shell merges that:

```dart
final repaint = Listenable.merge([device, _archiveController.syncStatus]);
```

Every assignment inside the controller still writes `_syncStatus`, now a
private getter/setter pair over the notifier's value, so the sites read as
plain field writes and the `notifyListeners()` beside each of them is
untouched — the archive tables depend on those and on nothing here. A
`ValueNotifier` only notifies on `!=`, and the status moves idle → syncing →
synced once per sync, so the nav bar is rebuilt **two or three times a sync**
rather than four times per file downloaded plus a progress tick every 150 ms.
On a two-thousand-file sync that is three rebuilds where there were about
eight thousand.

### Merged in `build`, not held in a field

The archive tables do it the other way (`_repaint` in `category_page.dart`).
The resubscribe cost is per `State.build` and not per notification — a
notification rebuilds only the builder closure, on the same widget instance,
so there is no `didUpdateWidget` and no resubscribe — and a table's own
search, filter, sort and selection `setState`s run its `build` often. The
shell's runs on a tab tap, any `MediaQuery` size change, a theme or locale
change, a permission re-read or a diagnostics change, the last two because it
depends on `PermissionScope` through `_bluetoothBlocks` and on
`DiagnosticsScope` through the post-frame read in `initState`. None of those
is a transport notification, which is the property the choice rests on.

A field would also have to capture whatever `notifierOf` returned. That
invariant does hold and is recorded on `DeviceScope.clientOf` — one controller
for the run, `late final` in the only state that builds a `DeviceScope` — so
this is a preference for the spelling with no captured lifetime rather than a
claim that the field would be wrong.

**What is not pinned:** nothing asserts that `deviceLabel` follows
`syncStatus`, so the merge's own justification is untested, and narrowing the
subscription made the mutation that drops it from the merge *easier* to miss.
The reason, and the three surviving mutations, are in the note at the foot of
`test/shell_rebuild_test.dart` — it needs a connected `FakeFlipperClient` with
a storage API, the same fixture #407 wanted for `_openFullInfo`. Filed.
