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
# stub it.
OBJDUMP="${OBJDUMP:-objdump}"
for tool in strip "$OBJDUMP"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required (binutils)." >&2
    exit 1
  fi
done

# Is this an ELF image? Four magic bytes, read in bash rather than by asking a
# tool, so that "not an ELF file" is decided by the file itself and not by
# whether a tool happened to succeed. A name pattern would miss the runner,
# which has no extension, or a plugin named something new.
is_elf() {
  local magic
  # Unreadable is not "not an ELF file". Returning false for it would drop the
  # file out of the strip and out of both scans below without a word, which is
  # the same silent-pass shape `has_section` refuses a few lines down.
  if [[ ! -r "$1" ]]; then
    echo "::error::$1 cannot be read, so it would be skipped by the strip and" >&2
    echo "::error::by both checks below without being reported. Refusing to pass." >&2
    exit 1
  fi
  IFS= read -r -N 4 -d '' magic < "$1" 2>/dev/null || return 1
  [[ "$magic" == $'\x7fELF' ]]
}

# Does this ELF image have the named section? Call only on something `is_elf`
# accepted: objdump failing here is a broken tool or an unreadable file, never
# a normal outcome, and it is fatal rather than false. Returning false would
# make the leak scan below report "clean" for a file it could not read, which
# is the silent-success shape this whole change exists to remove.
#
# Captured rather than piped into `grep -q`, the argument
# `check_arb_locales.sh` makes: `grep -q` exits on its first match, which can
# leave the producer killed by SIGPIPE, and under `pipefail` the pipeline is
# then non-zero. Not reachable on `objdump -h` output, which is a few KB and
# fits the pipe buffer - but the failure direction here ships debug
# information, so it is not worth depending on the size.
has_section() {
  local sections
  if ! sections="$("$OBJDUMP" -h "$1" 2>&1)"; then
    echo "::error::$OBJDUMP could not read $1, so this guard would check less" >&2
    echo "::error::of the bundle than it reports. Refusing to pass: $sections" >&2
    exit 1
  fi
  # Anchored on the name column, not a substring of the whole output. The first
  # line of `objdump -h` is the file's own path, so a substring match would let
  # a bundle path containing `.dynsym` satisfy that check vacuously and make
  # one containing `.debug_info` read as a leak. It also means a renamed or
  # compressed section (`.zdebug_info`) is reported absent rather than matched
  # by accident - which fails loudly in the positive checks and is the safe
  # direction in the leak check.
  awk -v want="$2" '$2 == want { found = 1 } END { exit !found }' <<<"$sections"
}

has_debug_info() {
  has_section "$1" ".debug_info"
}

# Every regular file in a directory, as an array, with `find`'s exit status
# honoured. `check_linux_abi.sh` spells out why this is not a process
# substitution: `find` prints what it reached before erroring on a directory it
# could not descend, and a process substitution's status is invisible to both
# `set -e` and `pipefail` - so the list would be silently short and every
# check over it green.
list_files() {
  local listed
  if ! listed="$(find "$1" -type f)"; then
    echo "::error::find failed under $1, so the list below is short and every" >&2
    echo "::error::check over it would pass over a subset. Refusing to pass." >&2
    exit 1
  fi
  mapfile -t "$2" <<<"$listed"
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

# The runner and our own FFI libraries, not merely "something in the bundle".
# The runner alone would be the weakest possible check: it is the one target
# whose debug information survives a partial regression, because it is the
# closest to where the flag is set. The three in `lib/modules/cpp` are most of
# what a native crash is.
#
# What this does NOT catch, so nobody assumes it does: appending `-g` before C
# is enabled replaces the C defaults with exactly ` -g`, which still produces
# DWARF. Every image this loop names passes in that state. The damage there is
# the lost `-O3 -DNDEBUG`, which no debug-file check can see; only
# `enable_language(C)` prevents it.
#
# `libapp.so` and `libflutter_linux_gtk.so` are deliberately not here: the
# first is the Dart AOT snapshot and the second a prebuilt engine, and neither
# is built by this tree.
required_images=("$BUILD_DIR/$APP_NAME")
for lib in mfkey32 hardnested faaccrack; do
  required_images+=("$BUILD_DIR/lib/libqunleashed_$lib.so")
done

# Three outcomes, not two, because sending someone to the wrong file is what
# the absent/undebuggable split exists to stop: gone from the bundle, there but
# not an ELF image at all, and there but carrying no DWARF. `is_elf` comes
# before `has_debug_info`, which is fatal on anything objdump cannot read.
#
# Absent and present-but-undebuggable are reported apart, because they have
# different causes and the first version of this guard conflated them: it said
# "no .debug_info" about three libraries that were not in the bundle at all,
# and cost an afternoon of looking for a stripping step that did not exist.
# A floor on the list itself. Nothing can empty it as the code stands, but the
# only thing between an empty list and a green run is the `echo` below - and a
# log line as the last word on a failure is the shape CLAUDE.md names.
if (( ${#required_images[@]} < 4 )); then
  echo "::error::The required-images list has ${#required_images[@]} entries and" >&2
  echo "::error::should have at least 4. Refusing to report a green bundle." >&2
  exit 1
fi

absent=()
malformed=()
undebuggable=()
for image in "${required_images[@]}"; do
  if [[ ! -f "$image" ]]; then
    absent+=("$image")
  elif ! is_elf "$image"; then
    malformed+=("$image")
  elif ! has_debug_info "$image"; then
    undebuggable+=("$image")
  fi
done
if (( ${#absent[@]} )); then
  echo "::error::These are missing from the bundle entirely, so the app cannot" >&2
  echo "::error::load them and Sentry has nothing to symbolicate. Check that the" >&2
  echo "::error::install step still covers QUNLEASHED_FFI_LIBRARIES - see the" >&2
  echo "::error::note in linux/runner/CMakeLists.txt." >&2
  printf '  %s\n' "${absent[@]}" >&2
  exit 1
fi
if (( ${#malformed[@]} )); then
  echo "::error::These are in the bundle but are not ELF images - truncated, or" >&2
  echo "::error::something other than a shared object was installed over them." >&2
  echo "::error::Neither -g nor the install step is the cause; look at what" >&2
  echo "::error::wrote them." >&2
  printf '  %s\n' "${malformed[@]}" >&2
  exit 1
fi
if (( ${#undebuggable[@]} )); then
  echo "::error::No .debug_info in the following, so Sentry cannot symbolicate" >&2
  echo "::error::a Linux crash in them. Release must compile with -g - see the" >&2
  echo "::error::debug information block in linux/CMakeLists.txt. (#310)" >&2
  printf '  %s\n' "${undebuggable[@]}" >&2
  exit 1
fi
echo "Debug information for Sentry: ${#required_images[@]} image(s) carry DWARF."

STAGE_DIR="$TMP_DIR/bundle"
cp -a "$BUILD_DIR" "$STAGE_DIR"

list_files "$STAGE_DIR" staged
# A tripwire, not a check against today's `cp`: `$STAGE_DIR` is a copy of a
# directory whose runner was asserted present above, under `set -e`, so this
# cannot fire as the code stands. It is here so that a future rewrite of the
# staging step cannot leave the assertions below sweeping an empty directory
# and reporting green - which is the failure mode this whole script exists to
# close, one level up.
if (( ${#staged[@]} < 2 )) || [[ ! -f "$STAGE_DIR/$APP_NAME" ]]; then
  echo "::error::The staged bundle has ${#staged[@]} file(s) and no $APP_NAME at" >&2
  echo "::error::its root. The layout changed and the checks below would cover" >&2
  echo "::error::almost nothing. Fix the staging before trusting a green build." >&2
  exit 1
fi

# `--strip-debug`, not the default `strip`: the symbol tables have to survive
# or nothing resolves at load. `libapp.so` is the Dart AOT snapshot, not built
# by this tree, so the strip is expected to be a no-op on it - but it is not
# skipped, and the assertions below cover it like anything else.
for f in "${staged[@]}"; do
  if is_elf "$f"; then
    strip --strip-debug "$f" \
      || { echo "::error::strip failed on $f; refusing to package it." >&2; exit 1; }
  fi
done

# Two assertions over the stripped copy. The first is the one that keeps the
# download small; the second is the one that keeps it working, because
# `--strip-debug` damaging a shared object is the #280 shape - green build,
# uploaded asset, dies at launch.
leaked=()
unloadable=()
for f in "${staged[@]}"; do
  is_elf "$f" || continue
  if has_debug_info "$f"; then
    leaked+=("$f")
  fi
  if ! has_section "$f" ".dynsym"; then
    unloadable+=("$f")
  fi
done
if (( ${#leaked[@]} )); then
  echo "::error::Debug info survived the strip and would ship to users:" >&2
  printf '  %s\n' "${leaked[@]}" >&2
  exit 1
fi
if (( ${#unloadable[@]} )); then
  echo "::error::The strip removed the dynamic symbol table from the following," >&2
  echo "::error::so they would not resolve at load:" >&2
  printf '  %s\n' "${unloadable[@]}" >&2
  exit 1
fi

# The bundle the Sentry step reads runs after this script and must still carry
# what the upload needs. Asserted because the strip above operates on a copy,
# and a refactor that stripped in place would make the leak check greener while
# silently restoring #310.
if ! has_debug_info "$BUILD_DIR/$APP_NAME"; then
  echo "::error::$BUILD_DIR/$APP_NAME lost its .debug_info while packaging. The" >&2
  echo "::error::Sentry upload step reads that bundle, not the archive." >&2
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
