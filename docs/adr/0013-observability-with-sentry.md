# 0013. Sentry is the second channel, wired into the chokepoints that exist

Status: Proposed (2026-10-01); breadcrumb source settled, the logging
chokepoints checked against the code, and `caught` added as a third level
(2026-10-02); every claim re-read against the tree (2026-10-07), which moved
the flipperlib pin, the replay mask target, the ratchet arithmetic, the route
count and what is left of #103; **consent reversed to on by default, sent
automatically, behind a one-time notice** (2026-10-07)

Re-verified 2026-10-07 and still true: the 48 and `pages/archive`'s 24 are
exactly what `test/log_level_budget_test.dart` counts — it sits at budget in
every area, with nothing to lower; `sentry_flutter` 9.30.1 is still the latest
on pub.dev and 10.0 has still not shipped stable, so §7 stands unchanged;
`jni` 1.0.0 and `path_provider_android` 2.3.1 are what the lockfile holds;
`enable-swift-package-manager: false` and the `qunleashed_hardnested` pod are
both still there; and both self-extracting launchers work the way §6 and the
Consequences describe.

Build identity — release, channel, commit — is its own decision,
[0014](0014-build-identity.md). This one consumes it.

## Context

The app has one route from "it failed" to a bug report, and it runs through
the user. `LogService` says so in its own doc: errors and warnings are kept in
a bounded history because "there is no second channel: no crash reporting",
and `LogSettingsPage` is "the only route from 'it failed' to something a bug
report can carry". Someone has to notice, open Settings → Log, copy, and paste
into an issue.

Some failures cannot take even that route. The MIFARE recovery (`lib/modules/cpp`,
including the `nfc-tools` submodule), libusb in the DFU path and libserialport
are native code behind `dart:ffi`. A fault there ends the process, and the
history it would have been written to goes with it.

The project is in Sentry's open-source programme, whose quotas (5M errors, 1B
spans, 100K replays, 5 TB logs, at the time of writing) are far above what the
app produces. One SDK, `sentry_flutter`, covers all five shipped platforms:

| | Dart errors | Native crashes | ANR / hangs | Crash-free rate | Replay |
|---|---|---|---|---|---|
| Android | yes | Java + NDK | yes | yes | yes |
| iOS | yes | yes | yes | yes | yes |
| macOS | yes | yes | yes | to verify | no |
| Windows | yes | crashpad | no | no | no |
| Linux | yes | crashpad | no | no | no |

Windows and Linux have no offline cache either: an event raised without a
network is lost.

What constrains the shape more than the SDK does:

- **`_initCore` must never throw**, and it runs on two entry points.
  `SentryFlutter.init` throws `ArgumentError` on a null DSN.
- **The app already funnels failures.** `LogService` keeps every error and
  warning; `guarded()` names every future nobody waits on; the uncaught
  handlers catch what nothing else does; `classifyConnectError` sorts BLE
  failures into kinds. Each of these took a sweep to get right
  ([0008](0008-swallowed-errors.md), #23, #89, #103).
- **Submodules are other repositories** and are not to take a dependency on a
  vendor SDK.
- **What the app handles is sensitive**: card dumps, MIFARE keys and UIDs,
  Sub-GHz captures, GPS, Flipper names, file names, and a map API key inside
  tile URLs. `LogService._redact` exists because a log is pasted into public
  issues.

## Decision

### 1. On by default, sent automatically, with one switch that turns it off

Reversed 2026-10-07. This section first said the opposite — one prompt at
first launch, nothing started before the answer — and the reasoning for the
reversal is below, in Rejected alternatives, because that is where the
on-by-default option was written down and declined.

**Reporting is on from the first launch and sends by itself.** No prompt, no
gate, no action by the user to send anything. Errors and crashes, Sentry Logs,
traces and metrics all go as they happen.

One switch turns it all off: Settings → Diagnostics (the Log row, renamed),
**Share logs with developers**, on by default. Turning it off calls
`Sentry.close()`, which also shuts the native SDK and the handlers; turning it
back on starts it again. One switch and not one per category, because
"performance" and "metrics" as separate controls are a distinction nobody can
act on - the same data in a different shape, neither of them the screen - and
every extra switch is friction that buys no privacy the first one did not.

**Replay is the exception and stays off by default**, a second switch under
the first, Android and iOS only. It is the only category that records the
screen, on an app whose screen shows card dumps and Sub-GHz captures, and the
only one with a cost a user can feel (about +13% CPU and +5% memory on
Android, +6% CPU on iOS). The stores label it separately too. A screen
recorder that starts without being asked is a different decision from a crash
reporter that does, and this ADR only makes the second one.

**A one-time notice on first launch, not a gate.** Shown once at first
launch, and once more for existing users after the update that carries this.
It says what is sent, links the privacy policy, and carries two actions:
**Got it** and **Turn it off**. Reporting is already on while it is on screen
— that is what makes it a notice and not consent — and the second action is
there so that turning it off takes one tap at the moment the user is being
told, rather than a hunt through Settings later.

It does not block. The app is usable behind it and dismissing it is the same
as **Got it**; it is recorded as shown either way, and never appears again.

There is no onboarding flow in the app to hang this on, so it is a one-time
sheet of its own, raised from `_runApp` once the first frame is up. Not from
`_initCore` — that must never throw and has no UI — and not from
`widgetMain()`, which has no window at all: a headless isolate must never be
the path that marks the notice shown, or the user would never see it.

This is also what Play's Data safety declaration and the App Store's privacy
labels need to be true, and it is what makes "on by default" honest rather
than quiet. Under GDPR it is the ordinary shape for diagnostics taken on
legitimate interest: nothing identifying (§6), IP storage off, and objecting
is one tap. The repository has no privacy policy today and needs one before
the first release that carries this; both stores require the URL anyway.

Firebase Test Lab — which Google Play's pre-launch report runs on — never
starts it. This matters more now than it did behind a prompt: nothing has to
tap "yes" for a robot's session to become real events.

The Log screen stays, and so does Copy. It is the route for anyone who turns
sharing off, and the history it shows is the same text Sentry receives. There
is no "send this now" button: sending is not something the user does.

### 2. One folder imports Sentry, and it plugs into what exists

`lib/services/telemetry/` is the only place allowed to import `package:sentry*`
— a ratchet test on `analyzer`, as [0004](0004-ratchet-not-lint.md) prescribes.
The rest of the app keeps calling `LogService`, `guarded` and the classifier
as it does now.

| Chokepoint | What reaches Sentry |
|---|---|
| `_initCore` | Init, after `LogService.initialize()` and the opt-out read, with its own catch. The read is one bool and defaults to on, so a preference store that will not open reports rather than going quiet - the opposite of the consent shape, where a failed read had to mean no. Sentry saves and calls the `FlutterError.onError` and `PlatformDispatcher.onError` it finds, so `LogService`'s handlers going in first keeps both. One init serves `main()` and `widgetMain()`: `promote` reuses the engine. |
| `LogService._emit`, kept entries | Sentry Logs, through a `keptSink` hook in the shape of flipperlib's `Log.sink`. **The first of a run only**: one RPC timeout produces hundreds of identical lines, which is why `_remember` coalesces them. That coalescing is not visible from `_emit` today - `_remember` returns `void` and folds silently - so it has to report whether the line was new. One signature, and the hook reads it rather than comparing bodies a second time. |
| `LogService.caught`, §5 | The same `keptSink`, sent at Sentry's **info** level rather than `warning`. The 48 failures a release build keeps no record of today, §5. |
| `guarded(what, …)` | An issue, fingerprinted on `what` and the error type — the best grouping key the app has. |
| `classifyConnectError` | `unknown` becomes an issue; every other kind is a metric and a breadcrumb. The issue list is then exactly the platform strings the classifier does not know yet. |
| `AppHttp` | Hand-made spans. Nothing instruments `dart:io` `HttpClient`, and the map's tile client is left out: URLs and query strings are always sent, and tile URLs carry the Carto key. |

A `traced(name, ...)` helper in the same folder covers the operations a user
waits on: connect, firmware install, file transfer (counting restarts — an
upload restarts after auto-reconnect), app install, DFU and MIFARE recovery
(duration and attack kind only, never keys or UIDs).

What is **not** an issue: an ordinary `LogService.error`. It carries a string,
not the exception, and many are expected — a timeout, a dropped link. Those
are logs, linked to the trace and the session they happened in.

### 3. Submodules expose hooks; the app owns the adapter

No submodule depends on Sentry. Each says what happened in its own types, and
`lib/services/telemetry/` turns that into Sentry calls.

- **flipperlib.** Errors already reach `LogService` through `Log.sink`; nothing
  changes for them. While reporting is on, `Log.level` is raised to `info` and
  `info` becomes a breadcrumb only, so a crash arrives with "link lost →
  reconnecting → reconnected" in front of it.

  Two things that is, concretely. `attachFlipperlibSink` pins the level to
  `warning` whenever nothing is printing, which is every release build, and
  its doc says why: history gets the transport faults and session failures a
  bug report needs, plus the degraded-but-not-broken class a warning is for,
  and nothing below those. The pin was `error` when this was first written and
  #232 raised it one step, which narrows the gap this closes rather than
  changing its shape: `info` is still unreachable in a release build.
  Reporting raises the pin again, to `info`; it is a change to a recorded
  decision rather than a setting that already allows it, and the pin returns
  to `warning` when reporting is turned off. And the hook belongs in
  `_flipperlibSink`, **before** it calls `_emit` - see the section below for
  why it cannot sit inside `_emit`. Request tracing needs a PR there:
  a `FlipperRpcObserver` constructor parameter on `FlipperClient`, no-op by
  default ([0002](0002-dependencies-are-passed-in.md)), called **synchronously
  inside `callRpcFrames`** at enqueue, send and completion. Synchronously,
  because a span is found through the caller's zone and the queue worker runs
  in another one. `callRpcFramesMulti` is a second door into the same queue -
  it reaches `_requireSessionFor(priority)` directly rather than through
  `callRpcFrames` (`client/client.dart:1342`) - so the observer goes in at the
  session, or in both, or every multi-frame call is untraced.
- **dartufbt.** No change. `UfbtLogger.addSink` gives the app its events:
  `error` and `critical` go to `LogService.error` — today they reach only the
  Assembler console — and progress `started → finished/failed` becomes a span.
- **nfc-tools** (C, flipperdevices). Covered by native crash capture; needs
  its debug information kept on every platform.

Sentry is told `package:flipperlib` and `package:dartufbt` are the app's own
(`addInAppInclude`), or their frames are collapsed as third-party. Code
mappings point each at its own repository.

### 4. Breadcrumbs come from flipperlib only, and `_emit` is not touched

Decided 2026-10-02, after reading what the alternative costs.

The app's `info` is not reachable in a release build, and not merely quiet.
`info` opens with `if (!infoOn) return;`, and `infoOn` is a `const` derived
from `QLOG`, which defaults to `kDebugMode` - so in a release build the guard
is a const false and the call sites shake out of the binary. There is nothing
there to hook.

Making them reachable means making `infoOn` true, and the levels are ordered:
`infoOn` implies `errorOn`, and `printing` *is* `errorOn`. A release build that
could emit app-side breadcrumbs is therefore a release build that prints
everything to the platform log. That is not a trade worth making for
commentary.

Even in a talking build the hook would be awkward in the obvious place.
`_emit` opens with `if (!keep && !console) return;`, which is #187: five
sites out of six are dropped, and each used to buy a timestamp first. A
breadcrumb hook would have to sit above that return and would reinstate the
stamp, plus a scrub, since a breadcrumb is sent and §6 scrubs everything
sent.

flipperlib is the other way round, which is what makes this decision
available at all. Its `Log.level` is a mutable static and `Log.info` checks it
at runtime - only `debug` and `trace` sit behind the `debugBuild` const - so
raising the level in a release build genuinely produces lines, where the same
move on the app's side produces nothing without recompiling it.

So breadcrumbs have one source: **flipperlib, hooked in `_flipperlibSink`
before it calls `_emit`.** `info` from the library becomes a breadcrumb and is
dropped as it is today; `warning` and `error` keep going to `history`, and
reach Sentry as Logs through the `keptSink` above. The app's own `info` feeds
nothing, which is what it does now.

What that buys is the sequence worth having - "link lost → reconnecting →
reconnected" in front of a crash - at a cost that only exists while reporting
is on, and only for the library's traffic rather than the whole app's.

What it gives up is app-side commentary before a crash. That is the right
trade only while the app's `info` sites are genuinely commentary, which is
exactly the question #103 asks about 48 of them. See the Consequences.

### 5. A third level, `caught`, for a failure worth keeping and not worth alerting on

Decided 2026-10-02. This reverses a rule `info`'s own doc states, so the
reversal is argued rather than asserted.

**Where a log goes today.** `_emit` has two destinations and neither is a file:
`history`, a 500-entry `ListQueue` in memory, and `debugPrint`. In a release
build nothing prints, so `error` and `warn` land in that queue and nothing else
does. The queue dies with the process - which is the FFI case this ADR opens
with - and with a restart, and the one way out of it is Settings → Log → Copy
and a human pasting the result somewhere.

**The gap.** 48 `LogService.info` calls sit inside a `catch` — the figure
`test/log_level_budget_test.dart` is at today, and the remainder after #107,
#108, #110, #111 and #115 took it down from the 117 #103 opened with. Those
sweeps raised the sites that were nobody's second surface, so the 48 left are
the ones the triage ruled *do* have one: the budget file says so area by area,
and says "read through" for all of them but `pages/tools`.

Which is the gap, stated precisely. `info` is not quiet in a release build, it
is absent: `infoOn` is a const and those call sites leave the binary. So for 48
failure paths the *user* is told and no *record* exists anywhere — not the
history, not the clipboard, and after this ADR, not Sentry either. A bug report
about one of them carries a user saying "it failed" and a log with nothing in
it. That is a narrower claim than the one #103 was opened on, and it is the one
this section argues from: the reader who is missing is the developer, not the
user.

**The mechanism already exists.** `_emit`'s two axes are independent, and
`warn` already uses the combination needed: kept in release, printed only in a
talking build. So the third level is one line.

```dart
static void caught(String msg) =>
    _emit('[caught] $msg', keep: true, console: infoOn);
```

The prefix is what `keptSink` reads to send it as a Sentry log at **info**
level rather than `warning`, so these are searchable without firing the
alerting that `warn` is for. It is called `caught` because that is where it
belongs - inside a catch - and because the distinction from `warn` is the
audience, not the severity: `warn` is a failure somebody should look at,
`caught` is a failure somebody may need to read about later.

**The rule, and it is narrow on purpose.** `caught` is for a failure where the
operation did not do what was asked. Commentary about something merely absent
stays `info` and stays out of the binary.

The quota is not the reason for the narrowness - the open-source programme
allows far more logs than this app can produce. The reason is the person
reading them. Applied to `pages/archive`'s 24 sites, which is the densest
area:

| | `caught` | stays `info` |
|---|---|---|
| `list`, `read`, `write`, `delete`, `mkdir`, `rename`, `appStart` refused | 12 | |
| `refresh`, `syncCategory`, `sync` failed | 3 | |
| `$path is unavailable`, `no hardware name` | | expected absence |
| `md5 check <path> failed`, per file in a sync | | the per-sync summary at `warn` covers it (#194) |
| `[Map] location stream`, `[StorageCards] watchStorage` | | stream noise, repeats |

Fifteen of twenty-four. The three excluded kinds are also the only chatty ones,
so the boundedness #110 and #111 argued for is kept rather than traded away.

**What this reverses.** `LogService.info`'s doc says: *"There is no catch-all to
reach for instead. Pick a level at each site."* `caught` is a catch-all, and
that rule was right for its reader - a person scrolling five hundred lines on a
phone, where volume is noise and a wrong level is a line nobody finds. The
reader is what changed. Gathered and indexed, a surplus line costs nothing to
skip and a missing one cannot be recovered at all.

The per-site judgment does not disappear, it gets smaller: not "which of five
levels" but "did an operation fail, or is this commentary".

**The new way to game the ratchet, named before it is used.** Moving a site
from `info` to `caught` lowers `log_level_budget_test.dart` legitimately - the
budget counts failures reported only at a level release drops, and `caught` is
not one. That is the opposite of the anti-pattern CLAUDE.md lists, where the
number falls because a log was deleted. But it opens the mirror of it: moving
*commentary* to `caught` would also lower the number, while putting noise in
front of whoever reads Sentry.

So `caught` gets a ratchet of its own, a ceiling per area, as
[0004](0004-ratchet-not-lint.md) prescribes for anything the project wants a
bounded amount of. Five use `test/ratchet.dart` today - `bare_catch`,
`build_io`, `client_reach`, `log_level` and `unawaited` - so this is the sixth,
and the import guard in §2 the seventh. The sixth is the only one of them whose
number is meant to *rise* - once, as the triage lands, and not after.

**This is worth doing before Sentry exists.** `caught` reaches `history`
immediately, so the 48 become visible in Settings → Log on the next build,
months before `keptSink` is written. The ADR consumes the work; it does not
gate it.

### 6. Privacy is four layers, because no single one covers everything

1. **Not collected:** `sendDefaultPii: false`; no screenshots, no view
   hierarchy; print breadcrumbs off, since `LogService` feeds Sentry directly.
2. **One scrubber, client-side.** `_redact` moves to `telemetry/scrub.dart`
   and gains known Flipper names, file names under `/ext` and `/int` (the
   extension survives), long hex runs, coordinates and URL query strings. It
   runs before every event, breadcrumb, log and transaction is sent, and on the
   Log screen's Copy.
3. **Server-side rules for the same patterns,** and "Prevent storing IP
   addresses" on. Native crashes do not pass through Dart's `beforeSend`, and
   their module paths carry `C:\Users\<name>\…` — the Windows launcher
   extracts into `%TEMP%`.
4. **Replay masks.** `maskAllText` masks text widgets. The hex editor paints
   card bytes with `TextPainter` (`pages/archive/editor/hex/view.dart`), and
   the remote-desktop screen is a `RawImage` fed the `ui.Image` that
   `remote/desktop/frame_decoder.dart` decodes
   (`remote/desktop/widgets/screen.dart:151`) — not an `Image` widget, so
   `maskAllImages` does not reach that one either. Neither surface is masked by
   anything the SDK does on its own; both are wrapped in `SentryMask` and
   checked in a recorded replay before replay ships.

### 7. `sentry_flutter` 9.30.1, written to move to 10

9.30.0 is the floor: it fixed a native worker leaked per engine, reported by a
BLE app with a headless engine — the home widget's shape (sentry-dart#3960).

10.0 is at RC and requires Swift Package Manager. This repository builds with
`enable-swift-package-manager: false`, and macOS links a local pod,
`qunleashed_hardnested`. Moving is its own task.

9.30.1 pins `jni` to 0.14.2 exactly, so the lockfile moves `jni` from 1.0.0
to 0.14.2 and `path_provider_android` from 2.3.1 to 2.2.23.

Code is written so that 10 is a version bump: no SDK profiling, no
`enableLogs` or `enableMetrics` flags, `SentryFeedbackForm` rather than
`SentryFeedbackWidget`.

### 8. Sampling

Errors, traces, logs and metrics at 100%. Replay records on error only
(`onErrorSampleRate: 1.0`, `sessionSampleRate: 0`), Android and iOS. Revisited
after a month of real volume.

## Rejected alternatives (and why)

**Firebase Crashlytics.** Firebase is already in the app for push, but
Crashlytics has no Windows or Linux, and nothing for logs or traces.

**`Sentry.captureException` at catch sites.** Several hundred sites, each a
judgement, when four chokepoints already see every failure that is recorded at
all — and the sweeps that made them see it are finished.

**A Sentry dependency in flipperlib.** Every consumer of the library would
inherit a vendor, and a hook in the library's own types is what makes the
behaviour testable from there.

**`sentry_logging`.** Neither submodule uses `package:logging`, and
`LogService` already funnels what does.

**Reporting on by default, before asking.** Declined on 2026-10-01, and
**adopted on 2026-10-07** — §1 now describes it. The argument against it was
that F-Droid applies the Tracking anti-feature unless reporting is opt-in and
off by default, that IzzyOnDroid is stricter still for security tools, and
that these are the users who would notice.

What was wrong with it is that the app is on neither, and nothing schedules
it: [0014](0014-build-identity.md) names F-Droid once, as one channel a build
might come from. So the rejection defended a distribution that does not exist
against a cost that is certain - an opt-in crash reporter on a tool with this
audience collects from a single-digit share of installs, which is not enough
reports to find the fault in a BLE stack on a handset nobody on the project
owns. That is the whole reason for the decision, and trading it away for a
channel the project has not committed to was the wrong way round.

What the reversal actually costs, stated plainly: if qUnleashed is ever
published on F-Droid, the Tracking anti-feature applies to it unless the
default flips back. That is a known price on a decision nobody has taken,
rather than a surprise.

What stays from the rejection: nothing is collected that identifies a person
(§6), IP storage is off server-side, the switch is one tap away and the notice
says it is there, and replay - the only category that records the screen -
keeps the off-by-default the whole feature used to have.

**Every `LogService.error` as an issue.** No exception object to group on, and
most of them are expected.

**Profiling.** Alpha, iOS and macOS only, and removed in 10.

**10.0 now.** An RC, behind a packaging migration this decision should not
carry.

## Consequences

- A native crash is visible for the first time, symbolicated, on every
  platform.
- `classifyConnectError` gets a feed of the strings it misses.
- A new ratchet: `package:sentry*` imports outside `lib/services/telemetry/`.
- Every distributed build uploads debug files: dSYMs, PDBs, Android and Linux
  native symbols through `sentry_dart_plugin`; the R8 mapping through the
  Sentry Android Gradle Plugin with auto-install off, which the Dart plugin does
  not cover.
- Store paperwork, and more of it than an opt-in build would need: Google
  Play Data safety declaring crash logs and diagnostics as collected and
  optional, App Store privacy labels for Crash and Performance Data not linked
  to identity, and a privacy policy the repository does not have yet. The
  policy is the blocker of the three - both stores want the URL regardless, and
  §1's notice links it.
- Desktop gets no crash-free rate and no offline cache; mobile carries replay's
  overhead (about +13% CPU and +5% memory on Android, +6% CPU on iOS, per
  Sentry's measurements).
- **#103 gets a second argument.** Its 48 `LogService.info` calls inside a
  catch were left on the grounds that the UI resolves and the cause reaches a
  surface ([0008](0008-swallowed-errors.md)); the count was never the target.
  Once this lands, "a surface" also means the one a developer reads remotely,
  and `info` is not on it: `info` returns at `if (!infoOn) return;` and
  `infoOn` is false in every release build. A site that is commentary stays
  commentary; a site that is the last word on a failure now loses a second
  reader rather than one. The triage does not change, the stakes do.
- `_remember` gains a return value, and `LogService` gains `caught` (§5).
  Those, the two hooks and the flipperlib level pin are the whole of what this
  changes outside `lib/services/telemetry/`.
- A sixth ratchet, a ceiling on `caught` per area — seventh counting the
  import guard above. It is the only one of them whose number is meant to rise
  once and then hold.
- #103 stops being a parallel debt and becomes part of this, though less of it
  is left than its text says: the per-area triage is read through everywhere
  but `pages/tools`, and what the issue still holds open is the blind spots the
  ratchet cannot see — the `onError:` closures (#216's moved line and three
  before it), the bare catches (#118), the one-line wrapper (#119) and the two
  controllers that disagree about when an error reaches anyone (#114). The
  decision this section asks of it is therefore a re-ruling of 48 sites already
  ruled on, for a reader that did not exist when they were ruled, rather than a
  triage still to be done.
- To verify before the first release that carries it: `crashpad_handler`
  keeping its exec bit on Linux; where the crash database lives, since the
  Linux launcher deletes `/tmp/qunleashed-self-$$` on exit; a JDK on the Windows
  runner; `SentryWidgetsFlutterBinding` doing nothing while reporting is off.

## Rollout

| Phase | Scope |
|---|---|
| 0 | Sentry project, server-side scrubbing, GitHub integration for the three repositories, alerts |
| 0a | `caught`, its ratchet, and the re-ruling of the 48 that #103's triage left at `info`. Independent of Sentry - it lands in `history` and on the Log screen on the next build - and done first so no phase ships a failure nothing records |
| 1 | Errors and crashes: dependency, `telemetry/`, the Diagnostics switch and the one-time notice, scrubber, `guarded` → issues, CI defines and symbol upload, the import ratchet |
| 2 | Logs and tracing: `keptSink` and the `_remember` return it needs, flipperlib breadcrumbs in `_flipperlibSink` with the level pin raised, named routes and `SentryNavigatorObserver`, `traced`, `AppHttp` spans, the dartufbt sink |
| 3 | Metrics, replay with its masks, a "Send to developers" action on the Log screen through `captureFeedback`, the flipperlib observer |

Phase 1 is done when a `dev` build has delivered one forced Dart error and one
forced native crash from each of the five platforms, symbolicated.

## Migration: what happens to legacy code

No catch site changes. `guarded`, `LogService` and the classifier gain a
destination; the sites calling them do not move.

`LogService.info` keeps its meaning for every site that stays on it: not the
history, not Sentry, and absent from a release build altogether. What changes
is that it is no longer the only place a caught failure can go — §5 adds
`caught` for the ones where an operation did not do what was asked, and #103's
triage is what sorts the 48 between them. The budget in
`test/log_level_budget_test.dart` is unchanged in what it counts; a site
leaving it for `caught` is a legitimate fall rather than the deletion CLAUDE.md
warns about, and the new ceiling on `caught` is what keeps that from becoming a
way to launder commentary.

The 25 unnamed `MaterialPageRoute`s within features stay unnamed — 25 today,
and not one of them passes `settings`. Names are given once, in the `AppRoute`
registry, which is what the navigator observer needs to build transactions.
