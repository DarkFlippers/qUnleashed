# 0014. A build says what it is: version, channel and commit

Status: Proposed (2026-10-01); the version is SemVer and §6 is settled
(2026-10-05)

Written for [0013](0013-observability-with-sentry.md), which needs every
event to name the binary it came from. The CI this is shaped for — a dev build
on every push to `main`, uploaded to TestFlight and the Play internal track —
does not exist yet; this decision is what keeps it from having to change
twice.

## Context

**The tag is the version.** `derive_version.sh` reads `0.12.1` out of
`dev-0.12.1` and derives the code `12001` from it
(`major × 1 000 000 + minor × 1 000 + patch`). `pubspec.yaml` is set to the
released version afterwards, by `sync-version`, so during a build it still
holds the previous one.

**Three places read the tag, and they do not agree.** `derive_version.sh`
takes the version; the publish job treats `dev-*` as a prerelease and anything
else as latest; `AppVersionLabel` has its own regex for the prefix. Every tag
so far is `dev-*` or `beta-*`, so `beta-*` has been what GitHub calls latest.

**No build carries its commit.** Nothing in the binary, the About screen or a
copied log says which commit it was built from.

**What the target imposes:**

- Apple's version string is one to three integers, and once a version is
  released, TestFlight refuses further builds of it. A dev build made after
  0.13.0 ships has to call itself 0.13.1 or 0.14.0 — a version no tag names
  yet.
- Android's `versionCode` has to rise with every build anyone installs. Under
  the current formula every commit between two tags gets the same one.
- `dev-0.12.1` has been sideloaded with `versionCode` 12001, and Android will
  not install a lower code over it.

## Decision

### 1. Each channel gets its own build

A push to `main` builds `dev`; a release tag builds `release`. A stable binary
is rebuilt from its tag, not promoted from a dev one.

Until per-commit builds exist, the tag prefix decides: `dev-*` is `dev`,
`beta-*` is `release`.

The channel is compiled in (`QU_CHANNEL`) and becomes Sentry's `environment`.
Where the build is actually running — TestFlight, App Store, Play, F-Droid, a
sideload — is read at runtime from `PackageInfo.installerStore` and sent as a
tag beside it.

### 2. The version is SemVer, and `pubspec.yaml` on `main` holds the next one

The version name means what SemVer says it means. While the app is pre-1.0,
that is: minor for a release, patch for a fix to one. `0.14.1` is "0.14.0 with
a fix", not "one commit after 0.14.0".

**SemVer's own answer for a dev build cannot be used.** A pre-release is
`0.15.0-dev.23`, which sorts below `0.15.0` - exactly the right meaning, and
illegal on iOS, where the short version string is one to three integers and
nothing else. So the fact that a build is a dev build lives in the channel
(§1) and the build number (§6), never in the name.

What follows is the ordinary shape for a mobile app, and it is what makes the
guard below hold rather than fail:

- `pubspec.yaml` on `main` holds the version being built **toward**. After
  releasing 0.14.0, CI sets it to 0.15.0; a fix series is a hand edit to
  0.14.1.
- Every dev build in a cycle is named that version. They are told apart by
  their build number and their commit, not by their name - `0.15.0 (107810,
  abc1234)` and `0.15.0 (107930, def5678)` are two different binaries and say
  so.
- A release tag equals the pubspec version at its commit, or the build fails.
  Under this scheme that is satisfied by construction, because pubspec already
  holds the version being released.

That last point is why the guard is written this way round. It would have
failed the release of 2026-10-01: `dev-0.13.0` points at `9ff711f`, where
pubspec still said `0.12.1+12001`, because `sync-version` wrote the version
*after* publishing. Holding the next version rather than the last one puts the
bump before the tag instead of after it, and the guard then checks something
that is already true.

Apple's rule is the reason this works rather than a problem to be worked
around: many TestFlight builds may share one short version, each with a higher
`CFBundleVersion`, and a short version is only closed to further builds once
it has been *released* on the App Store - which is the moment pubspec moves
on.

### 3. The commit is compiled in

`QU_COMMIT`, plus the flipperlib and dartufbt commits. They appear on the
About screen, on the first line of a copied log, and as tags on every Sentry
event. Each Sentry release is given its commits in all three repositories, so
a suspect commit can be found in a submodule as well.

### 4. One script derives all of it

`derive_version.sh` grows into the one place that turns a trigger into a build
identity: version, build number, channel, commit, Sentry release name. Every
job reads its outputs — the publish job's `dev-*` check and
`AppVersionLabel`'s regex go — and its tests cover each.

### 5. The Sentry release is `qunleashed@<version>+<build number>`

Set explicitly, never left to the SDK, whose default starts with the
application ID or bundle ID and would split one release into five platforms.
`dist` is the build number.

### 6. The build number is `100000 + commit count × 10 + slot`

Settled, because §2 forces it. Every dev build in a cycle shares one version
name, so the name carries no ordering at all and the build number has to carry
every bit of it. The old formula derived the code *from* the semver
(`major × 1 000 000 + minor × 1 000 + patch`), which would hand every dev build
in a cycle the same number - it fails on the second build of a cycle rather
than after a thousand commits.

So the name and the number are decoupled. The name is for people; the number
is a counter and means nothing else.

```
build number = 100000 + <commits on main> × 10 + slot
slot = 0            for a dev build
slot = run_attempt  for a release build (1, 2, … 9)
```

At 781 commits that is **107810** for a dev build and **107811** for the
release of the same commit. Every code ever shipped is below 13000, so the
floor clears them with room to spare, and the 2 100 000 000 ceiling Android
imposes is 210 million commits away.

Why each piece:

- **`100000 +`** clears every historical code in one step, so nothing has to
  remember what the highest shipped number was. (That floor is why the earlier
  draft of this section said "above 12001"; it is 13000 now, and would have
  gone stale again at every release. Not depending on it is the point.)
- **`× 10`** leaves ten slots per commit, which is what lets two builds of one
  commit differ. A bare commit count cannot do that, and a release is
  frequently tagged at a commit a dev build has already been made from.
- **`slot = run_attempt` for a release** means re-running a failed release job
  produces a fresh number rather than one the store has already refused. A
  dev re-run does collide, deliberately: a dev build is disposable - the
  rolling prerelease is overwritten anyway - and the fix is another commit.
- **Recomputable from git**, so any commit can state the number it would build
  as. It needs `fetch-depth: 0`.

**GitHub's `run_number` was weighed and not taken.** It is simpler - no deep
fetch, monotonic by construction, and distinct per build without a slot - and
`ChameleonUltraGUI` ships exactly that, naming iOS and macOS builds
`1.3.${{ github.run_number }}` straight from it. Two things decided against
it: a re-run reuses the number, which is the collision this formula's slot
exists to avoid, and `run_number` is counted per workflow *file*, so renaming
or recreating the file resets it to 1 - below everything already shipped, with
no cheap guard.

What this scheme does borrow from that project is §7.

### 7. Dev builds go to one rolling prerelease

A push to `main` builds, and the artifacts replace the assets of a single
GitHub prerelease tagged `dev`. One tag, one link to bookmark, no history.
Release tags get real releases as they do now.

Taken from `ChameleonUltraGUI`, which does this alongside its per-run store
uploads. The alternative shapes are worse in obvious ways: a release per push
is a release per commit on the releases page and a push notification with it,
and artifacts-only leaves the `app_dev` FCM topic with no URL to point at and
requires a GitHub account to download.

The channel step in `auto-release.yml` already distinguishes `dev-*` from
everything else for exactly this notification, so the topic and body it
chooses are unchanged.

## Rejected alternatives (and why)

**Promoting one binary through the channels.** The channel it was built with
would be wrong as soon as it was promoted, and a Play track cannot be read at
runtime to correct it.

**The channel or the commit inside the version string.** Apple refuses
anything but integers there. This also rules out SemVer's own pre-release
form, `0.15.0-dev.23`, which would otherwise be the right way to say it - see
§2.

**Patch as a count of commits since the last release.** It reads well -
`0.14.178` is "178 commits in" - and works with the old formula untouched,
because the name happens to rise monotonically. It was rejected for taking the
patch field: a fix to a shipped 0.14.0 has nowhere to go, since `0.14.1` is
already the name of a dev build. It also bounds a cycle at 1000 commits, which
the old formula would otherwise carry silently into the next minor, and leaves
two builds of one commit sharing a number.

**The tag as the source of the version.** A push to `main` has no tag, and
TestFlight closes a version once it has shipped.

**The channel as a semver prerelease in the Sentry release name**
(`0.14.0-dev+…`). A unique build number already makes the release unique, and
`environment` already carries the channel.

## Consequences

- `sync-version` changes from "set to the released version" to "bump to the
  next one".
- `AppVersionLabel` reads `QU_CHANNEL` and stops parsing the tag.
- `sentry_dart_plugin`'s default release, which is read from pubspec, becomes
  right. It is still passed explicitly.
- Tagging two channels at one version is no longer a hazard: §6's slot gives
  them different numbers. What remains is that they would share a *name*, so
  the channel on the About screen is what tells them apart.
- `derive_version.sh` stops deriving the number from the name. Its component
  arithmetic goes, and with it the overflow that let `0.1.1000` and `0.2.0`
  produce one code. Its regex should still be anchored: `beta-0.14.0-rc1`
  currently builds as `0.14.0`, silently claiming the identity of a release it
  is not.
- `fetch-depth: 0` on every job that derives a version.

## Migration: what happens to legacy code

Existing tags and releases stay as they are. The first release after this
lands is the first under the new rule, and pubspec is bumped to the version
after it.

Concretely from where the tree is now: `dev-0.13.0` shipped with code 13000
and pubspec says `0.13.0+13000`. Landing this sets pubspec to the version being
built toward - `0.14.0` - and from then on a push to `main` builds `0.14.0`
with a number from §6, which at 781 commits starts at 107810. Nothing has to
be renumbered, because the floor was chosen to clear 13000.

The prefix convention outlives the scheme that needed it. `dev-*` and `beta-*`
still pick the channel until a push to `main` is what makes a dev build, and
§1 already says the tag prefix decides until then.
