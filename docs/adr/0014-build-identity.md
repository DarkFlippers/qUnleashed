# 0014. A build says what it is: version, channel and commit

Status: Proposed (2026-10-01); the version is SemVer and §6 is settled
(2026-10-05); the `-dev` suffix is kept wherever a person reads the version
and dropped only from the two fields a store validates, and the automatic
version bump is replaced by two guards (2026-10-08)

Written against three needs, stated in that order of certainty: release builds
cut on SemVer when the team decides, dev builds published automatically from
every commit on `main` (and later to the stores), and an executable that can
say which version and which commit it is. §2 is what makes the second possible
at all - until the version comes from `pubspec.yaml`, a push to `main` has no
tag to derive one from and `derive_version.sh` refuses to run.

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
else as latest; `AppVersionLabel` has its own regex for the prefix. Of 56 tags, 22 are
`alpha-`, 22 `beta-`, 7 `dev-` and 5 `wip-`, so everything but the
seven `dev-*` has been what GitHub calls latest.

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

**SemVer's own answer cannot go in the field iOS reads.** A pre-release is
`0.15.0-dev.23`, which sorts below `0.15.0` - exactly the right meaning, and
illegal in `CFBundleShortVersionString`, which may hold digits and periods and
at most three integers. A build carrying it fails validation with the rule
quoted back: *the value '1.13.1-dev' in the Info.plist file must be a
period-separated list of at most three non-negative integers*. A fourth
integer trips the same check. Android would take it; iOS and macOS will not,
and that is the binding constraint.

**But that rule governs one field, and this decision first over-generalised
it** to "never in the name at all" (corrected 2026-10-08). The suffix is kept
everywhere a person reads the version and dropped from the one place a store
validates:

| Where | What it says |
|---|---|
| `--build-name` → `CFBundleShortVersionString` | `0.15.0` — digits and periods, always |
| `--build-number` → `CFBundleVersion` | `108080` |
| The version line on the Tools screen | `0.15.0-dev (108080 · abc1234)` |
| The head of a copied log | `qUnleashed 0.15.0-dev · 108080 · abc1234` |
| The Sentry release (§5) | `qunleashed@0.15.0-dev+108080` |

So a dev build is explicit about being one wherever that helps somebody, and
the platform never sees the suffix. The channel (§1) and the build number (§6)
still carry it for anything that has to compare versions numerically.

What follows is the ordinary shape for a mobile app, and it is what makes the
guard below hold rather than fail:

- `pubspec.yaml` on `main` holds the version being built **toward**. Moving it
  is a commit somebody makes on purpose — see "the bump is a decision" below.
- Every dev build in a cycle is named that version. They are told apart by
  their build number and their commit, not by their name - `0.15.0 (108080,
  abc1234)` and `0.15.0 (107930, def5678)` are two different binaries and say
  so.
- A release tag equals the pubspec version at its commit, or the build fails.
  Under this scheme that is satisfied by construction, because pubspec already
  holds the version being released.
- **A build whose version has already been released fails too.** That is the
  second guard, and the next section is why it is needed.

**The bump is a decision, so it is not automated** (corrected 2026-10-08).
This section first said CI sets pubspec to 0.15.0 after releasing 0.14.0. That
guesses: a release is as often a patch, and occasionally a major, and no rule
over the previous version knows which. Choosing is the work; writing one line
is not.

So moving pubspec is a commit — "open the 0.16.0 cycle" — reviewable like any
other, and CI never picks a digit. What CI does instead is refuse to build a
version that has already shipped.

That check exists because dropping the automatic bump opens a real hole:
release 0.15.0, forget to bump, and the next dev build is named 0.15.0 as
well. TestFlight then refuses it, because that short version has been
released - days later, far from the commit that caused it, and reported as a
store problem rather than a versioning one. The check turns that into a red
build on the commit itself.

Which leaves CI automating the two things a rule can actually settle - a tag
that disagrees with pubspec, and a version that has already gone out - and
leaves the choice of digit to the person making it.

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

### 5. The Sentry release is `qunleashed@<version>[-dev]+<build number>`

Set explicitly, never left to the SDK, whose default starts with the
application ID or bundle ID and would split one release into five platforms.
`dist` is the build number.

The `-dev` on a dev build is §2's suffix, and it reverses a rejection further
down (2026-10-08). The rejection was not wrong about the mechanics - a unique
build number already makes a release unique, and `environment` already carries
the channel - it just weighed the wrong thing. In a release list,
`qunleashed@0.15.0+108080` against `qunleashed@0.15.0+108081` says nothing
until each one's environment is opened, and that list is the one most often
read. With the suffix a dev build and the shipped `0.15.0` never look alike.
It costs nothing, since Sentry's release is a free-form string.

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

At 808 commits that is **108080** for a dev build and **108081** for the
release of the same commit. The floor clears every code ever shipped with room
to spare, and the 2 100 000 000 ceiling Android imposes is 210 million commits
away.

Why each piece:

- **`100000 +`** clears every historical code in one step, so nothing has to
  remember what the highest shipped number was. Earlier drafts of this section
  quoted that high-water mark — "above 12001", then "below 13000" — and it was
  wrong again by the time this was written, because 0.14.1 shipped as 14001 in
  the meantime. Not depending on it is the whole point; the Migration section
  names the figure once, where it is actually load-bearing.
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

**The channel or the commit inside the version string Apple reads.** It
refuses anything but digits and periods there, so SemVer's own pre-release
form - `0.15.0-dev.23`, which would otherwise be exactly the right way to say
it - cannot go in `CFBundleShortVersionString`.

What this first concluded from that, and got wrong, is that the suffix cannot
appear anywhere. It can appear in every field a person reads; §2 now says
where, and only the two platform fields stay numeric.

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
(`0.14.0-dev+…`). Declined on the grounds that a unique build number already
makes the release unique and `environment` already carries the channel —
**adopted on 2026-10-08**, because that reasoning weighed uniqueness when the
thing that matters is reading a release list at a glance. §5 has it.

## Consequences

- `sync-version` **goes.** It set pubspec to the version just released, which
  is the thing §2 reverses, and nothing takes its place: the bump is a commit
  now. What replaces it is a check that a build's version is not one already
  published.
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
- `fetch-depth: 0` on every job that derives a version — the three build jobs
  and `publish`. `guard` takes it only on a dispatch, which is the one trigger
  whose check reads history.
- A push to `main` now builds five platforms, so the trigger carries a
  `paths-ignore` for documentation and store metadata. Translations are **not**
  in it: they are compiled in, so a translation-only push changes the binary.
- Not taken, and worth knowing about: the identity could be derived once in
  `guard` and passed to the build jobs as outputs, saving three full-history
  clones per push. Declined because the drift it would prevent does not exist —
  all three jobs check out the same commit, read the same pubspec and tags, and
  see the same run attempt, so they agree by construction — and because it
  moves release plumbing for a clone that is cheap beside a 500-second build.

## Migration: what happens to legacy code

Existing tags and releases stay as they are. The first release after this
lands is the first under the new rule, and pubspec is bumped to the version
after it.

Concretely from where the tree is now, 2026-10-08: the newest tag is
`dev-0.14.1` and pubspec says `0.14.1+14001`, so pubspec already names a
version that has gone out. Landing this is therefore one commit that opens the
next cycle — `0.15.0`, or `0.14.2` if the next release is meant to be a fix —
and from then on a push to `main` builds that version with a number from §6,
which at 808 commits starts at 108080. The second guard in §2 is what would
have caught the state the tree is in right now.

Nothing has to be renumbered: every code ever shipped is at or below 14001 and
§6's floor of 100000 clears it.

The prefix history matters for one reason. Of 56 tags, 22 are `alpha-`, 22
`beta-`, 7 `dev-` and 5 `wip-`, and `dev-` was how a dev build was made before
`main` built on its own — so the prefix has never reliably meant the channel.
Now that `dev` is the name of the single rolling prerelease (§7), a `dev-*` tag
would collide with it outright: it would resolve to the dev channel, delete and
recreate that prerelease, and leave its own tag with no release and no assets.
So `derive_version.sh` refuses a `dev-*` tag, and §1's channel comes from the
trigger rather than from any prefix.

The cost is that the seven versions already published under `dev-*` can never
be rebuilt. That is acceptable: they are published, and the guard in §2 exempts
only the tag being rebuilt, which from now on is the version itself.

The prefix convention outlives the scheme that needed it. `dev-*` and `beta-*`
still pick the channel until a push to `main` is what makes a dev build, and
§1 already says the tag prefix decides until then.
