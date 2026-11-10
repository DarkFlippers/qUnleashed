# 0017. The release ships two Android artifact kinds, so it runs R8 twice

Status: Accepted (2026-11-10).

Implemented. `.github/scripts/build/android.sh` builds both kinds,
`upload_r8_mapping.sh` sends both mappings, and `verify_apks.sh` holds the
invariant each one still has to satisfy.

Written because Play does not accept an APK for a new application, so the four
artifacts this release already built could not be submitted at all. The
decision that needed recording is not "also build a bundle" - it is everything
that follows from the fact that the bundle cannot come from the same build.

## 1. What forces two builds

AGP refuses to produce an App Bundle while ABI splits are enabled. Measured,
not read:

```
> Task :app:buildReleasePreBundle FAILED
Multiple shrunk-resources files found in directory
'.../shrunk_resources_proto_format/release/minifyReleaseWithR8':
[... -arm64-v8a-release.ap_, ... -armeabi-v7a-release.ap_,
 ... -universal-release.ap_, ... -x86_64-release.ap_]
Please disable building multiple APKs when building an Android app bundle.
```

([issuetracker 402800800](https://issuetracker.google.com/402800800), AGP
8.11.1.) The Gradle *task graph* for both is clean -
`gradlew :app:assembleRelease :app:bundleRelease --dry-run` lists
`minifyReleaseWithR8` exactly once - so the trap is that this looks possible
until it executes.

Note what this does **not** say. Two `flutter build` commands are two Gradle
invocations whatever the splits do, because the Flutter CLI has no subcommand
that asks for both outputs. Dropping splits would not by itself collapse the
runs; what would is one Gradle invocation requesting both, which needs splits
off *and* AGP to share its R8 task across the two packaging paths. §4 is that
alternative and its price.

## 2. Two R8 runs, so both mappings are uploaded

Each run writes its mapping to R8's own output name and the Sentry Gradle
plugin mints a UUID from that mapping's content, so each artifact carries the
identifier of the mapping it was built against. Uploading one of them, or one
under the other's UUID, is [#361](https://github.com/DarkFlippers/qUnleashed/issues/361)
with the symptom inverted: not an unreadable frame but a confidently wrong
name, which is worse because a wrong name is believed. The bundle is what Play
installs, so that half would be every store user.

So `android.sh` keeps both mappings and `upload_r8_mapping.sh` sends both,
each under the UUID read out of the artifact it describes, reporting each half
separately - the halves fail independently, and a summary saying only
"uploaded" would hide which one is unreadable.

Measured on a full local release: R8 ran twice (`mapping.txt`'s mtime moved
past the copy's) and wrote byte-identical mappings both times, so both
artifacts carried the same UUID and the two uploads sent one mapping twice.
That is a property of that build, not a guarantee.

**What pairs a mapping with a UUID is content, not freshness.** The checks in
`android.sh` are therefore existence checks, deliberately: a mapping that was
not rewritten still pairs correctly with the UUID beside it, while a `-nt`
comparison would fail a release whose second R8 run legitimately produced
identical bytes. This is written down because it reads like an oversight and
two reviewers proposed the freshness check.

## 3. What each kind still has to satisfy

`verify_apks.sh` checks both, and stays one script: the UUID invariant has to
see every artifact at once, and nothing split across two scripts can assert
it. A bundle holds the same contents one level in, under `base/`, so the entry
paths are per kind - and only `base/`, because this app has no feature
modules.

The invariant splits where the builds do. The four APKs come from one
invocation and must agree on one UUID; the bundle has its own, and that is the
design rather than a defect. Equality across kinds is not asserted in either
direction.

The bundle is **not** a GitHub release asset. An `.aab` cannot be sideloaded,
so publishing one beside the APKs would invite a download nobody can install.
It is kept out structurally rather than by a filter in each consumer: the
filename has no second underscore (`_android.aab`), so no `*_android_*` glob
in the repository can reach it, and it is uploaded under a CI artifact name
`publish`'s `release-assets-*` pattern does not match - which is also what
keeps it out of `SHA256SUMS`, a file that hashes whatever is in `dist/`.

## 4. Rejected: drop the per-ABI APKs

The alternative that would collapse this back to one R8 run: stop asking for
ABI splits, and request `assembleRelease bundleRelease` from one Gradle
invocation. The `splits`/`isUniversalApk` block and its `ndk.abiFilters`
interlock both disappear, `verify_apks.sh` drops from five artifacts to two,
and `upload_r8_mapping.sh` loses its two-half machinery entirely.

Rejected for now, on price rather than on doubt: the per-ABI APKs are a
release asset users choose, roughly 40% smaller than the universal one for
their device, and sideloading is how most of this app's users install it.
Taking them away is a release-note decision, not a build cleanup.

It is also not fully measured. `--dry-run` shows one `minifyReleaseWithR8` for
the pair, but whether AGP really shares that task's output across both
packaging paths in execution has not been tested with splits off.

**What would change the answer:** Play becoming the install path most users
take, or a measurement showing the single invocation works - at which point
the saving is one whole Android build per release plus every line this ADR
exists to justify.

## 5. Where the pieces live

| | |
|---|---|
| Both builds, both mappings kept | `.github/scripts/build/android.sh` |
| The names three scripts must agree on | `.github/scripts/android_artifacts.sh` |
| Both mappings uploaded, per-half reporting | `.github/scripts/upload_r8_mapping.sh` |
| What a publishable artifact satisfies | `.github/scripts/verify_apks.sh` |
| The 16 KB page-size half of that | `.github/scripts/elf_page_align.py` |
| What a maintainer does about any of it | [`docs/releasing.md`](../releasing.md) |
