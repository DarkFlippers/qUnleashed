# Releasing qUnleashed

For maintainers. What CI does on its own, what a release costs you, and what
each refusal means. The decision behind all of it is
[ADR 0014](adr/0014-build-identity.md); this is the half you need with a
terminal open.

## The model, in four facts

1. **`pubspec.yaml` holds the version being built *toward*, not the last one
   released.** During the 0.16.0 cycle it says `0.16.0`, and every dev build is
   named that. The versions in this file are illustrative; `pubspec.yaml` is
   what the current cycle actually is.
2. **Moving it is a commit somebody makes on purpose.** CI never picks a digit,
   because patch against minor against major is a decision no rule over the
   previous version can make. What CI does is refuse a build whose version is
   wrong (below).
3. **The build number is a counter and means nothing else:**
   `100000 + commits on main × 10 + slot`, where the slot is `0` for a dev
   build and the run attempt for a release. It carries all the ordering,
   because every dev build in a cycle shares one version name.
4. **Three channels.** `dev` is every push to `main`; `release` is a tag you
   cut; `local` is anybody's own `flutter run`. The channel comes from the
   trigger, never from the tag's prefix.

A build says which of these it is in two places. The Tools screen reads
`qUnleashed for Android v0.16.0-dev (108170 · abc1234)`, and tapping it copies
the line; a release shows no suffix. And every event it reports to Sentry
carries the same identity as its release name and `environment`, with the
submodule commits as the `flipperlib` and `dartufbt` tags.

That second place used to be a copied log, opening with
`qUnleashed 0.16.0-dev · 108170 · abc1234` and the submodule commits under it.
ADR 0013 §1 removed the log and its Copy button, so the Tools screen is the
only thing a user can read an identity off now - which is also why the tags
matter: they are how a submodule revision reaches a bug report at all.

## What happens without you

**Every push to `main` builds all five platforms and replaces one rolling
prerelease tagged `dev`.** One tag, one link to bookmark, no history — the
assets are overwritten each time. A push notification goes to the `app_dev`
topic.

You do nothing for this. Two things worth knowing:

- A burst of commits builds only the newest. The older runs are cancelled, and
  that is deliberate — a dev build is disposable and the rolling release would
  have been overwritten anyway.
- Pushes that only touch `docs/`, `**/*.md`, `.github/ISSUE_TEMPLATE/`,
  `fastlane/` or `LICENSE` do not build. **Translations are not in that
  list**, because they are compiled in.

## Cutting a release

Four steps. The version is the only decision.

1. **Decide the version** and make sure `pubspec.yaml` already holds it. If the
   cycle has been running toward `0.16.0` and that is what you are releasing,
   there is nothing to do. If you want a patch instead, change it to `0.16.1`
   and push that commit to `main` first.
2. **Create the release in GitHub** with the tag set to the bare version —
   `0.16.0`. **No `dev-` prefix** (see the refusals below). A `v` prefix or any
   other letter prefix is accepted.

   **Do not tag a commit whose changes are all docs.** `paths-ignore` sits on
   the same `on.push` key as `tags`, so it may be in scope for a tag push too -
   and a filtered push produces no run at all, which `assert-published` cannot
   catch because there is nothing for it to check. #291 is settling whether
   this actually fires; until it does, tag a commit that touches something
   buildable.
3. **CI builds and publishes it.** All five platforms, a real release rather
   than a prerelease, marked latest, with generated notes, `SHA256SUMS`, and a
   push notification to `app_release`. The rolling `dev` prerelease is left
   alone.
4. **Open the next cycle immediately.** Bump `pubspec.yaml` to the next version
   and push it to `main`. This is not optional — see below.

## Immediately after a release: open the next cycle

Until you bump `pubspec.yaml`, **every push to `main` fails**:

```
::error::Version 0.16.0 has already been published as 0.16.0.
Open the next cycle by bumping pubspec.yaml.
```

That is the guard working, not a bug. It replaced an automatic bump that
guessed minor, and it exists because the alternative failure is much worse: a
dev build named after a released version is refused by TestFlight days later,
far from the commit, and reported as a store problem rather than a versioning
one.

So make the bump the first commit after the release. One line, and `main` is
green again.

## When CI refuses

Four refusals, with their text. The fifth, a version already published, has
its own section above because it is the one you will meet routinely. Each is
`derive_version.sh` saying the build would not have been what it claimed.

### The tag does not match pubspec

```
::error::Tag 0.17.0 names 0.17.0 but pubspec.yaml says 0.16.0.
Bump pubspec in a commit of its own, or tag the version it holds.
```

You tagged a version the commit does not hold. Either tag `0.16.0`, or push a
pubspec bump to `main` first and tag that commit. Do not tag a commit whose
pubspec you have not updated — that is the shape that broke the release of
2026-10-01.

### The tag uses the `dev-` prefix

```
::error::The tag dev-0.16.0 uses the dev- prefix, which is no longer a
channel: a dev build comes from a push to main, and 'dev' is the rolling
prerelease. Tag the version itself.
```

This is the old habit — seven of this repository's tags are `dev-*`, from when
that was how a dev build was made. It is refused rather than mapped, because
`dev` is now the rolling prerelease's own tag name: a `dev-0.16.0` push would
have deleted and recreated that prerelease, left its own tag with no release
and no assets, and labelled the binaries a dev build. Every job would have
succeeded. Tag `0.16.0`.

### The tag has something after the patch number

```
::error::Tag must be a semantic version with an optional prefix - 0.6.1,
v0.6.1, alpha-0.6.1 - and nothing after the patch number. Got
'beta-0.16.0-rc1'.
```

There is no release-candidate form. `beta-0.16.0-rc1` would have matched
`0.16.0` and published claiming to be the real release.

### A shallow checkout

```
::error::This checkout is shallow or not a repository, so the commit count
would be wrong. Use fetch-depth: 0.
```

Only reachable if a workflow loses its `fetch-depth: 0`. The build number
counts commits and the published-version guard reads every tag, and a shallow
clone answers `1` to the count — a plausible number that collides with every
other shallow build. The script refuses rather than produce one.

## If a release job fails halfway

**Re-run it.** Re-running a release increments the run attempt, which is the
slot in the build number, so the retry produces a number the stores have not
already refused — `100031` becomes `100032`.

Re-running `publish` alone is safe: it reuses the artifacts from the first
attempt, and the version and number it quotes come from the build job's
outputs rather than from a fresh derivation, so the release cannot describe a
build nobody made. That is the cheap option when the failure was in publishing
itself.

Re-run the **whole workflow** when the failure was in a build, or when you do
not know which it was — the binaries then get the new slot as well as the
release text.

A dev build is the opposite: re-running one produces the same number on
purpose. It is disposable, and the fix for wanting a fresh one is another
commit.

## Building locally with the things CI has

CI passes a set of `--dart-define`s from its own secrets — the map key, the
build server — plus the build identity `derive_version.sh` derives. A local
build gets none of them unless you say so, which is usually right:
`flutter run` works without any of it.

When you do want them, copy the template and fill in what you need:

```bash
cp dart-defines.local.example.json dart-defines.local.json
flutter run --dart-define-from-file=dart-defines.local.json
```

`dart-defines.local.json` is gitignored; the `.example.` file beside it is not,
so never put a real value in the template. It is one of five gitignored
local-config files a fresh clone needs, and the only one that fails silently;
#284 is giving all five one document and a stub script.

| Key | What it is | Where it comes from |
|---|---|---|
| `QU_CHANNEL` | `local`, and leave it that way | — |
| `QU_SENTRY_DSN` | the project errors are reported to | Sentry → Project → Settings → Client Keys (DSN), and the `SENTRY_DSN` repo secret |
| `QU_CARTO_KEY` | basemap tiles | the `QU_CARTO_KEY` repo secret |
| `QU_BUILD_SERVER_KEY` | the Flibler build server | its repo secret |
| `QU_BUILD_SERVER_URL` | only to point at a different server; it has a public default | — |
| `QLOG`, `QLOG_LEVEL` | make a build talk | see `LogService` |

**The DSN is public, and the auth token is not.** A DSN identifies a project
and authorises nothing but writing to it, which is why it is compiled into
every shipped binary and why it is safe in a file on your disk. Leave it empty
and the app says `[Telemetry] not reporting: no DSN was compiled in` once, in
the log, and sends nothing. The token is the next section.

**`QU_CHANNEL` stays `local`.** Setting it to `dev` or `release` makes your own
tree report as a build somebody could otherwise go and look at. `local` is the
compiled-in default for exactly that reason — see `BuildIdentity.channelName`
in `lib/services/build_identity.dart`.

### The auth token is not one of these

`SENTRY_AUTH_TOKEN` must **never** be a `--dart-define`: a define is compiled
into the binary, and anyone with the APK could read it out. It belongs in the
environment — `~/.sentryclirc` or a user-level variable — and is only needed
for uploading debug files, never for checking that an error arrives.

In CI it is a repository secret, read by the `Upload debug symbols to Sentry`
step in each of the three build jobs. A run without it builds and publishes
normally and says so in the log; the traces from that build are just not
symbolicated. That is deliberate — a fork has to be able to build.

**The DSN's secret is `SENTRY_DSN`, and the define it becomes is
`QU_SENTRY_DSN`.** The two spellings are not a typo: the secret is named for
Sentry, beside `SENTRY_AUTH_TOKEN`, and the define is named for this app,
beside `QU_CARTO_KEY`. The three `Derive the build identity` steps map one to
the other. Nothing reads `secrets.QU_SENTRY_DSN` — a build wired to that name
compiles with the define empty, publishes green, and reports nothing, which is
what happened on the first push to `main` after ADR 0013 merged. The script
now says `::warning::No DSN` on a `dev` or `release` build rather than
omitting the define in silence. `SENTRY_ORG` and `SENTRY_PROJECT` exist as
secrets but are read by nothing — `pubspec.yaml`'s `sentry:` block supplies
both to `sentry_dart_plugin`.

### Checking that reporting works

```bash
cp dart-defines.local.example.json dart-defines.local.json   # fill in the DSN
flutter run --dart-define-from-file=dart-defines.local.json
```

The build reports as `qunleashed@<version>-local+<build>` in the `local`
environment, so its events are one filter away from anything shipped. With the
DSN blank the app says `[Telemetry] not reporting: no DSN was compiled in` once
on the Diagnostics screen's log and sends nothing — which is how to tell "I
forgot the define" from "the SDK is broken".

## What is not automated yet

Honest list, so nobody waits for something that is not coming.

| | |
|---|---|
| Store uploads | Nothing uploads to TestFlight or the Play internal track. The ADR is shaped for it; the jobs do not exist. |
| The version bump after a release | Deliberately manual (fact 2). A bot could open the PR; none does. |
| The R8 mapping | `sentry_dart_plugin` uploads dSYMs, PDBs and native symbols, but not Android's R8 mapping — that wants the Sentry Android Gradle Plugin, which is a change in `android/` that has not been made. Until it is, an obfuscated Android Dart trace is less readable than the other four platforms'. |
| Release commits in the submodules | Each Sentry release gets the app's commits automatically. [ADR 0013](adr/0013-observability-with-sentry.md) §3 wants flipperlib's and dartufbt's too, so a suspect commit can be found in a submodule; they go as event tags today, not as release commits. |
| `installerStore` | 0014 §1 wants the actual install source — TestFlight, Play, a sideload — read at runtime and reported. Not read anywhere yet. |

## Where each piece lives

| | |
|---|---|
| `.github/scripts/derive_version.sh` | The one place a trigger becomes a build identity: version, number, channel, three commits. Everything above is this script. |
| `.github/scripts/derive_version_test.sh` | Its tests. Run it directly; it needs no Flutter. |
| `.github/workflows/auto-release.yml` | The triggers, the five builds, the publish job and the rolling prerelease. |
| `lib/services/build_identity.dart` | How the app reads what was compiled in, and formats it for a person. |
| `pubspec.yaml` | The version. Nothing else about the identity lives here — the build number is derived. |
