#!/usr/bin/env bash
# Checks that the built Android APKs actually contain a working application
# before the release publishes them.
#
#   verify_apks.sh [directory]   # default: dist
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

if (( failures )); then
  echo "::error::$failures problem(s) found; refusing to publish." >&2
  exit 1
fi
echo "Verified ${#apks[@]} Android artifact(s)."
