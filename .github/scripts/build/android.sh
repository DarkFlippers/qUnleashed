#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP_NAME="qunleashed"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../android_abis.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/android_abis.sh"
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
APK_OUT="$ROOT_DIR/build/app/outputs/flutter-apk"
rm -f "$APK_OUT/app-release.apk"
for abi in "${ANDROID_ABIS[@]}"; do
  rm -f "$APK_OUT/app-${abi}-release.apk"
done

# One build, all four APKs: `--split-per-abi` enables AGP's ABI splits and the
# `splits` block in `android/app/build.gradle.kts` turns the universal output
# back on, which is also where the why is written down. #361.
echo "Building Android APKs..."
(cd "$ROOT_DIR" && "$FLUTTER_BIN" build apk --release --split-per-abi "${FLUTTER_BUILD_ARGS[@]}")

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

echo "Built Android APKs:"
find "$DIST_DIR" -maxdepth 1 -type f -name "${APP_NAME}_${VERSION_NAME}_android_*.apk" -print | sort
