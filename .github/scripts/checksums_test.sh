#!/usr/bin/env bash
# Covers checksums.sh. auto-release.yml only runs on a tag push, so without this
# a regression would not surface until a release was already being cut.
#
# The fixture mirrors the real asset set on purpose, including the extensionless
# Linux binary: a mutation as small as globbing `*.*` instead of `*` drops every
# extensionless asset, and a fixture of only .apk/.dmg/.exe cannot see it.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/checksums.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/          /'
  failures=$((failures + 1))
}

# Runs the script, keeping its output so a failure can say why.
run() {
  local out
  if out="$(bash "$SCRIPT" "$@" 2>&1)"; then printf '%s' "$out"; return 0; fi
  printf '%s' "$out"; return 1
}

echo "checksums.sh"

d="$TMP/assets"; mkdir -p "$d"
printf 'apk\n'   > "$d/qunleashed_0.13.0_android_arm64-v8a.apk"
printf 'ipa\n'   > "$d/qunleashed_0.13.0_ios_arm64.ipa"
printf 'linux\n' > "$d/qunleashed_0.13.0_linux_x64"
printf 'dmg\n'   > "$d/qunleashed_0.13.0_macos_universal.dmg"
printf 'exe\n'   > "$d/qunleashed_0.13.0_windows_x64.exe"
# Mixed case pins the byte-wise order: under a UTF-8 locale it collates after
# the lowercase names, under LC_ALL=C before them.
printf 'notes\n' > "$d/QUnleashed_0.13.0_notes.txt"
# A leading dash is what `--` protects against; without it sha256sum reads the
# name as an option and the run dies.
printf 'dash\n'  > "$d/-leading-dash.bin"
mkdir -p "$d/nested" && printf 'inner\n' > "$d/nested/inner.txt"

out="$(run "$d")" || fail "a normal run exited non-zero" "$out"

( cd "$d" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ) \
  && pass "output verifies with sha256sum -c" || fail "sha256sum -c rejected the output"

grep -q " [*]qunleashed_0.13.0_windows_x64.exe$" "$d/SHA256SUMS" \
  && pass "names are bare and the mode is binary" || fail "wrong name or mode marker"

# The asset with no extension is the one a careless glob silently drops.
grep -q " [*]qunleashed_0.13.0_linux_x64$" "$d/SHA256SUMS" \
  && pass "the extensionless Linux binary is covered" || fail "extensionless asset dropped"

# Names, not just a count: this pins the exact set and catches a lost sort too.
expected="-leading-dash.bin
QUnleashed_0.13.0_notes.txt
qunleashed_0.13.0_android_arm64-v8a.apk
qunleashed_0.13.0_ios_arm64.ipa
qunleashed_0.13.0_linux_x64
qunleashed_0.13.0_macos_universal.dmg
qunleashed_0.13.0_windows_x64.exe"
actual="$(sed 's/^[0-9a-f]* [*]//' "$d/SHA256SUMS")"
[[ "$actual" == "$expected" ]] \
  && pass "covers exactly the files, in byte order, no directory" \
  || fail "wrong file set or order" "$actual"

# Rerunning must not churn the file, and on this run SHA256SUMS already exists -
# which is the only run where the self-exclusion is live code.
before="$(cat "$d/SHA256SUMS")"
out="$(run "$d")" || fail "a rerun exited non-zero" "$out"
[[ "$before" == "$(cat "$d/SHA256SUMS")" ]] \
  && pass "rerunning is byte-identical" || fail "output changed on rerun"
grep -q "SHA256SUMS" "$d/SHA256SUMS" && fail "the sums file lists itself on rerun" \
  || pass "the sums file excludes itself once it exists"

# The failure mode the file exists to catch.
printf 'tampered\n' > "$d/qunleashed_0.13.0_macos_universal.dmg"
( cd "$d" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ) \
  && fail "a tampered asset still verified" || pass "a tampered asset fails verification"

# A partial download must not leave a manifest behind for a later step to ship.
part="$TMP/partial"; mkdir -p "$part"; printf 'ok\n' > "$part/good.apk"
ln -s "$TMP/absent" "$part/dangling.apk" 2>/dev/null || true
rm -f "$part/SHA256SUMS"

empty="$TMP/empty"; mkdir -p "$empty"
run "$empty" >/dev/null 2>&1 && fail "an empty directory was accepted" \
  || pass "an empty directory is refused"
[[ ! -e "$empty/SHA256SUMS" ]] \
  && pass "a refused run writes no manifest" || fail "a refused run left a manifest"

run "$TMP/does-not-exist" >/dev/null 2>&1 && fail "a missing directory was accepted" \
  || pass "a missing directory is refused"

if (( failures )); then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
