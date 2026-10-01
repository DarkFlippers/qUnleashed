# 0014. A build says what it is: version, channel and commit

Status: Proposed (2026-10-01)

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

### 2. `pubspec.yaml` on `main` holds the next release

After a release, CI bumps the minor version (0.13.0 → 0.14.0); a patch release
is a hand edit. A release tag must equal the pubspec version at its commit, or
the build fails.

Dev builds take their version from pubspec, which is the only place the next
version exists before its tag does.

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

### 6. Open: the build number

What it must be: unique per binary, rising across every channel, above 12001,
at most 2 100 000 000.

The candidate is `100000 + commit count × 10 + slot`, with the slot telling a
dev build from a release built at the same commit. It can be recomputed from
git, and needs `fetch-depth: 0`. GitHub's run number + offset is simpler, but
reruns reuse it, which collides after a partial upload.

Until this is decided the current formula stays.

## Rejected alternatives (and why)

**Promoting one binary through the channels.** The channel it was built with
would be wrong as soon as it was promoted, and a Play track cannot be read at
runtime to correct it.

**The channel or the commit inside the version string.** Apple refuses
anything but integers there.

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
- Until §6 is decided, tagging `dev-X` and `X` for the same version produces
  two binaries with one build number. Do not.

## Migration: what happens to legacy code

Existing tags and releases stay as they are. The first release after this
lands is the first under the new rule, and pubspec is bumped to the version
after it.
