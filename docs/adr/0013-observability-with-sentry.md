# 0013. Sentry is the second channel, wired into the chokepoints that exist

Status: Proposed (2026-10-01); breadcrumb source settled and the logging
chokepoints checked against the code (2026-10-02)

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

### 1. Sentry, behind consent, with everything on once consent is given

One prompt, at first launch and once for existing users after the update.
**Nothing starts before the answer** — no init, no network.

After "yes", every category is on: errors and crashes; performance, logs and
metrics; replay where the platform has it. Settings → Diagnostics, next to
Log, has a switch per category. Turning reporting off calls `Sentry.close()`,
which also shuts the native SDK and the handlers; turning it on starts it
again.

Firebase Test Lab — which Google Play's pre-launch report runs on, and whose
robots will tap "yes" — never starts it.

The Log screen stays. It is still the route for anyone who says no, and the
history it shows is the same text Sentry receives.

### 2. One folder imports Sentry, and it plugs into what exists

`lib/services/telemetry/` is the only place allowed to import `package:sentry*`
— a ratchet test on `analyzer`, as [0004](0004-ratchet-not-lint.md) prescribes.
The rest of the app keeps calling `LogService`, `guarded` and the classifier
as it does now.

| Chokepoint | What reaches Sentry |
|---|---|
| `_initCore` | Init, after `LogService.initialize()` and the consent read, with its own catch. Sentry saves and calls the `FlutterError.onError` and `PlatformDispatcher.onError` it finds, so `LogService`'s handlers going in first keeps both. One init serves `main()` and `widgetMain()`: `promote` reuses the engine. |
| `LogService._emit`, kept entries | Sentry Logs, through a `keptSink` hook in the shape of flipperlib's `Log.sink`. **The first of a run only**: one RPC timeout produces hundreds of identical lines, which is why `_remember` coalesces them. That coalescing is not visible from `_emit` today - `_remember` returns `void` and folds silently - so it has to report whether the line was new. One signature, and the hook reads it rather than comparing bodies a second time. |
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
  `error` whenever nothing is printing, which is every release build, and its
  doc says why: history gets the transport faults and session failures a bug
  report needs "and none of the traffic below them". Reporting raises that pin;
  it is a change to a recorded decision rather than a setting that already
  allows it, and the pin returns when reporting is turned off. And the hook
  belongs in `_flipperlibSink`, **before** it calls `_emit` - see the section
  below for why it cannot sit inside `_emit`. Request tracing needs a PR there:
  a `FlipperRpcObserver` constructor parameter on `FlipperClient`, no-op by
  default ([0002](0002-dependencies-are-passed-in.md)), called **synchronously
  inside `callRpcFrames`** at enqueue, send and completion. Synchronously,
  because a span is found through the caller's zone and the queue worker runs
  in another one.
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
stamp, plus a scrub, since a breadcrumb is sent and §5 scrubs everything
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

### 5. Privacy is four layers, because no single one covers everything

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
   card bytes with `TextPainter` (`pages/archive/editor/hex/view.dart`) and the
   remote-desktop screen is custom-painted, so neither is masked by it; both
   are wrapped in `SentryMask` and checked in a recorded replay before replay
   ships.

### 6. `sentry_flutter` 9.30.1, written to move to 10

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

### 7. Sampling

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

**Reporting on by default, before asking.** F-Droid applies the Tracking
anti-feature unless reporting is opt-in and off by default, IzzyOnDroid is
stricter for security tools, and these are the users who would notice.

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
- Store paperwork: Google Play Data safety, and App Store privacy labels once
  the app is there.
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
- `_remember` gains a return value, which is the only change this makes to a
  file outside `lib/services/telemetry/` beyond the two hooks.
- To verify before the first release that carries it: `crashpad_handler`
  keeping its exec bit on Linux; where the crash database lives, since the
  Linux launcher deletes `/tmp/qunleashed-self-$$` on exit; a JDK on the Windows
  runner; `SentryWidgetsFlutterBinding` doing nothing while reporting is off.

## Rollout

| Phase | Scope |
|---|---|
| 0 | Sentry project, server-side scrubbing, GitHub integration for the three repositories, alerts |
| 1 | Errors and crashes: dependency, `telemetry/`, consent and Diagnostics, scrubber, `guarded` → issues, CI defines and symbol upload, the import ratchet |
| 2 | Logs and tracing: `keptSink` and the `_remember` return it needs, flipperlib breadcrumbs in `_flipperlibSink` with the level pin raised, named routes and `SentryNavigatorObserver`, `traced`, `AppHttp` spans, the dartufbt sink |
| 3 | Metrics, replay with its masks, a "Send to developers" action on the Log screen through `captureFeedback`, the flipperlib observer |

Phase 1 is done when a `dev` build has delivered one forced Dart error and one
forced native crash from each of the five platforms, symbolicated.

## Migration: what happens to legacy code

No catch site changes. `guarded`, `LogService` and the classifier gain a
destination; the sites calling them do not move.

`LogService.info` stays where it is and still reaches nothing — not the
history, not Sentry. The rule in its doc comment, and the budget in
`test/log_level_budget_test.dart`, apply unchanged.

The 23 unnamed `MaterialPageRoute`s within features stay unnamed. Names are
given once, in the `AppRoute` registry, which is what the navigator observer
needs to build transactions.
