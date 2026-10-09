# Releasing qUnleashed

For maintainers. What CI does on its own, what a release costs you, and what
each refusal means. The decision behind all of it is
[ADR 0014](adr/0014-build-identity.md); this is the half you need with a
terminal open.

## The model, in four facts

1. **`pubspec.yaml` holds the version being built *toward*, not the last one
   released.** During the 0.16.0 cycle it says `0.16.0`, and every dev build is
   named that.
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

A build says which of these it is on the Tools screen and at the head of a
copied log: `qUnleashed for Android v0.16.0-dev (108170 · abc1234)`. Tapping
that line copies it. A release shows no suffix.

## What happens without you

**Every push to `main` builds all five platforms and replaces one rolling
prerelease tagged `dev`.** One tag, one link to bookmark, no history — the
assets are overwritten each time. A push notification goes to the `app_dev`
topic.

You do nothing for this. Two things worth knowing:

- A burst of commits builds only the newest. The older runs are cancelled, and
  that is deliberate — a dev build is disposable and the rolling release would
  have been overwritten anyway.
- Pushes that only touch `docs/`, `**/*.md`, `fastlane/` or `LICENSE` do not
  build. **Translations are not in that list**, because they are compiled in.

## Cutting a release

Four steps. The version is the only decision.

1. **Decide the version** and make sure `pubspec.yaml` already holds it. If the
   cycle has been running toward `0.16.0` and that is what you are releasing,
   there is nothing to do. If you want a patch instead, change it to `0.16.1`
   and push that commit to `main` first.
2. **Create the release in GitHub** with the tag set to the bare version —
   `0.16.0`. **No `dev-` prefix** (see the refusals below). A `v` prefix or any
   other letter prefix is accepted.
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

Four refusals, with their text. Each is `derive_version.sh` saying the build
would not have been what it claimed.

### The tag does not match pubspec

```
::error::Tag 0.17.0 names 0.17.0 but pubspec.yaml says 0.16.0.
Bump pubspec in a commit of its own, or tag the version it holds.
```

You tagged a version the commit does not hold. Either tag `0.16.0`, or push a
pubspec bump to `main` first and tag that commit. Do not tag a commit whose
pubspec you have not updated — that is the shape that broke the release of
2026-10-01.

### The version has already been published

See the section above. Bump `pubspec.yaml`.

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

Re-run the **whole workflow**, not just the failed job. Re-running `publish`
alone reuses the artifacts from the first attempt, and only the identity
derived by the build job is quoted in the release, so the two would still
agree — but a half-re-run has no other advantage and the whole run is cheap
against the confusion.

A dev build is the opposite: re-running one produces the same number on
purpose. It is disposable, and the fix for wanting a fresh one is another
commit.

## Building locally with the things CI has

CI passes a set of `--dart-define`s from its own secrets — the Sentry DSN, the
map key, the build server. A local build gets none of them unless you say so,
which is usually right: `flutter run` works without any of it.

When you do want them — to check that a crash actually reaches Sentry, say —
copy the template and fill in what you need:

```bash
cp dart-defines.local.example.json dart-defines.local.json
flutter run --dart-define-from-file=dart-defines.local.json
```

`dart-defines.local.json` is gitignored; the `.example.` file beside it is not,
so never put a real value in the template.

| Key | What it is | Where it comes from |
|---|---|---|
| `QU_SENTRY_DSN` | where the app reports to | Sentry → Project → Settings → Client Keys (DSN) |
| `QU_CHANNEL` | `local`, and leave it that way | — |
| `QU_CARTO_KEY` | basemap tiles | the `QU_CARTO_KEY` repo secret |
| `QU_BUILD_SERVER_URL` / `_KEY` | the Flibler build server | their repo secrets |
| `QLOG`, `QLOG_LEVEL` | make a build talk | see `LogService` |

**`QU_CHANNEL` stays `local`.** Setting it to `dev` or `release` makes your own
tree report as a build somebody could otherwise go and look at — which is the
one thing 0014 §1 defaults it to `local` to prevent.

### The auth token is not one of these

`SENTRY_AUTH_TOKEN` must **never** be a `--dart-define`: a define is compiled
into the binary, and anyone with the APK could read it out. It is read from the
environment at build time instead, by `sentry_dart_plugin`, and only when
uploading debug files or creating a release.

If you need it locally — which is only for testing symbol upload, never for
checking that an error arrives — put it in `~/.sentryclirc` or a user-level
environment variable. Not in the repository, and not in the file above.

## What is not automated yet

Honest list, so nobody waits for something that is not coming.

| | |
|---|---|
| Store uploads | Nothing uploads to TestFlight or the Play internal track. The ADR is shaped for it; the jobs do not exist. |
| The version bump after a release | Deliberately manual (fact 2). A bot could open the PR; none does. |
| Anything Sentry | `release`, `dist`, `environment` and the commit tags are all [ADR 0013](adr/0013-observability-with-sentry.md), which has not landed. The build already carries every value they need. |
| `installerStore` | 0014 §1 wants the actual install source — TestFlight, Play, a sideload — read at runtime and reported. Not read anywhere yet. |

## Where each piece lives

| | |
|---|---|
| `.github/scripts/derive_version.sh` | The one place a trigger becomes a build identity: version, number, channel, three commits. Everything above is this script. |
| `.github/scripts/derive_version_test.sh` | Its tests. Run it directly; it needs no Flutter. |
| `.github/workflows/auto-release.yml` | The triggers, the five builds, the publish job and the rolling prerelease. |
| `lib/services/build_identity.dart` | How the app reads what was compiled in, and formats it for a person. |
| `pubspec.yaml` | The version. Nothing else about the identity lives here — the build number is derived. |
