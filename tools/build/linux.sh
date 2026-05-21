#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="qunleashed"
BUILD_DIR="$ROOT_DIR/build/linux/x64/release/bundle"
DIST_DIR="$ROOT_DIR/dist"
OUT_FILE="$DIST_DIR/${APP_NAME}-linux-x64"

FLUTTER_BIN="${FLUTTER_BIN:-}"
if [[ -z "$FLUTTER_BIN" ]]; then
  if [[ -x "/home/apfx32/development/flutter/bin/flutter" ]]; then
    FLUTTER_BIN="/home/apfx32/development/flutter/bin/flutter"
  else
    FLUTTER_BIN="$(command -v flutter)"
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
(cd "$ROOT_DIR" && "$FLUTTER_BIN" build linux --release)

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
