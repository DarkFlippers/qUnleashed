#!/usr/bin/env bash
# Covers checksums.sh. auto-release.yml only runs on a tag push, so without this
# a regression would not surface until a release was already being cut.
#
# The fixture is chosen for what each name pins rather than to mirror the
# release: an extensionless binary, a mixed-case name, and a leading dash all
# break a plausible simplification of the script.
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

run()    { bash "$SCRIPT" "$@" 2>&1; }
check()  { local l="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$l"; else fail "$l"; fi; }
refute() { local l="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$l"; else pass "$l"; fi; }
verify() { ( cd "$1" && sha256sum -c SHA256SUMS ); }

echo "checksums.sh"

# In the byte order the script must emit, so the same list serves as fixture
# and as expectation.
names=(
  -leading-dash.bin                       # `--` guards it; without that the run dies
  QUnleashed_0.13.0_notes.txt             # mixed case pins LC_ALL=C collation
  qunleashed_0.13.0_linux_x64             # extensionless: a `*.*` glob drops it
  qunleashed_0.13.0_macos_universal.dmg   # the one the tamper case corrupts
  qunleashed_0.13.0_windows_x64.exe       # the one the mode-marker case reads
)
d="$TMP/assets"; mkdir -p "$d"
for n in "${names[@]}"; do printf '%s\n' "$n" > "$d/$n"; done
mkdir -p "$d/nested" && printf 'inner\n' > "$d/nested/inner.txt"

out="$(run "$d")" || fail "a normal run exited non-zero" "$out"

check  "output verifies with sha256sum -c" verify "$d"
check  "names are bare and the mode is binary" \
       grep -q " [*]qunleashed_0.13.0_windows_x64.exe$" "$d/SHA256SUMS"

actual="$(sed 's/^[0-9a-f]* [*]//' "$d/SHA256SUMS")"
expected="$(printf '%s\n' "${names[@]}")"
[[ "$actual" == "$expected" ]] \
  && pass "covers exactly the files, in byte order, no directory" \
  || fail "wrong file set or order" "$actual"

# The rerun is the only run where the self-exclusion is live code, because the
# glob happens before SHA256SUMS exists on a first run.
before="$(cat "$d/SHA256SUMS")"
out="$(run "$d")" || fail "a rerun exited non-zero" "$out"
[[ "$before" == "$(cat "$d/SHA256SUMS")" ]] \
  && pass "rerunning is byte-identical" || fail "output changed on rerun"
refute "the sums file excludes itself once it exists" \
       grep -q "SHA256SUMS" "$d/SHA256SUMS"

# The failure mode the file exists to catch.
printf 'tampered\n' > "$d/qunleashed_0.13.0_macos_universal.dmg"
refute "a tampered asset fails verification" verify "$d"

empty="$TMP/empty"; mkdir -p "$empty"
refute "an empty directory is refused" run "$empty"
refute "a refused run writes no manifest" test -e "$empty/SHA256SUMS"
refute "a missing directory is refused" run "$TMP/does-not-exist"

# Usage errors are exit 2, as in derive_version.sh and restore_firebase_config.sh.
check "an unknown flag exits 2" bash -c '"$1" --help; [[ $? -eq 2 ]]' _ "$SCRIPT"
check "a stray second argument exits 2" bash -c '"$1" a b; [[ $? -eq 2 ]]' _ "$SCRIPT"

if (( failures )); then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
