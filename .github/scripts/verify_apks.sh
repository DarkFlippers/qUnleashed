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
# The expected ABIs come from android_abis.sh, shared with android.sh so the
# names it writes and the names checked here cannot drift apart.
#
# Note this assumes standalone APKs from `flutter build apk`. An App Bundle
# config split carries no classes.dex and would be rejected; if the build ever
# moves to bundles (Play requires them), this needs revisiting.
set -Eeuo pipefail

# shellcheck source=android_abis.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/android_abis.sh"

# A real snapshot is multiple megabytes. This only has to be large enough to
# reject an empty or stub file and small enough never to reject a real one.
MIN_SNAPSHOT_BYTES=1048576

# What the Sentry Android Gradle Plugin injects so an event can name the R8
# mapping it belongs to. Checked here because nothing else can see it go
# missing: R8 renames every Java and Kotlin frame whether or not this is
# present, the build is green either way, and the only other symptom is a
# crash report that arrives as `w2.r.k` months later - which is #343, three
# releases long. The plugin skips a variant it does not consider minified and
# says nothing at all about it - not even at `info` - so "the plugin is
# configured" and "this APK can be deobfuscated" are different facts, and this
# is the only place that can tell them apart.
SENTRY_UUID_ASSET='assets/sentry-debug-meta.properties'
SENTRY_UUID_RE='[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'

dir="${1:-dist}"
failures=0

fault() {
  echo "::error::$1" >&2
  failures=$((failures + 1))
}

shopt -s nullglob
apks=("$dir"/*_android_*.apk)
if (( ${#apks[@]} == 0 )); then
  echo "::error::No Android APKs found in $dir." >&2
  exit 1
fi

seen_universal=0
declare -A seen_abi=()
declare -A seen_uuid=()

for apk in "${apks[@]}"; do
  name="$(basename "$apk")"
  before=$failures

  # Both the expected ABIs and the artifact's identity come from the name.
  case "$name" in
    *_android_universal.apk)
      want=("${ANDROID_ABIS[@]}")
      seen_universal=1
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

  # Reads the entry data and checks every CRC, which the listing below does not.
  if ! err="$(unzip -tqq "$apk" 2>&1)"; then
    fault "$name failed its integrity check: ${err:-no detail}"
    continue
  fi

  if ! listing="$(unzip -Z1 "$apk" 2>&1)"; then
    fault "$name could not be listed: ${listing:-no detail}"
    continue
  fi

  grep -qxF -- 'AndroidManifest.xml' <<<"$listing" \
    || fault "$name has no AndroidManifest.xml."
  grep -qxF -- 'classes.dex' <<<"$listing" \
    || fault "$name has no classes.dex."

  # Present is not the same as populated here either: the plugin writes the
  # file whenever any of its features is on, and only the mapping's UUID makes
  # it mean anything.
  if ! grep -qxF -- "$SENTRY_UUID_ASSET" <<<"$listing"; then
    fault "$name has no $SENTRY_UUID_ASSET - nothing ties it to an R8 mapping, so its Java frames will not deobfuscate."
  else
    # `|| true` because `head` closing the pipe early SIGPIPEs `unzip`, which
    # `pipefail` turns into a failed assignment and `errexit` into this gate
    # abandoning the remaining artifacts with no message at all. Today's
    # properties file is far too small to reach that, and a gate is the last
    # place to leave it standing. An empty read falls into the fault below.
    uuid="$(unzip -p "$apk" "$SENTRY_UUID_ASSET" 2>/dev/null \
      | sed -nE "s/^io\.sentry\.ProguardUuids=($SENTRY_UUID_RE)\$/\1/p" | head -n 1 || true)"
    if [[ -z "$uuid" ]]; then
      fault "$name carries $SENTRY_UUID_ASSET with no io.sentry.ProguardUuids in it."
    else
      seen_uuid["$uuid"]=1
    fi
  fi

  for abi in "${want[@]}"; do
    if ! grep -qxF -- "lib/$abi/libapp.so" <<<"$listing"; then
      fault "$name has no lib/$abi/libapp.so - the Dart snapshot is missing."
      continue
    fi
    # Present is not the same as populated: a truncated or stub snapshot is
    # still an app that dies at launch.
    bytes="$(unzip -p "$apk" "lib/$abi/libapp.so" | wc -c)"
    if (( bytes < MIN_SNAPSHOT_BYTES )); then
      fault "$name has a $bytes-byte lib/$abi/libapp.so; expected at least $MIN_SNAPSHOT_BYTES."
    fi
  done

  # A split carrying an ABI it should not have means the split did not happen.
  # `|| true` because no lib/ entries at all is a fault reported above, not a
  # reason to abandon the remaining artifacts.
  found="$(grep -oE '^lib/[^/]+/' <<<"$listing" | cut -d/ -f2 | sort -u || true)"
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
(( seen_universal )) || fault "No universal APK in $dir."
for abi in "${ANDROID_ABIS[@]}"; do
  [[ -n "${seen_abi[$abi]:-}" ]] || fault "No $abi APK in $dir."
done

# One mapping is uploaded, so one UUID has to be what every artifact points at.
# `android.sh` builds twice - once universal, once --split-per-abi - and R8
# writes over the same `mapping.txt` both times. The UUID is derived from the
# mapping's contents, so the two runs agree as long as R8 is deterministic
# across them; that holds today and nothing enforces it. If it ever stops
# holding, the upload sends one mapping and the APKs built by the other run
# carry a UUID with nothing behind it - and the ones that do resolve resolve
# against a mapping describing different bytes, which deobfuscates to confident
# wrong names. Worse than `w2.r.k`, because a wrong name is believed.
if (( ${#seen_uuid[@]} > 1 )); then
  fault "The artifacts in $dir carry ${#seen_uuid[@]} different R8 mapping UUIDs (${!seen_uuid[*]}); only one mapping is uploaded, so the rest could not deobfuscate."
fi

if (( failures )); then
  echo "::error::$failures problem(s) found; refusing to publish." >&2
  exit 1
fi
echo "Verified ${#apks[@]} Android artifact(s)."
