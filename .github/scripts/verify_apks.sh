#!/usr/bin/env bash
# Checks that the built Android APKs actually contain a working application
# before the release publishes them.
#
#   verify_apks.sh [directory]   # default: dist
#
# Two things that a green build does not tell you: that the APK can run, and
# that a crash in it can be read.
#
# The build only ever checked that the files exist, and so did the upload. An
# APK missing lib/<abi>/libapp.so - the Dart snapshot - builds green, installs,
# and dies at launch. CopyFlutterJniLibsTask in the Flutter SDK documents two
# regressions that dropped libapp.so from the APK (flutter#186810, #187388), and
# its copy step silently stages nothing when the per-ABI directory is missing or
# empty, so the shape is reachable without anything failing.
#
# Integrity is checked first and separately, because `unzip -Z` reads only the
# central directory: an APK whose entry data is truncated or zeroed still lists
# every expected name. `unzip -t` is what actually reads the bytes.
#
# The third thing a green build does not tell you is that the native libraries
# can be loaded at all on a current device. Play requires an app targeting
# Android 15 or later to support 16 KB memory pages, and `targetSdk` comes
# from the pinned Flutter (`flutter.targetSdkVersion`, 36 today), so the
# requirement applies. A `.so` linked with a 4 KB max-page-size dies at
# `dlopen` on a device running 16 KB pages, and for `libapp.so` that is
# launch. `android/build.gradle.kts` pins the NDK for everything built from
# source here, so what this is really for is the prebuilt libraries a
# dependency ships, which no build setting can realign; `elf_page_align.py`
# holds that reasoning. `elf_page_align_test.sh` covers the parser directly,
# and what is covered here is the wiring.
#
# The expected ABIs come from android_abis.sh, shared with android.sh so the
# names it writes and the names checked here cannot drift apart.
#
# It covers both artifacts a release builds: the standalone APKs, which is
# what a sideload installs, and the App Bundle, which is what Play installs
# and therefore what every store user gets. A bundle holds the same things one
# level in, under its base module, so the entry paths are per kind rather than
# shared - and only the base module, because this app has no feature modules.
# `elf_page_align.py` holds what to decide on the day it gains one.
#
# One script and not two, because the UUID check at the bottom has to see
# every artifact at once: the four APKs must agree with each other, and the
# bundle must be *excluded* from that comparison rather than merely absent
# from it. Neither half of that can be asserted from a script that sees only
# one kind. The bottom of this file has the reasoning.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=android_abis.sh
. "$HERE/android_abis.sh"
# The artifact names and the per-kind entry paths, shared with the build and
# the uploader so a glob cannot drift in one of the three. ADR 0017.
# shellcheck source=android_artifacts.sh
. "$HERE/android_artifacts.sh"

# A real snapshot is multiple megabytes. This only has to be large enough to
# reject an empty or stub file and small enough never to reject a real one.
MIN_SNAPSHOT_BYTES=1048576

# The identifier that ties an APK to an R8 mapping, shared with
# `upload_r8_mapping.sh` so the gate and the uploader cannot disagree about it.
#
# Checked here because nothing else can see it go missing: R8 renames every
# Java and Kotlin frame whether or not this is present, the build is green
# either way, and the only other symptom is a crash report that arrives as
# `w2.r.k` months later - which is #343, three releases long. The plugin skips
# a variant it does not consider minified and says nothing at all about it,
# not even at `info`, so "the plugin is configured" and "this APK can be
# deobfuscated" are different facts and this is the only place that can tell
# them apart.
#
# One case this refuses that it arguably should not: a build with
# `-Pshrink=false`, where R8 never runs, so there is nothing to deobfuscate and
# no UUID to carry. Nothing in CI passes it - `derive_version.sh` puts only
# `--build-name`, `--build-number` and the dart-defines into
# `QUNLEASHED_FLUTTER_BUILD_ARGS` - so it takes a person running `android.sh`
# by hand. Said here rather than taught to the code, which would give a
# `dist`-only script a second input for one hypothetical.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=sentry_proguard_uuid.sh
. "$HERE/sentry_proguard_uuid.sh"

dir="${1:-dist}"
failures=0

# The alignment check's stderr, kept out of its stdout; the block below says
# why. One file for the whole run, truncated per artifact, so a `dist/` of
# four does not leave four behind.
stderr_file="$(mktemp)"
trap 'rm -f "$stderr_file"' EXIT

fault() {
  echo "::error::$1" >&2
  failures=$((failures + 1))
}

shopt -s nullglob
# `_android.aab` has no second underscore, which is what keeps the bundle out
# of every `*_android_*` glob in this repository - including the one beside it
# here, the release-asset upload and `action-gh-release`'s file list.
artifacts=("$dir"/$ANDROID_APK_GLOB "$dir"/$ANDROID_BUNDLE_GLOB)
if (( ${#artifacts[@]} == 0 )); then
  echo "::error::No Android artifacts found in $dir." >&2
  exit 1
fi

declare -A seen_abi=()
declare -A seen_uuid=()

for file in "${artifacts[@]}"; do
  name="$(basename "$file")"
  before=$failures

  # Both the expected ABIs and the artifact's identity come from the name.
  case "$name" in
    *_android.aab | *_android_universal.apk)
      # Everything, in one artifact. The loop at the bottom is what counts
      # them; this only has to say which ABIs to expect inside.
      want=("${ANDROID_ABIS[@]}")
      ;;
    *)
      abi="${name##*_android_}"
      abi="${abi%.apk}"
      if printf '%s\n' "${ANDROID_ABIS[@]}" | grep -qxF -- "$abi"; then
        want=("$abi")
        seen_abi["$abi"]=1
      else
        fault "$name does not match any known Android artifact name."
        continue
      fi
      ;;
  esac

  # Where each thing lives, which differs by kind rather than by a prefix: an
  # APK has `AndroidManifest.xml` and `classes.dex` at its root, a bundle has
  # `base/manifest/AndroidManifest.xml` and `base/dex/classes.dex`.
  case "$name" in
    *.aab)
      manifest="$BUNDLE_MANIFEST_ENTRY"
      dex="$BUNDLE_DEX_ENTRY"
      sentry_asset="$SENTRY_UUID_ASSET_BUNDLE"
      lib_root="$ANDROID_BUNDLE_MODULE/lib"
      ;;
    *)
      manifest="$APK_MANIFEST_ENTRY"
      dex="$APK_DEX_ENTRY"
      sentry_asset="$SENTRY_UUID_ASSET"
      lib_root="lib"
      ;;
  esac

  # Reads the entry data and checks every CRC, which the listing below does not.
  if ! err="$(unzip -tqq "$file" 2>&1)"; then
    fault "$name failed its integrity check: ${err:-no detail}"
    continue
  fi

  if ! listing="$(unzip -Z1 "$file" 2>&1)"; then
    fault "$name could not be listed: ${listing:-no detail}"
    continue
  fi

  grep -qxF -- "$manifest" <<<"$listing" \
    || fault "$name has no $manifest."
  grep -qxF -- "$dex" <<<"$listing" \
    || fault "$name has no $dex."

  # Present is not the same as populated here either: the plugin writes the
  # file whenever any of its features is on, and only the mapping's UUID makes
  # it mean anything.
  if ! grep -qxF -- "$sentry_asset" <<<"$listing"; then
    fault "$name has no $sentry_asset - nothing ties it to an R8 mapping, so its Java frames will not deobfuscate."
  else
    uuid="$(sentry_proguard_uuid "$file" "$sentry_asset")"
    if [[ -z "$uuid" ]]; then
      fault "$name carries $sentry_asset with no io.sentry.ProguardUuids in it."
    elif [[ "$name" != *.aab ]]; then
      # The bundle's own UUID is deliberately not collected: the comparison
      # below is the APKs' alone, for the reason stated where it happens.
      seen_uuid["$uuid"]=1
    fi
  fi

  for abi in "${want[@]}"; do
    if ! grep -qxF -- "$lib_root/$abi/libapp.so" <<<"$listing"; then
      fault "$name has no $lib_root/$abi/libapp.so - the Dart snapshot is missing."
      continue
    fi
    # Present is not the same as populated: a truncated or stub snapshot is
    # still an app that dies at launch.
    bytes="$(unzip -p "$file" "$lib_root/$abi/libapp.so" | wc -c)"
    if (( bytes < MIN_SNAPSHOT_BYTES )); then
      fault "$name has a $bytes-byte $lib_root/$abi/libapp.so; expected at least $MIN_SNAPSHOT_BYTES."
    fi
  done

  # 16 KB pages, per artifact rather than once: the universal APK and the
  # per-ABI splits are packed separately, and a split is what a device
  # installs. `want` and not `found` on purpose - an ABI the APK should not
  # carry is the fault reported below, and reporting its alignment too would
  # bury that under a second message about a library that has no business
  # being there.
  #
  # Three outcomes: could not run, ran and wrote to stderr, ran and found
  # something. Each has its own fault string and its own case in the suite.
  #
  # Stderr goes to its own file rather than into the capture, because folded
  # in with `2>&1` it was the bug it looks like a shortcut for: the helper
  # writes nothing there on success today, but one `DeprecationWarning` from a
  # newer runner image - or a `PYTHONWARNINGS` in the environment - turned a
  # clean APK into a confident wrong diagnosis about a library that will not
  # load. Measured with `PYTHONVERBOSE=1`, which reported CPython's own import
  # trace as offending libraries.
  : > "$stderr_file"
  status=0
  aligned="$(python3 "$HERE/elf_page_align.py" "$file" "${want[@]}" 2>"$stderr_file")" || status=$?
  noise="$(tr '\n' ' ' < "$stderr_file")"
  if (( status != 0 )); then
    partial=""
    [[ -n "$aligned" ]] && partial=" (it had already reported: $(tr '\n' ' ' <<<"$aligned"))"
    fault "$name could not be checked for 16 KB page alignment: ${noise:-no detail}$partial"
  elif [[ -n "$noise" ]]; then
    fault "$name's 16 KB page check exited 0 but wrote to stderr, so its silence is not a pass: $noise"
  elif [[ -n "$aligned" ]]; then
    while IFS= read -r line; do
      fault "$name has a library that will not load on a 16 KB page device - $line"
    done <<<"$aligned"
  fi

  # A split carrying an ABI it should not have means the split did not happen.
  # `|| true` because no lib/ entries at all is a fault reported above, not a
  # reason to abandon the remaining artifacts.
  found="$(grep -oE "^$lib_root/[^/]+/" <<<"$listing" \
    | awk -F/ '{print $(NF-1)}' | sort -u || true)"
  for abi in $found; do
    printf '%s\n' "${want[@]}" | grep -qxF -- "$abi" \
      || fault "$name carries an unexpected ABI: $abi."
  done

  if (( failures == before )); then
    echo "  ok  $name (${want[*]})"
  fi
done

# The build hard-fails on a missing artifact, but this is the gate that is meant
# not to trust the build.
# EXACTLY one universal APK and exactly one bundle - both halves of that, in
# one loop, because a boolean can only say "at least one".
#
# Play does not accept an APK for a new application, so a release missing the
# bundle cannot be submitted at all; and more than one of either is a leftover,
# because nothing clears `dist/` between local runs. `upload_r8_mapping.sh`
# would then read a UUID off whichever sorted first - for a version number the
# OLDER one, systematically - and file a fresh mapping under it while
# reporting success. The APK half of that is caught by the UUID comparison
# below as well; the bundle is exempt from it by design, so for the bundle
# this is the only thing in front of it.
for kind in "universal APK|$ANDROID_UNIVERSAL_GLOB" "App Bundle|$ANDROID_BUNDLE_GLOB"; do
  label="${kind%%|*}"
  matched=("$dir"/${kind#*|})
  if (( ${#matched[@]} == 0 )); then
    fault "No $label in $dir."
  elif (( ${#matched[@]} > 1 )); then
    fault "$dir holds ${#matched[@]} ${label}s (${matched[*]##*/}); a release produces exactly one, so the rest are leftovers from another build."
  fi
done
for abi in "${ANDROID_ABIS[@]}"; do
  [[ -n "${seen_abi[$abi]:-}" ]] || fault "No $abi APK in $dir."
done

# The APKs come from one Gradle invocation, so one R8 run, so one UUID - and
# that is checked rather than trusted. The shape it guards against is cheap to
# reintroduce and silent when it happens: `android.sh` used to build the APKs
# twice, R8 wrote over the same `mapping.txt` both times, and the upload sent
# one of them under a UUID read out of an APK built by the other. Then the
# artifacts from the losing run carry a UUID with nothing behind it, and the
# ones that do resolve resolve against a mapping describing different bytes -
# confident wrong names, which are worse than `w2.r.k` because a wrong name is
# believed. #361.
#
# So this is what would notice the two-build shape coming back, or a stale
# `app-release.apk` left in `build/` by an earlier local run being copied in
# beside freshly built splits.
if (( ${#seen_uuid[@]} > 1 )); then
  fault "The APKs in $dir carry ${#seen_uuid[@]} different R8 mapping UUIDs (${!seen_uuid[*]}); each needs its own mapping uploaded, and only one is."
fi

# The bundle is deliberately NOT part of that comparison, and the reason is
# not neglect. AGP refuses to build an App Bundle while ABI splits are enabled
# - "Please disable building multiple APKs when building an Android app
# bundle", issuetracker 402800800 - so the bundle cannot come from the
# invocation that makes the four APKs. Two invocations are two R8 runs and
# therefore possibly two UUIDs: above, two UUIDs mean a bug; here a second one
# is the design. What makes that safe is `upload_r8_mapping.sh` sending BOTH
# mappings, each under the UUID of the artifact it describes.
#
# Equality is not asserted either way. R8 is deterministic, so two runs over
# the same inputs can write the same mapping and mint the same UUID - measured
# on a full local release, where both files came out byte-identical - but
# anything that differs between the invocations can change that, and the
# correct behaviour is the same either way.
#
# There is deliberately no separate "the bundle has a UUID" assertion here,
# and the reason is structural rather than measured: the per-artifact block
# above faults both for a missing asset and for an asset with no usable value,
# for every artifact including the bundle, and every other route to that point
# (a failed integrity check, a failed listing) faults and `continue`s first.
# So a check here could not fire. Both of those bundle shapes have their own
# case in the suite, which is what makes that argument checkable rather than
# merely plausible.

if (( failures )); then
  echo "::error::$failures problem(s) found; refusing to publish." >&2
  exit 1
fi
echo "Verified ${#artifacts[@]} Android artifact(s)."
