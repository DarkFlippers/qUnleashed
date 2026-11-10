#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP_NAME="qunleashed"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../android_abis.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/android_abis.sh"
# The two R8 mapping filenames, shared with `upload_r8_mapping.sh` so the
# build and the upload cannot disagree about which file is which artifact's.
# shellcheck source=../sentry_proguard_uuid.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sentry_proguard_uuid.sh"
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
# The bundle and both mappings for the same reason. The mappings matter most:
# the second invocation overwrites the first's, so a stale one left in the
# tree would be uploaded as if it described this build.
APK_OUT="$ROOT_DIR/build/app/outputs/flutter-apk"
AAB_OUT="$ROOT_DIR/build/app/outputs/bundle/release"
MAPPING_DIR="$ROOT_DIR/build/app/outputs/mapping/release"
# Where the APK run's mapping is kept while the bundle run overwrites
# `mapping.txt`. Named here and read by `upload_r8_mapping.sh`, which is given
# both paths rather than deriving either.
APK_MAPPING="$MAPPING_DIR/$R8_MAPPING_APK"
rm -f "$APK_OUT/app-release.apk"
rm -f "$AAB_OUT/app-release.aab"
rm -f "$MAPPING_DIR/$R8_MAPPING_BUNDLE" "$APK_MAPPING"
for abi in "${ANDROID_ABIS[@]}"; do
  rm -f "$APK_OUT/app-${abi}-release.apk"
done

# One invocation, all four APKs: `--split-per-abi` enables AGP's ABI splits
# and the `splits` block in `android/app/build.gradle.kts` turns the universal
# output back on, which is also where the why is written down. One R8 run, so
# one mapping and one UUID across the four. #361.
echo "Building Android APKs..."
(cd "$ROOT_DIR" && "$FLUTTER_BIN" build apk --release --split-per-abi "${FLUTTER_BUILD_ARGS[@]}")

# The APK run's mapping, kept before the bundle run overwrites it.
#
# This is the whole reason the bundle is a second invocation and not a task in
# the first. AGP refuses to build an App Bundle while ABI splits are enabled -
# "Please disable building multiple APKs when building an Android app bundle",
# issuetracker 402800800, measured rather than read - so `assembleRelease`
# finalized by `bundleRelease` fails outright. A Gradle task graph that asks
# for both is fine, the execution is not.
#
# So there are two R8 runs, two mappings and two UUIDs, and the answer is to
# upload both rather than to pretend there is one: `upload_r8_mapping.sh` is
# given each mapping with the artifact whose UUID it belongs to.
if [[ ! -f "$MAPPING_DIR/$R8_MAPPING_BUNDLE" ]]; then
  echo "R8 wrote no mapping for the APKs at $MAPPING_DIR/$R8_MAPPING_BUNDLE." >&2
  echo "Either R8 did not run, or its output moved - the variant is in that path." >&2
  exit 1
fi
cp "$MAPPING_DIR/$R8_MAPPING_BUNDLE" "$APK_MAPPING"

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
if [[ ! -f "$MAPPING_DIR/$R8_MAPPING_BUNDLE" ]]; then
  echo "R8 wrote no mapping for the App Bundle at $MAPPING_DIR/$R8_MAPPING_BUNDLE." >&2
  exit 1
fi

echo "Built Android artifacts:"
find "$DIST_DIR" -maxdepth 1 -type f \
  \( -name "${APP_NAME}_${VERSION_NAME}_android_*.apk" \
  -o -name "${APP_NAME}_${VERSION_NAME}_android.aab" \) -print | sort
echo "R8 mappings:"
echo "  $APK_MAPPING (the APKs)"
echo "  $MAPPING_DIR/$R8_MAPPING_BUNDLE (the App Bundle)"
