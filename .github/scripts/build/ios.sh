#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP_NAME="Runner"
FILE_NAME="qunleashed"
# The asset version, which carries the channel suffix and build number on a
# dev build so its filenames differ from the release of the same cycle.
# Falls back to the numeric name, then to pubspec.
VERSION_NAME="${QUNLEASHED_ASSET_VERSION:-${QUNLEASHED_VERSION_NAME:-}}"
DIST_DIR="$ROOT_DIR/dist"
BUILD_APP="$ROOT_DIR/build/ios/iphoneos/$APP_NAME.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "The iOS IPA can only be built on macOS." >&2
  exit 1
fi

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

if ! command -v zip >/dev/null 2>&1; then
  echo "zip is required." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"

echo "Using Flutter: $FLUTTER_BIN"
echo "Building iOS release (no codesign)..."
FLUTTER_COMMAND=("$FLUTTER_BIN" build ios --release --no-codesign)
if [[ -n "${QUNLEASHED_FLUTTER_BUILD_ARGS:-}" ]]; then
  read -r -a FLUTTER_BUILD_ARGS <<< "$QUNLEASHED_FLUTTER_BUILD_ARGS"
  FLUTTER_COMMAND+=("${FLUTTER_BUILD_ARGS[@]}")
fi
(cd "$ROOT_DIR" && "${FLUTTER_COMMAND[@]}")

if [[ ! -d "$BUILD_APP" ]]; then
  echo "Expected app bundle not found: $BUILD_APP" >&2
  exit 1
fi

"$ROOT_DIR/.github/scripts/check_ffi_exports.sh" "$BUILD_APP/$APP_NAME" "$BUILD_APP"

OUT_FILE="$DIST_DIR/${FILE_NAME}_${VERSION_NAME}_ios_arm64.ipa"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${FILE_NAME}-ipa.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/Payload"
cp -R "$BUILD_APP" "$TMP_DIR/Payload/$APP_NAME.app"
xattr -cr "$TMP_DIR/Payload"

rm -f "$OUT_FILE"
(cd "$TMP_DIR" && zip -qry "$OUT_FILE" Payload)

echo "Built iOS IPA:"
echo "$OUT_FILE"
