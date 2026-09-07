#!/usr/bin/env bash
# Covers verify_apks.sh. auto-release.yml only runs on a tag push, so without
# this a regression would not surface until a release was already being cut.
#
# An APK is a zip, so the fixtures are built with python's zipfile and need no
# Android toolchain. Every negative case asserts the message as well as the
# exit status: a script that merely exits non-zero for the wrong reason - or
# dies on a syntax error - would otherwise satisfy almost the whole suite.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/verify_apks.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/          /'
  failures=$((failures + 1))
}

run() { bash "$SCRIPT" "$@" 2>&1; }

# accepts <label> <dir>
accepts() {
  local out
  if out="$(run "$2")"; then pass "$1"; else fail "$1" "$out"; fi
}

# refuses <label> <dir> <expected message substring>
refuses() {
  local out
  if out="$(run "$2")"; then
    fail "$1 (was accepted)" "$out"
  elif [[ "$out" != *"$3"* ]]; then
    fail "$1 (refused for the wrong reason; wanted \"$3\")" "$out"
  else
    pass "$1"
  fi
}

# A snapshot large enough to clear the script's floor.
SNAPSHOT_BYTES=$((1024 * 1024 + 32))

# apk <path> <abi>...
apk() {
  python3 - "$SNAPSHOT_BYTES" "$@" <<'PY'
import sys, zipfile
size, path, abis = int(sys.argv[1]), sys.argv[2], sys.argv[3:]
with zipfile.ZipFile(path, "w") as z:
    z.writestr("AndroidManifest.xml", "manifest")
    z.writestr("classes.dex", "dex")
    z.writestr("classes2.dex", "dex")          # real APKs have these; must not confuse the check
    z.writestr("resources.arsc", "res")
    z.writestr("assets/flutter_assets/lib/fonts/x.ttf", "font")
    for abi in abis:
        z.writestr(f"lib/{abi}/libapp.so", b"\0" * size)
        z.writestr(f"lib/{abi}/libflutter.so", "engine")
        z.writestr(f"lib/{abi}/libapp.so.sym", "symbols")  # superstring; pins the exact-line match
PY
}

# apk_omitting <path> <prefix-to-omit> <abi>...  (prefix drops a file or a whole tree)
apk_omitting() {
  python3 - "$SNAPSHOT_BYTES" "$@" <<'PY'
import sys, zipfile
size, path, omit, abis = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4:]
with zipfile.ZipFile(path, "w") as z:
    for entry in ("AndroidManifest.xml", "classes.dex"):
        if not entry.startswith(omit):
            z.writestr(entry, "body")
    for abi in abis:
        if not f"lib/{abi}/libapp.so".startswith(omit):
            z.writestr(f"lib/{abi}/libapp.so", b"\0" * size)
        # Kept even when libapp.so is omitted, so a substring match would
        # wrongly satisfy the snapshot check. Only a dropped tree removes it.
        if not (omit.endswith("/") and f"lib/{abi}/libapp.so.sym".startswith(omit)):
            z.writestr(f"lib/{abi}/libapp.so.sym", "symbols")
        if not f"lib/{abi}/libflutter.so".startswith(omit):
            z.writestr(f"lib/{abi}/libflutter.so", "engine")
PY
}

good_set() {
  local d="$1"; mkdir -p "$d"
  apk "$d/qunleashed_0.13.0_android_universal.apk"   armeabi-v7a arm64-v8a x86_64
  apk "$d/qunleashed_0.13.0_android_armeabi-v7a.apk" armeabi-v7a
  apk "$d/qunleashed_0.13.0_android_arm64-v8a.apk"   arm64-v8a
  apk "$d/qunleashed_0.13.0_android_x86_64.apk"      x86_64
}

echo "verify_apks.sh"

d="$TMP/good"; good_set "$d"
accepts "a complete artifact set passes" "$d"

d="$TMP/no-snapshot"; good_set "$d"
apk_omitting "$d/qunleashed_0.13.0_android_arm64-v8a.apk" "lib/arm64-v8a/libapp.so" arm64-v8a
refuses "a split APK missing libapp.so is refused" "$d" "the Dart snapshot is missing"

# The task stages nothing when the per-ABI directory is absent, so the APK has
# no lib/ tree at all - not merely a missing file.
d="$TMP/no-lib-tree"; good_set "$d"
apk_omitting "$d/qunleashed_0.13.0_android_x86_64.apk" "lib/x86_64/" x86_64
refuses "an APK with no lib/ tree at all is refused" "$d" "the Dart snapshot is missing"

# Present is not populated.
d="$TMP/empty-snapshot"; good_set "$d"
python3 - "$d/qunleashed_0.13.0_android_x86_64.apk" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("AndroidManifest.xml", "manifest")
    z.writestr("classes.dex", "dex")
    z.writestr("lib/x86_64/libapp.so", b"")
PY
refuses "a zero-byte libapp.so is refused" "$d" "expected at least"

# The listing reads only the central directory, so entry data must be checked.
d="$TMP/corrupt-data"; good_set "$d"
python3 - "$d/qunleashed_0.13.0_android_x86_64.apk" <<'PY'
import sys, zipfile, io
path = sys.argv[1]
raw = bytearray(open(path, "rb").read())
end = raw.rfind(b"PK\x01\x02")           # start of the central directory
raw[:end] = b"\0" * end                  # obliterate the entry data, keep the index
open(path, "wb").write(bytes(raw))
PY
refuses "an APK whose data is corrupt but listable is refused" "$d" "failed its integrity check"

d="$TMP/universal-partial"; good_set "$d"
apk "$d/qunleashed_0.13.0_android_universal.apk" armeabi-v7a arm64-v8a
refuses "a universal APK missing an ABI is refused" "$d" "the Dart snapshot is missing"

d="$TMP/unsplit"; good_set "$d"
apk "$d/qunleashed_0.13.0_android_x86_64.apk" armeabi-v7a arm64-v8a x86_64
refuses "a split APK carrying other ABIs is refused" "$d" "carries an unexpected ABI"

d="$TMP/no-manifest"; good_set "$d"
apk_omitting "$d/qunleashed_0.13.0_android_x86_64.apk" "AndroidManifest.xml" x86_64
refuses "an APK with no AndroidManifest.xml is refused" "$d" "has no AndroidManifest.xml"

d="$TMP/no-dex"; good_set "$d"
apk_omitting "$d/qunleashed_0.13.0_android_universal.apk" "classes.dex" armeabi-v7a arm64-v8a x86_64
refuses "an APK with no classes.dex is refused" "$d" "has no classes.dex"

d="$TMP/unreadable"; good_set "$d"
printf 'not a zip\n' > "$d/qunleashed_0.13.0_android_x86_64.apk"
refuses "an unreadable APK is refused" "$d" "failed its integrity check"

d="$TMP/stray"; good_set "$d"
apk "$d/qunleashed_0.13.0_android_riscv64.apk" riscv64
refuses "an artifact with an unrecognised name is refused" "$d" "does not match any known"

# The build guards this too, but this is the gate that must not trust the build.
d="$TMP/partial-set"; mkdir -p "$d"
apk "$d/qunleashed_0.13.0_android_universal.apk" armeabi-v7a arm64-v8a x86_64
refuses "an incomplete artifact set is refused" "$d" "No armeabi-v7a APK"

d="$TMP/no-universal"; mkdir -p "$d"
apk "$d/qunleashed_0.13.0_android_armeabi-v7a.apk" armeabi-v7a
apk "$d/qunleashed_0.13.0_android_arm64-v8a.apk"   arm64-v8a
apk "$d/qunleashed_0.13.0_android_x86_64.apk"      x86_64
refuses "a set with no universal APK is refused" "$d" "No universal APK"

d="$TMP/empty"; mkdir -p "$d"
refuses "a directory with no APKs is refused" "$d" "No Android APKs found"
refuses "a missing directory is refused" "$TMP/does-not-exist" "No Android APKs found"

# One run must report every problem, not stop at the first.
d="$TMP/many"; good_set "$d"
apk_omitting "$d/qunleashed_0.13.0_android_x86_64.apk" "classes.dex" x86_64
apk_omitting "$d/qunleashed_0.13.0_android_arm64-v8a.apk" "lib/arm64-v8a/libapp.so" arm64-v8a
out="$(run "$d" || true)"
if [[ "$out" == *"has no classes.dex"* && "$out" == *"the Dart snapshot is missing"* ]]; then
  pass "one run reports every broken artifact"
else
  fail "one run reports every broken artifact" "$out"
fi

# A rejected artifact must not also be logged as ok.
if [[ "$out" == *"  ok  qunleashed_0.13.0_android_x86_64.apk"* ]]; then
  fail "a failing APK is still logged as ok" "$out"
else
  pass "a failing APK is not logged as ok"
fi

if (( failures )); then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
