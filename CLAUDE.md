# CLAUDE.md — qUnleashed

A Flutter companion app for Flipper Zero: talks to the device over BLE **and**
USB/serial, browses and edits its files, installs firmware and apps. Ships on
Android, iOS and four desktop targets.

Architecture decisions live in [`docs/adr/`](docs/adr/). What the codebase
looks like today is described in [`docs/architecture.md`](docs/architecture.md).

## Commands

```bash
flutter run                              # Flutter 3.47.1 / Dart 3.13.1, pinned
flutter test
flutter analyze                          # infos and warnings are fatal in CI
.github/scripts/check_format.sh --write  # NOT `dart format .` — see below
```

The format gate takes its file list from `git ls-files`, because `dart format`
does not read the analyzer's exclude list. Running `dart format .` reformats
generated protobuf and the platform folders, which CI then rejects.

There is **no code generation**. No `build_runner`, nothing to run before the
code compiles.

Submodules (`lib/modules/flipperlib`, `lib/modules/dartufbt`) are separate
repositories in the same organisation. A change there is a PR in that
repository plus a submodule bump here.

## Stack

| Area | Decision | ADR |
|---|---|---|
| State | `ChangeNotifier` + `setState`. No state-management package | [0001](docs/adr/0001-state-management.md) |
| DI | Constructor parameters for new code; no container | [0002](docs/adr/0002-dependencies-are-passed-in.md) |
| Routing | `AppRoute` registry across features, `Navigator` within one | [0006](docs/adr/0006-navigation.md) |
| Layers | No repository layer. UI may import `flipperlib` | [0007](docs/adr/0007-no-repository-layer.md) |
| Errors | Exceptions. No result types, no sealed failure hierarchies | [0008](docs/adr/0008-swallowed-errors.md) |
| JSON | Hand-written, tolerant, one shared mechanism | [0005](docs/adr/0005-tolerant-decoding.md) |
| Rules | Ratchet tests on `analyzer`, not lint plugins | [0004](docs/adr/0004-ratchet-not-lint.md) |

## Target patterns vs legacy

> New code follows the target patterns (see the ADRs). Legacy code is not
> rewritten without a task of its own.
> **Do not copy a pattern from a neighbouring file if it is listed below.**

Legacy, kept deliberately, not to be imitated:

- **`static final X instance` singletons, and `FlipperOneClient()`.** New code
  takes dependencies as parameters instead. Two scoreboards say whether this is
  going the right way: `resetFirmwareState()` in `test/firmware_fixture.dart`
  should get shorter, and the ratchet counting `FlipperOneClient()` under
  `lib/pages/**` should not rise.
  [0002](docs/adr/0002-dependencies-are-passed-in.md),
  [0004](docs/adr/0004-ratchet-not-lint.md)
- **All-or-nothing `fromJson`** — a decoder that throws on the first bad field.
  Feed decoding reads entry by entry and names what it skipped.
  [0005](docs/adr/0005-tolerant-decoding.md)
- **Sentinel values for absence** — `sha256: ''`, `timestamp: 0`. Absence is
  `null`. [0009](docs/adr/0009-absence-is-null.md)
- **`LogService.info` as the last word on a failure.** `info` is `keep: false`
  and const-folds away in release, so nothing reaches the in-app log.
  `test/log_level_budget_test.dart` ratchets the count per directory.

## BLE and transport invariants

This is the part where a mistake reaches a user rather than CI. Check what
the submodule's own suite covers before relying on it to catch you — see
[0003](docs/adr/0003-test-flipperlib-first.md) for what is being built up
there and why it was the first thing scheduled.

- **`_initCore` must never throw.** `lib/main.dart` has two entry points:
  `main()` and `widgetMain()`, the second a headless isolate a home-screen
  widget starts. Both await `_initCore`. A throw there is not a setting that
  falls back — it is an app that never appears, on either path. Every call in
  it that touches disk or a platform channel carries its own catch.
- **Anything assembled in `_runApp` does not exist in `widgetMain()`.** Wiring
  a dependency in the wrong place breaks a path nobody runs locally and CI does
  not cover.
- **`guarded()` never rejects.** Queues chain the next operation with
  `previous.then(...)`, so a rejected future would strand everything behind it
  for the life of the chain. Do not "improve" it to propagate.
- **Auto-reconnect is on** (`autoReconnect = true`, `reconnectSettle` 600 ms),
  and a file upload restarts after the session is restored
  (`client/api/storage.dart`). Code that assumes a transfer runs once is wrong.
- **The request queue is ordered and its flags are load-bearing** — `priority`,
  `seq`, `interleavable`, `holdsTxUntilAnswer`. Do not reorder or drop them to
  make something simpler.
- **`connectionStream` is a broadcast stream**, and an error on it does not end
  it. A wait that treats the first event as "connected" is wrong; consult
  `isConnected`.
- **The client's API is extensions over a small core.** `appStart`,
  `storageRead`, `appStateStream` and the rest of `client/api/*.dart` are
  `extension ... on FlipperClient`, and an extension is resolved statically -
  declaring one on a fake does nothing, the real body runs. Fake
  `callRpcFrames` and `notificationStream` instead; everything above them goes
  through those two. `test/emulate_start_test.dart` is the worked example.
- **Connection errors are classified at the boundary**, not typed:
  `classifyConnectError` → `FlipperConnectErrorKind`, consumed by an exhaustive
  `switch`. It matches substrings from platform BLE stacks, so a sealed
  hierarchy is impossible here. [0008](docs/adr/0008-swallowed-errors.md)

## Definition of Done

Before saying a change is finished:

1. `.github/scripts/check_format.sh` — no differences.
2. `flutter analyze` — no new problems. Infos and warnings are fatal in CI.
3. `flutter test` — green.
4. UI changes: checked on Android **and** iOS, or say explicitly that they were
   not.
5. If the change touches a submodule, its own CI must be green too, and the
   submodule bump is a separate commit here.

Claims about test or analyzer state are made after running them, not from
memory. Report failures with the output.

## Anti-patterns

Each of these has already shipped a bug in this repository.

- **I/O in `build` or `didUpdateWidget`.** `DeviceScope` rebuilds on a
  five-second battery poll, so a fetch there ran 12 times a minute forever
  against a server that was not answering (#135/#136). Fetch from a listener
  with a guard.
- **A bare `catch (_) {}` on a path where the UI is waiting.** Three firmware
  surfaces latched "Checking…" until the app restarted, each behind a catch
  that recorded nothing in any build (#118/#134). Best-effort catches — `mkdir`
  of an existing directory, temp-file cleanup — are fine and stay.
- **Deleting a counted `LogService.info` to make the ratchet go green.** That
  lowers the number by making the code worse; the ratchet's own comment says
  so.
- **Asserting on a log line's count when `LogService` can coalesce it.**
  `_remember` folds a *consecutive* identical body into the existing entry, so
  `hasLength(1)` cannot tell "said once" from "said twice". This has produced a
  test that passed for the wrong reason more than once.
- **Trusting that a test fails for the reason its name says.** In this
  codebase, four separate tests have passed on a mechanism other than the one
  they claimed. Mutation runs caught all four; reading caught none.

## Official Flutter guidance that applies

The [official architecture guide](https://docs.flutter.dev/app-architecture) is
the neutral reference, and its case study uses `ChangeNotifier` — the same
choice made here. Where it recommends a ViewModel per View, this project
diverges deliberately ([0007](docs/adr/0007-no-repository-layer.md)); the rest
of its advice on separating UI from data applies.

Do not propose Riverpod, `go_router`, `freezed` or `json_serializable` without
reading the ADR that rejected it first. Each was considered with this
codebase's evidence, and each rejection names what would change the answer.
