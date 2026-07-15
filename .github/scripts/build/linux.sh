#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP_NAME="qunleashed"
VERSION_NAME="${QUNLEASHED_VERSION_NAME:-}"
DIST_DIR="$ROOT_DIR/dist"

if [[ -z "$VERSION_NAME" ]]; then
  VERSION_NAME="$(sed -nE 's/^version:[[:space:]]*([0-9A-Za-z._-]+).*/\1/p' "$ROOT_DIR/pubspec.yaml" | head -n 1)"
  VERSION_NAME="${VERSION_NAME%%+*}"
fi

if [[ -z "$VERSION_NAME" ]]; then
  echo "App version not found. Set QUNLEASHED_VERSION_NAME or pubspec.yaml version." >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64 | amd64) TARGET_ARCH="x64" ;;
  aarch64 | arm64) TARGET_ARCH="arm64" ;;
  armv7l | armv7*) TARGET_ARCH="armv7" ;;
  *) TARGET_ARCH="$(uname -m)" ;;
esac

BUILD_DIR="$ROOT_DIR/build/linux/$TARGET_ARCH/release/bundle"
OUT_FILE="$DIST_DIR/${APP_NAME}_${VERSION_NAME}_linux_${TARGET_ARCH}"

FLUTTER_BIN="${FLUTTER_BIN:-}"
if [[ -z "$FLUTTER_BIN" ]]; then
  if [[ -x "/home/apfx32/development/flutter/bin/flutter" ]]; then
    FLUTTER_BIN="/home/apfx32/development/flutter/bin/flutter"
  else
    FLUTTER_BIN="$(command -v flutter || true)"
  fi
fi

if [[ -z "$FLUTTER_BIN" || ! -x "$FLUTTER_BIN" ]]; then
  echo "Flutter executable not found. Set FLUTTER_BIN=/path/to/flutter." >&2
  exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "tar is required." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"

echo "Using Flutter: $FLUTTER_BIN"
echo "Building Linux release..."
read -r -a FLUTTER_BUILD_ARGS <<< "${QUNLEASHED_FLUTTER_BUILD_ARGS:-}"
(cd "$ROOT_DIR" && "$FLUTTER_BIN" build linux --release "${FLUTTER_BUILD_ARGS[@]}")

if [[ ! -x "$BUILD_DIR/$APP_NAME" ]]; then
  echo "Expected app binary not found: $BUILD_DIR/$APP_NAME" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
ARCHIVE="$TMP_DIR/payload.tar.gz"
STUB="$TMP_DIR/stub.sh"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -C "$BUILD_DIR" -czf "$ARCHIVE" .

cat > "$STUB" <<'STUB'
#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="qunleashed"
WORK_DIR="${TMPDIR:-/tmp}/${APP_NAME}-self-$$"
MARKER="__QUNLEASHED_PAYLOAD_BELOW__"

cleanup() {
  local tmp_root="${TMPDIR:-/tmp}"
  local expected_prefix="${tmp_root%/}/${APP_NAME}-self-"

  if [[ -n "${WORK_DIR:-}" && "$WORK_DIR" == "$expected_prefix"* ]]; then
    rm -rf -- "$WORK_DIR"
  else
    echo "Refusing to remove unexpected work directory: ${WORK_DIR:-<unset>}" >&2
  fi
}
trap cleanup EXIT

mkdir -p "$WORK_DIR"
ARCHIVE_LINE="$(awk "/^$MARKER$/ { print NR + 1; exit 0; }" "$0")"
if [[ -z "$ARCHIVE_LINE" ]]; then
  echo "Embedded payload marker not found." >&2
  exit 1
fi

tail -n +"$ARCHIVE_LINE" "$0" | tar -xz -C "$WORK_DIR"
chmod +x "$WORK_DIR/$APP_NAME"
exec "$WORK_DIR/$APP_NAME" "$@"

__QUNLEASHED_PAYLOAD_BELOW__
STUB

cat "$STUB" "$ARCHIVE" > "$OUT_FILE"
chmod +x "$OUT_FILE"

echo "Built single-file executable:"
echo "$OUT_FILE"
