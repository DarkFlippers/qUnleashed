#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP_NAME="qunleashed"
# The asset version, which carries the channel suffix and build number on a
# dev build so its filenames differ from the release of the same cycle.
# Falls back to the numeric name, then to pubspec.
VERSION_NAME="${QUNLEASHED_ASSET_VERSION:-${QUNLEASHED_VERSION_NAME:-}}"
DIST_DIR="$ROOT_DIR/dist"

if [[ -z "$VERSION_NAME" ]]; then
  VERSION_NAME="$(sed -nE 's/^version:[[:space:]]*([0-9A-Za-z._-]+).*/\1/p' "$ROOT_DIR/pubspec.yaml" | head -n 1)"
  VERSION_NAME="${VERSION_NAME%%+*}"
fi

if [[ -z "$VERSION_NAME" ]]; then
  echo "App version not found. Set QUNLEASHED_ASSET_VERSION or pubspec.yaml version." >&2
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

# `objdump` rather than `readelf`, to match `check_linux_abi.sh`, which reads
# the same bundle in the same job and takes the same override so its tests can
# stub it. Both tools are load-bearing below rather than optional extras: a
# missing `strip` aborts loudly under `set -e`, but a missing section reader
# makes the leak check a silent no-op.
OBJDUMP="${OBJDUMP:-objdump}"
for tool in strip "$OBJDUMP"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required (binutils)." >&2
    exit 1
  fi
done

# Is this an ELF image? Four magic bytes, read in bash, because the alternative
# is a process per file across the whole bundle and because a name pattern
# would miss the runner (no extension) or a plugin named something new.
is_elf() {
  local magic
  IFS= read -r -N 4 -d '' magic < "$1" 2>/dev/null || return 1
  [[ "$magic" == $'\x7fELF' ]]
}

# Does this file carry DWARF?
has_debug_info() {
  "$OBJDUMP" -h "$1" 2>/dev/null | grep -q '\.debug_info'
}

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

# === What ships, and what Sentry gets ===
#
# Release compiles with `-g` now (linux/CMakeLists.txt), so the bundle Flutter
# just wrote carries DWARF. The Sentry upload step needs that and reads
# `$BUILD_DIR` itself, after this script has finished - so the bundle is left
# exactly as the build left it, and the archive is built from a stripped copy.
#
# The positive check comes first and is the important one. #310 was not a
# bundle that shipped too much; it was a toolchain that produced nothing and a
# pipeline that reported success anyway. The strip below, and the leak check
# after it, are both no-ops in that state - `strip` removes nothing, the leak
# scan finds nothing, and a green build means only that nothing was there.
# `check_ffi_exports.sh` makes the same argument about a regex that matches
# nothing: a guard that cannot fail is a rubber stamp.
if ! has_debug_info "$BUILD_DIR/$APP_NAME"; then
  echo "::error::$BUILD_DIR/$APP_NAME carries no .debug_info, so Sentry cannot" >&2
  echo "::error::symbolicate a Linux crash. Release must compile with -g - see" >&2
  echo "::error::the debug information block in linux/CMakeLists.txt. (#310)" >&2
  exit 1
fi

STAGE_DIR="$TMP_DIR/bundle"
cp -a "$BUILD_DIR" "$STAGE_DIR"

# `--strip-debug`, not the default `strip`: the symbol tables have to survive
# or nothing resolves at load. `libapp.so` is the Dart AOT snapshot, never
# compiled with `-g`, so it passes through either way.
while IFS= read -r f; do
  if is_elf "$f"; then
    strip --strip-debug "$f"
  fi
done < <(find "$STAGE_DIR" -type f)

# Re-derived from the file system rather than from the list above, so that a
# misjudgement by `is_elf` is caught here instead of being shared. This strip
# is the only thing between the download a user gets and one several times its
# size.
leaked=()
while IFS= read -r f; do
  if has_debug_info "$f"; then
    leaked+=("$f")
  fi
done < <(find "$STAGE_DIR" -type f)
if (( ${#leaked[@]} )); then
  echo "::error::Debug info survived the strip and would ship to users:" >&2
  printf '  %s\n' "${leaked[@]}" >&2
  exit 1
fi

tar -C "$STAGE_DIR" -czf "$ARCHIVE" .

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
