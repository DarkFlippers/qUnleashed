#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP_NAME="qunleashed"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../android_abis.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/android_abis.sh"
# The artifact names and the mapping filenames, shared with `verify_apks.sh`
# and `upload_r8_mapping.sh` so the three cannot disagree about what this
# build produced. ADR 0017.
# shellcheck source=../android_artifacts.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/android_artifacts.sh"
DIST_DIR="$ROOT_DIR/dist"
# The asset version, which carries the channel suffix and build number on a
# dev build so its filenames differ from the release of the same cycle.
# Falls back to the numeric name, then to pubspec.
VERSION_NAME="${QUNLEASHED_ASSET_VERSION:-${QUNLEASHED_VERSION_NAME:-}}"

if [[ -z "$VERSION_NAME" ]]; then
  VERSION_NAME="$(sed -nE 's/^version:[[:space:]]*([0-9A-Za-z._-]+).*/\1/p' "$ROOT_DIR/pubspec.yaml" | head -n 1)"
  VERSION_NAME="${VERSION_NAME%%+*}"
fi

if [[ -z "$VERSION_NAME" ]]; then
  echo "App version not found. Set QUNLEASHED_ASSET_VERSION or pubspec.yaml version." >&2
  exit 1
fi

FLUTTER_BIN="${FLUTTER_BIN:-}"
if [[ -z "$FLUTTER_BIN" ]]; then
  FLUTTER_BIN="$(command -v flutter || true)"
fi

if [[ -z "$FLUTTER_BIN" || ! -x "$FLUTTER_BIN" ]]; then
  echo "Flutter executable not found. Set FLUTTER_BIN=/path/to/flutter." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"

echo "Using Flutter: $FLUTTER_BIN"
read -r -a FLUTTER_BUILD_ARGS <<< "${QUNLEASHED_FLUTTER_BUILD_ARGS:-}"

# Clear what this build is about to claim it produced. The universal APK no
# longer comes from an invocation of its own, so if the Gradle override that
# emits it ever stopped taking effect, a leftover `app-release.apk` from an
# earlier non-split build in the same tree would be copied into `dist/` and
# published beside freshly built splits. CI is a fresh checkout and would hit
# the existence check below instead; this is for a local run, where it turns a
# silent wrong answer into no answer.
#
# The bundle and both mappings for the same reason, and the mappings matter
# most - not because of the overwrite, but because the existence checks below
# cannot tell R8's output from an earlier run's. Deleting them first is what
# makes their presence afterwards mean anything.
#
# `dist/` too, for the artifacts this build is about to write there. Nothing
# else clears it, so a local re-run after a version bump leaves the previous
# version's files beside the new ones - and a glob that then matches two picks
# by collation order, which for a version number is the OLDER one. Both gates
# refuse that now, but refusing a hazard the build can simply not create is
# the shallower half; this is the other one. Version-agnostic globs, because
# the leftovers that matter are another version's.
APK_OUT="$ROOT_DIR/build/app/outputs/flutter-apk"
AAB_OUT="$ROOT_DIR/build/app/outputs/bundle/release"
MAPPING_DIR="$ROOT_DIR/build/app/outputs/mapping/release"
# Each R8 run's output under a name of its own. R8 always writes
# `$R8_MAPPING_OUTPUT`, so neither run's output keeps that name for long -
# both are copied aside as soon as they exist, and from then on a reader of
# either name knows which artifact it describes. `android_artifacts.sh` holds
# the names; ADR 0017 §2 holds the why.
APK_MAPPING="$MAPPING_DIR/$R8_MAPPING_APK"
BUNDLE_MAPPING="$MAPPING_DIR/$R8_MAPPING_BUNDLE"
R8_OUTPUT="$MAPPING_DIR/$R8_MAPPING_OUTPUT"
rm -f "$APK_OUT/app-release.apk"
rm -f "$AAB_OUT/app-release.aab"
rm -f "$R8_OUTPUT" "$APK_MAPPING" "$BUNDLE_MAPPING"
for abi in "${ANDROID_ABIS[@]}"; do
  rm -f "$APK_OUT/app-${abi}-release.apk"
done
shopt -s nullglob
rm -f "$DIST_DIR"/${APP_NAME}_$ANDROID_APK_GLOB "$DIST_DIR"/${APP_NAME}_$ANDROID_BUNDLE_GLOB

# One invocation, all four APKs: `--split-per-abi` enables AGP's ABI splits
# and the `splits` block in `android/app/build.gradle.kts` turns the universal
# output back on, which is also where the why is written down. One R8 run, so
# one mapping and one UUID across the four. #361.
#
# The bundle cannot join this invocation, and ADR 0017 §1 is the measurement
# and the alternative that was rejected. What matters here is only the
# consequence: a second R8 run, so a second mapping to keep.
echo "Building Android APKs..."
(cd "$ROOT_DIR" && "$FLUTTER_BIN" build apk --release --split-per-abi "${FLUTTER_BUILD_ARGS[@]}")

# The APK run's mapping, given its own name before the bundle run overwrites
# R8's output. Existence and not freshness, deliberately: ADR 0017 §2 has the
# reasoning and the measurement, and says why a `-nt` check would be wrong.
if [[ ! -f "$R8_OUTPUT" ]]; then
  echo "R8 wrote no mapping for the APKs at $R8_OUTPUT." >&2
  echo "Either R8 did not run, or its output moved - the variant is in that path." >&2
  exit 1
fi
mv "$R8_OUTPUT" "$APK_MAPPING"

# Play does not accept an APK for a new application, so the bundle is what a
# submission uploads. It is not a GitHub release asset: an `.aab` cannot be
# sideloaded, so publishing one beside the APKs would only invite someone to
# download a file they cannot install.
#
# No `--split-per-abi` here, and it is not an omission: it is the flag AGP
# refuses alongside a bundle. A bundle carries every ABI by construction and
# Play does the splitting at install time, which is the point of the format.
echo "Building the Android App Bundle..."
(cd "$ROOT_DIR" && "$FLUTTER_BIN" build appbundle --release "${FLUTTER_BUILD_ARGS[@]}")

# Flutter names what it copies into `flutter-apk/` after the output's ABI
# filter, and the universal output has none - so it keeps the plain
# `app-release.apk` it had when it was its own build, rather than AGP's
# `app-universal-release.apk` from the directory underneath.
UNIVERSAL_APK="$APK_OUT/app-release.apk"
if [[ ! -f "$UNIVERSAL_APK" ]]; then
  echo "Expected universal APK not found: $UNIVERSAL_APK" >&2
  exit 1
fi

cp "$UNIVERSAL_APK" "$DIST_DIR/${APP_NAME}_${VERSION_NAME}_android_universal.apk"

for abi in "${ANDROID_ABIS[@]}"; do
  apk="$APK_OUT/app-${abi}-release.apk"
  if [[ ! -f "$apk" ]]; then
    echo "Expected ABI APK not found: $apk" >&2
    exit 1
  fi

  cp "$apk" "$DIST_DIR/${APP_NAME}_${VERSION_NAME}_android_${abi}.apk"
done

# `_android.aab`, with no second underscore, so it cannot be caught by any of
# the `*_android_*` globs that collect the APKs - in this script, in
# `verify_apks.sh`, in the release-asset upload or in `action-gh-release`'s
# file list. The bundle is uploaded as its own CI artifact under a name the
# publish job's `release-assets-*` pattern does not match, which is what keeps
# it out of `SHA256SUMS` as well: that file hashes whatever is in `dist/`, so a
# bundle reaching the publish job would be listed in a digest file for an asset
# nobody can download.
AAB="$AAB_OUT/app-release.aab"
if [[ ! -f "$AAB" ]]; then
  echo "Expected App Bundle not found: $AAB" >&2
  exit 1
fi
cp "$AAB" "$DIST_DIR/${APP_NAME}_${VERSION_NAME}_android.aab"

# Both mappings have to exist for the upload to address both artifacts, and
# the bundle run is what wrote the second one. Checked here rather than left
# to the uploader, which runs as a `continue-on-error` step: a release must
# not get as far as publishing artifacts whose Java frames cannot be read.
if [[ ! -f "$R8_OUTPUT" ]]; then
  echo "R8 wrote no mapping for the App Bundle at $R8_OUTPUT." >&2
  exit 1
fi
mv "$R8_OUTPUT" "$BUNDLE_MAPPING"

echo "Built Android artifacts:"
find "$DIST_DIR" -maxdepth 1 -type f \
  \( -name "${APP_NAME}_${VERSION_NAME}_android_*.apk" \
  -o -name "${APP_NAME}_${VERSION_NAME}_android.aab" \) -print | sort
echo "R8 mappings:"
echo "  $APK_MAPPING (the APKs)"
echo "  $BUNDLE_MAPPING (the App Bundle)"
