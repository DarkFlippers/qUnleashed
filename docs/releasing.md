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
2. **Moving it is a commit somebody makes on purpose.** CI *proposes* a digit
   after a release - a minor, in a draft pull request - and never lands one,
   because patch against minor against major is a decision no rule over the
   previous version can make. The eight released transitions since 0.11.0 are
   four patches and four minors, so the proposal is a coin flip and the draft
   is there to make you look at it. What CI also does is refuse a build whose
   version is wrong (below).
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

You do nothing for this. Three things worth knowing:

- **Its notes are the whole changelog**, re-published every time, because the
  `dev` release is deleted and recreated on each push. That is the shape the
  accumulating changelog is for — the page answers "what is new since the last
  release you installed on purpose" — but nothing on it marks what is new in
  *this* dev build. The build number and the commit on the first line are what
  tell two dev builds apart.
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
   than a prerelease, marked latest, with **`CHANGELOG.md` as the release
   notes**, `SHA256SUMS`, and a push notification to `app_release`. The rolling
   `dev` prerelease is left alone. Check the changelog *before* tagging: it is
   the release body, and no check runs on a tag push — `ci.yml` triggers on a
   push to `main` and on pull requests only.
4. **Open the next cycle immediately.** The release run opens a draft pull
   request that bumps `pubspec.yaml` and resets the changelog; set the version
   and merge it. This is not optional — see below.

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

**The release run opens a pull request that does both of these**, bumping
pubspec to the next minor and resetting the changelog - see
[The bot that opens the next cycle](#the-bot-that-opens-the-next-cycle).
Read it, change the version if this cycle is a patch or a major, merge. That is
the whole release-day job, and `main` is green on the merge.

By hand, if the bot is ever not what you want: make the bump the first commit
after the release, and **reset `CHANGELOG.md` in the same commit.** Its notes
have shipped, and `check_changelog.sh` refuses a version line that disagrees
with pubspec - so the two move together or `main` is red either way:

```markdown
## Main changes
- Version: 0.17.0
## Other changes
```

## The changelog

`CHANGELOG.md` is the release notes, and it holds **one** set: everything
since the last stable release, accumulating across the dev builds in between.
There is no "changes since 0.14.1" line, because a dev build is not a
predecessor anybody installed on purpose - the question the file answers is
"what is new since the last release", and the answer runs until the next one.

Write the entry **in the pull request that makes the change**, not at release
time. A release should be a tag on notes that are already written;
reconstructing six weeks of them from commit messages is how 0.12.1 ended up
with none at all.

The shape, which `check_changelog.sh` enforces:

```markdown
## Main changes
- Version: 0.16.0
- Tools: **A headline in bold** - what it does, and what it cost (by @mishamyte | PR #264 | Closes #142)
## Other changes
- Fixed: the smaller ones, same shape (by @apfxtech)
```

**A bullet is one line, however long.** The credit has to be the last thing on
it, so a bullet wrapped across two lines fails with "no well-formed credit" -
the guard reads line by line and cannot see a continuation.

- **Two sections.** `## Main changes` is what somebody would install the build
  for; `## Other changes` is everything else. `Main` bolds its headline.
- **`- ` bullets**, never `* `, and every bullet opens with an area and a
  colon - `Tools:`, `Archive:`, `Connection:`, `Fixed:`.
- **Every bullet credits somebody**, last on the line:
  `(by @user)`, plus `| PR #1` when there is one and `| Closes #2` or
  `| Fixes #2` when it closed an issue. Several are allowed - `PR #260, #261`.
  A change pushed straight to `main` has no pull request to cite and carries
  just the author. The form is unleashed-firmware's, which also uses
  `(OFW PR 4462 | by @kormax)` for something taken from upstream.
- **One author per bullet**, and the guard enforces it: `(by @a, @b)` and
  `(by @a | and @b)` are both refused. Two people's work is two bullets, which
  is what makes the credit worth reading.
- **Areas may carry a hyphen, a dot, a plus or a space** - `Sub-GHz:`,
  `Pixel Draw:` - but must start with a letter.

What the guard does **not** check is whether a pull request added an entry at
all. Most should not - a CI fix, a Crowdin sync, a submodule bump or a
test-only branch has nothing a user would read - and a gate that is wrong that
often needs a bypass label, which then gets used without being read. Judgement
stays with the author and the review.

## The bot that opens the next cycle

`open-next-cycle` in `auto-release.yml` runs after a release publishes, and
only for a release. It does four things:

1. Reads the version that was just published, from the build job's own output
   rather than a fresh derivation.
2. Computes **the next minor** - 0.16.0 becomes 0.17.0 - and writes it to
   `pubspec.yaml`, leaving every other line alone. **That digit is a guess**:
   four of the eight released transitions since 0.11.0 were patches. It is
   proposed because one of the two has to be, not because it is usually right.
3. Resets `CHANGELOG.md` to its three-line skeleton, in the same commit,
   because `check_changelog.sh` refuses a changelog whose version line
   disagrees with pubspec.
4. Pushes `chore/open-<version>` and opens a **draft** pull request assigned
   to you, titled "Open the 0.17.0 cycle - confirm the digit". A draft cannot
   be merged by reflex, which is the minimum friction that makes the choice
   real on the one day somebody wants `main` green in a hurry.

**It does not push to `main`,** and the first of these three reasons is the one
that decides it:

- The version is a person's call (fact 2). A minor bump is what this project
  almost always opens, so that is what gets proposed - but a proposal in a
  pull request can be changed to a patch or a major before it lands, and a
  commit pushed straight to `main` cannot.
- `main` is branch-protected, so a push would need a bypass or a personal
  token, granted to the workflow that holds the signing keys.
- A push can race a merge and half-apply, leaving the release published and
  the cycle unopened - the state it exists to clear.

So the release-day job is: read the pull request, change the version if this
cycle is not a minor, merge. `main` is green again on the merge.

Two things worth knowing:

- **The pull request carries no checks.** GitHub starts no workflow for an
  event the repository's own `GITHUB_TOKEN` caused. The release run therefore
  runs `check_changelog.sh` against the files before committing them, so the
  *changelog* is verified even though the pull request shows nothing — nothing
  re-runs `derive_version.sh`, so the pull request is not proven to unblock
  `main`. Closing and reopening it by hand starts the checks for free; a
  personal access token or a GitHub App token would do it automatically, at the
  cost of a credential in the release workflow.
- **`gh pr create` needs one repository setting**: Settings → Actions → "Allow
  GitHub Actions to create and approve pull requests". It is on for this
  repository; without it the step fails with "GitHub Actions is not permitted
  to create or approve pull requests" and leaves a pushed branch and no pull
  request.
- **Re-running a failed release re-runs this job.** It reuses an open pull
  request rather than opening a second one, and its push is *not* forced - so a
  version you edited on that branch survives the re-run. Once that pull request
  has merged a re-run fails this job on purpose: `main` is already unblocked,
  so the red is cosmetic.
- **It refuses rather than discarding a late note.** The release published the
  changelog as it stood at the tag, and this job works on `main`. A bullet
  merged while the five builds were running belongs to neither, so rather than
  reset over it the job stops and asks you to open the cycle by hand. Holding
  merges until the release run finishes avoids it entirely.

`open_next_cycle.sh` is the file-writing half and is tested on its own,
including that what it writes satisfies `check_changelog.sh`.

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

## The Linux runtime floor

A Flutter Linux app links against the host's GTK and GLib and ships neither, so
the oldest system the binary can start on is decided by the image it was
compiled on. `ubuntu-latest` is not a floor — it is whatever GitHub last
pointed that label at, and when it moved from 22.04 to 24.04 it took a
published asset with it: 0.11.2 could not start on Ubuntu 22.04, Mint 21.x,
Debian 12 or Ubuntu 23.10, because GLib 2.80 had added
`g_once_init_enter_pointer`, GObject's type machinery picks it up when compiled
against 2.80 headers, and 2.72 has never had it
([#280](https://github.com/DarkFlippers/qUnleashed/issues/280)).

So the Linux job pins `runs-on: ubuntu-22.04`, and `check_linux_abi.sh`
asserts the floor after every Linux build. `check_linux_abi.sh --print-floor`
prints the current numbers rather than repeating them here.

Two checks, because the ABI has two halves and neither substitutes for the
other:

| | |
|---|---|
| The build machine's GLib | GLib has no symbol versioning, so there is no general rule to apply to the finished binary — only a hand-maintained list of which symbol arrived in which release, which nobody is going to keep. The machine compiling it answers the same question in one number, and this is the half that catches #280. |
| The bundle's versioned references | glibc, libstdc++ and the C++ ABI do version their symbols, so the artifact states its own requirement and `objdump -T` is asked directly. |

**Raising the floor drops distributions**, so it is a release-note-worthy
decision and belongs in a commit of its own — one that edits the supported-systems
table in `README.md` in the same breath, because that table is the promise a
user reads and nothing checks it against the guard.

Two separate things will force the question, on different dates: GitHub
retiring the `ubuntu-22.04` runner label, and 22.04 leaving Ubuntu's standard
support in April 2027. Three ways out, in the order they cost:

1. **Build in an `ubuntu:22.04` container** on a newer runner. Keeps the promise
   exactly as it stands; costs the container setup on every Linux build.
2. **Set `GLIB_VERSION_MIN_REQUIRED` and `GLIB_VERSION_MAX_ALLOWED` to
   `GLIB_VERSION_2_72`** in `linux/CMakeLists.txt`, which sets neither today.
   That is the gate GObject uses to decide which symbol to emit, so it fixes
   the GLib half on a newer image — but only the GLib half. glibc, libstdc++
   and GTK's own `GDK_VERSION_MAX_ALLOWED` still come from the image, and the
   artifact check would still have to pass. Useful, not sufficient on its own.
3. **Raise the numbers** in `check_linux_abi.sh`, update the README table, and
   say in the release notes which systems stopped being supported.

## What is not automated yet

Honest list, so nobody waits for something that is not coming.

| | |
|---|---|
| Store uploads | Nothing uploads to TestFlight or the Play internal track. The ADR is shaped for it; the jobs do not exist. |
| The *decision* in the version bump after a release | `open-next-cycle` proposes a minor bump and opens the pull request; which digit moves is still a person's call (fact 2). |
| The R8 mapping | `sentry_dart_plugin` uploads dSYMs, PDBs and native symbols, but not Android's R8 mapping — that wants the Sentry Android Gradle Plugin, which is a change in `android/` that has not been made. Until it is, an obfuscated Android Dart trace is less readable than the other four platforms'. |
| Release commits in the submodules | Each Sentry release gets the app's commits automatically. [ADR 0013](adr/0013-observability-with-sentry.md) §3 wants flipperlib's and dartufbt's too, so a suspect commit can be found in a submodule; they go as event tags today, not as release commits. |
| `installerStore` | 0014 §1 wants the actual install source — TestFlight, Play, a sideload — read at runtime and reported. Not read anywhere yet. |

## Where each piece lives

| | |
|---|---|
| `.github/scripts/derive_version.sh` | The one place a trigger becomes a build identity: version, number, channel, three commits. Everything above is this script. |
| `.github/scripts/derive_version_test.sh` | Its tests. Run it directly; it needs no Flutter. |
| `.github/scripts/check_changelog.sh` | The changelog's shape, including that its version line agrees with pubspec. Its tests are beside it. |
| `.github/scripts/open_next_cycle.sh` | The pubspec bump and changelog reset the release-day pull request carries. Its tests are beside it. |
| `.github/scripts/check_linux_abi.sh` | The Linux runtime floor, checked after every Linux build. `--print-floor` states it. Its tests are beside it. |
| `.github/workflows/auto-release.yml` | The triggers, the five builds, the publish job, the rolling prerelease and the cycle opener. |
| `lib/services/build_identity.dart` | How the app reads what was compiled in, and formats it for a person. |
| `pubspec.yaml` | The version. Nothing else about the identity lives here — the build number is derived. |
