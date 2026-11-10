#!/usr/bin/env bash
# Covers elf_page_align.py by feeding it blobs directly.
#
# `verify_apks_test.sh` is the other half and covers the wiring: that
# `verify_apks.sh` passes the right ABIs, turns output into faults, and tells
# "the check found something" apart from "the check could not run". Every
# parser shape there costs a whole four-artifact `dist/`, so a mutation run
# measured 13 of 21 mutations surviving while the shell gate was the parser's
# only coverage - one of them the release blocker `elfmk.py` records.
#
# So the rule here is one case per shape, each asserting the reason and not
# merely the verdict. A script that exits non-zero for the wrong reason - or
# accepts for the wrong reason, which is worse, because it certifies - passes
# a suite that only looks at the exit status.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/elf_page_align.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PYTHONPATH="$HERE"
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/          /'
  failures=$((failures + 1))
}

# zip_of <name> <path>=<expression>...
#
# Each entry's expression is evaluated with `elfmk` imported and its value
# written at that path, so a case reads as the shape it is about. Echoes the
# archive's path, for `a="$(zip_of ...)"`.
zip_of() {
  local out="$TMP/$1.apk"; shift
  python3 - "$out" "$@" <<'PY'
import sys, zipfile, elfmk
out, entries = sys.argv[1], sys.argv[2:]
with zipfile.ZipFile(out, "w") as z:
    for spec in entries:
        path, _, expr = spec.partition("=")
        z.writestr(path, eval(expr, {"elfmk": elfmk}))
PY
  printf '%s\n' "$out"
}

# accepts <label> <apk> <abi>...
accepts() {
  local label="$1" apk="$2"; shift 2
  local out status=0
  out="$(python3 "$SCRIPT" "$apk" "$@" 2>&1)" || status=$?
  if (( status != 0 )); then
    fail "$label (exited $status)" "$out"
  elif [[ -n "$out" ]]; then
    fail "$label (reported something)" "$out"
  else
    pass "$label"
  fi
}

# finds <label> <expected substring> <apk> <abi>...
#
# A finding is output on a ZERO exit: the parser ran and the APK is bad.
finds() {
  local label="$1" want="$2" apk="$3"; shift 3
  local out status=0
  out="$(python3 "$SCRIPT" "$apk" "$@" 2>/dev/null)" || status=$?
  if (( status != 0 )); then
    fail "$label (exited $status instead of reporting)" "$out"
  elif [[ "$out" != *"$want"* ]]; then
    fail "$label (wanted \"$want\")" "${out:-<no output>}"
  else
    pass "$label"
  fi
}

# cannot_run <label> <expected substring> <apk> <abi>...
#
# Exit 2 with the reason on stderr and nothing on stdout, which is what stops
# a broken check reading as a pass.
cannot_run() {
  local label="$1" want="$2" apk="$3"; shift 3
  local err out status=0
  err="$TMP/err"
  out="$(python3 "$SCRIPT" "$apk" "$@" 2>"$err")" || status=$?
  local stderr; stderr="$(cat "$err")"
  if (( status != 2 )); then
    fail "$label (exited $status, wanted 2)" "$stderr$out"
  elif [[ "$stderr" != *"$want"* ]]; then
    fail "$label (wanted \"$want\" on stderr)" "${stderr:-<nothing on stderr>}"
  elif [[ -n "$out" ]]; then
    fail "$label (also wrote to stdout, which the caller parses as findings)" "$out"
  else
    pass "$label"
  fi
}

echo "elf_page_align.py"

# --- the two verdicts, on a well-formed library ------------------------------

a="$(zip_of ok64 "lib/arm64-v8a/libapp.so=elfmk.so(size=4096)")"
accepts "a 16 KB-aligned arm64 library passes" "$a" arm64-v8a

a="$(zip_of big "lib/arm64-v8a/libapp.so=elfmk.so(aligns=(65536,))")"
accepts "a 64 KB-aligned library passes, since every 64 KB boundary is a 16 KB one" "$a" arm64-v8a

a="$(zip_of low "lib/arm64-v8a/libapp.so=elfmk.so(aligns=(4096,))")"
finds "a 4 KB-aligned arm64 library is a finding" \
  "segments ask for 4096-byte alignment" "$a" arm64-v8a

a="$(zip_of x64low "lib/x86_64/libapp.so=elfmk.so(aligns=(4096,))")"
finds "x86_64 is judged too, not only arm64" \
  "segments ask for 4096-byte alignment" "$a" x86_64

# --- the smallest PT_LOAD decides, not the largest ---------------------------
#
# The shape the shell suite could not reach: every fixture there has one
# program header, so `max` and `min` over the segments are indistinguishable
# and a mutation between them survived. A real NDK `libc++_shared.so` has four.

a="$(zip_of mixed "lib/arm64-v8a/libapp.so=elfmk.so(aligns=(65536,4096,16384))")"
finds "a library whose segments disagree is judged on the smallest" \
  "segments ask for 4096-byte alignment" "$a" arm64-v8a

a="$(zip_of four "lib/arm64-v8a/libapp.so=elfmk.so(aligns=(16384,16384,16384,16384))")"
accepts "four segments all at 16 KB pass, as the NDK's own libc++_shared.so does" "$a" arm64-v8a

# --- 32-bit --------------------------------------------------------------

# The release blocker `elfmk.py` records. A real armeabi-v7a library is
# ELFCLASS32 and must pass there, and `ANDROID_ABIS` carries armeabi-v7a, so
# the gate ran this against every split and every universal APK.
a="$(zip_of arm32 "lib/armeabi-v7a/libapp.so=elfmk.so(size=4096,cls=32,aligns=(4096,))")"
accepts "a real 4 KB-aligned 32-bit library passes under a 32-bit ABI" "$a" armeabi-v7a

# The same bytes in the wrong place, which cannot load whatever its alignment.
a="$(zip_of arm32in64 "lib/arm64-v8a/libapp.so=elfmk.so(cls=32,aligns=(16384,))")"
finds "a 32-bit library under a 64-bit ABI is a finding" \
  "a 32-bit library under a 64-bit ABI" "$a" arm64-v8a

# --- shapes the parser cannot read an alignment out of -----------------------

a="$(zip_of stub "lib/arm64-v8a/libstub.so=b'a dependency that shipped a stub'")"
finds "a .so that is not an ELF is a finding" "not an ELF file" "$a" arm64-v8a

a="$(zip_of cut "lib/arm64-v8a/libcut.so=elfmk.so()[:20]")"
finds "a file too short to hold a header is a finding" "not an ELF file" "$a" arm64-v8a

a="$(zip_of be "lib/arm64-v8a/libbe.so=elfmk.so(endian='big')")"
finds "a big-endian ELF is a finding" "not a little-endian ELF" "$a" arm64-v8a

a="$(zip_of nodyn "lib/arm64-v8a/libdyn.so=elfmk.so(p_type=elfmk.PT_DYNAMIC)")"
finds "a table with no PT_LOAD in it is a finding" "no PT_LOAD segment" "$a" arm64-v8a

a="$(zip_of nophdr "lib/arm64-v8a/libnophdr.so=elfmk.so(phnum=0)")"
finds "no program header table at all is a finding" "no program header table" "$a" arm64-v8a

# The other half of the same guard, which the shell suite never reached.
a="$(zip_of small "lib/arm64-v8a/libsmall.so=elfmk.so(phentsize=32)")"
finds "program header entries too small for ELF64 are a finding" \
  "under the 56 an ELF64 needs" "$a" arm64-v8a

a="$(zip_of far "lib/arm64-v8a/libfar.so=elfmk.so(phoff=200000,size=300000)")"
finds "a program header table past the bytes read is a finding" \
  "is past the" "$a" arm64-v8a

# p_align 0 and 1 mean "no alignment requirement", which on a 16 KB page
# device is the misaligned case - and must not be reported as a missing
# segment, which is what a `best == 0` sentinel did.
a="$(zip_of zero "lib/arm64-v8a/libzero.so=elfmk.so(aligns=(0,))")"
finds "p_align 0 is judged as unaligned, not as a missing segment" \
  "segments ask for 1-byte alignment" "$a" arm64-v8a

# --- the gate must not pass when it inspected nothing ------------------------

a="$(zip_of nolibs "AndroidManifest.xml=b'manifest'")"
cannot_run "an APK with no libraries at all cannot be checked" \
  "no native libraries for" "$a" arm64-v8a

a="$(zip_of deep "lib/arm64-v8a/sub/libdeep.so=elfmk.so(aligns=(4096,))")"
cannot_run "a .so nested deeper than lib/<abi>/ leaves nothing to inspect" \
  "no native libraries for" "$a" arm64-v8a

# A 32-bit-only artifact legitimately carries no 64-bit library, so this is
# the one "nothing inspected" that is not an error.
a="$(zip_of only32 "lib/armeabi-v7a/libapp.so=elfmk.so(cls=32)")"
accepts "a 32-bit-only artifact is not faulted for carrying no 64-bit library" "$a" armeabi-v7a

# ABIS_64 and ANDROID_ABIS are two lists that nothing couples. A Flutter
# upgrade that adds an ABI is a red build in `verify_apks.sh`, and the fix for
# that red build is to add the name to `android_abis.sh` - which used to leave
# every library under it silently unjudged.
a="$(zip_of newabi "lib/loongarch64/libapp.so=elfmk.so(aligns=(4096,))")"
cannot_run "an ABI in neither list is refused rather than left unjudged" \
  "unknown ABI loongarch64" "$a" loongarch64

# --- the App Bundle's shape --------------------------------------------------
#
# Play takes an `.aab`, which is the artifact store users install, so the gate
# has to read it as well as the APKs. A bundle puts the same tree inside its
# base module, one level deeper.

a="$(zip_of aabok "base/lib/arm64-v8a/libapp.so=elfmk.so(size=4096)")"
accepts "a 16 KB-aligned library in a bundle's base module passes" "$a" arm64-v8a

a="$(zip_of aablow "base/lib/arm64-v8a/libapp.so=elfmk.so(aligns=(4096,))")"
finds "a 4 KB-aligned library in a bundle is a finding" \
  "segments ask for 4096-byte alignment" "$a" arm64-v8a

a="$(zip_of aab32 "base/lib/armeabi-v7a/libapp.so=elfmk.for_abi('armeabi-v7a',size=4096,aligns=(4096,))")"
accepts "a bundle's 32-bit library passes, as in an APK" "$a" armeabi-v7a

# Only `base`. A dynamic feature module is not installed with the base, so its
# libraries are a different question - and this app has none, so the answer is
# "nothing was inspected" rather than a guess.
a="$(zip_of aabfeature "extra/lib/arm64-v8a/libapp.so=elfmk.so(aligns=(4096,))")"
cannot_run "libraries outside the base module leave nothing to inspect" \
  "no native libraries for" "$a" arm64-v8a

a="$(zip_of aabdeep "base/lib/arm64-v8a/sub/libdeep.so=elfmk.so(aligns=(4096,))")"
cannot_run "a .so nested deeper inside a bundle leaves nothing to inspect" \
  "no native libraries for" "$a" arm64-v8a

# --- it cannot read the archive ---------------------------------------------

printf 'not a zip\n' > "$TMP/notzip.apk"
cannot_run "an unreadable archive cannot be checked" \
  "could not read" "$TMP/notzip.apk" arm64-v8a

cannot_run "a missing archive cannot be checked" \
  "could not read" "$TMP/does-not-exist.apk" arm64-v8a

# --- findings are per library, and every one is named ------------------------

a="$(zip_of many \
  "lib/arm64-v8a/liba.so=elfmk.so(aligns=(4096,))" \
  "lib/arm64-v8a/libb.so=elfmk.so(aligns=(8192,))" \
  "lib/arm64-v8a/libc.so=elfmk.so(aligns=(16384,))")"
out="$(python3 "$SCRIPT" "$a" arm64-v8a 2>/dev/null)"
if [[ "$(grep -c . <<<"$out")" == 2 && "$out" == *liba.so* && "$out" == *libb.so* && "$out" != *libc.so* ]]; then
  pass "each offending library is reported once and the good one is not"
else
  fail "each offending library is reported once and the good one is not" "$out"
fi

# `libapp.so.sym` is not a `.so`, and the exact-suffix match is what keeps it
# out. A substring match would report Flutter's symbol file as a stub.
a="$(zip_of sym \
  "lib/arm64-v8a/libapp.so=elfmk.so()" \
  "lib/arm64-v8a/libapp.so.sym=b'symbols'")"
accepts "a sibling .so.sym is not mistaken for a library" "$a" arm64-v8a

if (( failures )); then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
