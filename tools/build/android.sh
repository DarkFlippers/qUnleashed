#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="qunleashed"
DIST_DIR="$ROOT_DIR/dist"
VERSION_NAME="${QUNLEASHED_VERSION_NAME:-}"

if [[ -z "$VERSION_NAME" ]]; then
  VERSION_NAME="$(sed -nE 's/^version:[[:space:]]*([0-9A-Za-z._-]+).*/\1/p' "$ROOT_DIR/pubspec.yaml" | head -n 1)"
  VERSION_NAME="${VERSION_NAME%%+*}"
fi

if [[ -z "$VERSION_NAME" ]]; then
  echo "App version not found. Set QUNLEASHED_VERSION_NAME or pubspec.yaml version." >&2
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

echo "Building Android universal APK..."
(cd "$ROOT_DIR" && "$FLUTTER_BIN" build apk --release "${FLUTTER_BUILD_ARGS[@]}")

UNIVERSAL_APK="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "$UNIVERSAL_APK" ]]; then
  echo "Expected universal APK not found: $UNIVERSAL_APK" >&2
  exit 1
fi

cp "$UNIVERSAL_APK" "$DIST_DIR/${APP_NAME}_${VERSION_NAME}_android_universal.apk"

echo "Building Android ABI APKs..."
(cd "$ROOT_DIR" && "$FLUTTER_BIN" build apk --release --split-per-abi "${FLUTTER_BUILD_ARGS[@]}")

ANDROID_ABIS=(
  "armeabi-v7a"
  "arm64-v8a"
  "x86_64"
)

for abi in "${ANDROID_ABIS[@]}"; do
  apk="$ROOT_DIR/build/app/outputs/flutter-apk/app-${abi}-release.apk"
  if [[ ! -f "$apk" ]]; then
    echo "Expected ABI APK not found: $apk" >&2
    exit 1
  fi

  cp "$apk" "$DIST_DIR/${APP_NAME}_${VERSION_NAME}_android_${abi}.apk"
done

echo "Built Android APKs:"
find "$DIST_DIR" -maxdepth 1 -type f -name "${APP_NAME}_${VERSION_NAME}_android_*.apk" -print | sort
