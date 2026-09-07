#!/usr/bin/env bash
# Covers checksums.sh. The release job that calls it only runs on a tag push,
# so this is the only place a regression can surface before a release.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/checksums.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

echo "checksums.sh"

d="$TMP/assets"; mkdir -p "$d"
printf 'apk\n'  > "$d/qunleashed_0.13.0_android_arm64-v8a.apk"
printf 'dmg\n'  > "$d/qunleashed_0.13.0_macos_universal.dmg"
printf 'exe\n'  > "$d/qunleashed_0.13.0_windows_x64.exe"
mkdir -p "$d/nested"

bash "$SCRIPT" "$d" >/dev/null 2>&1 || fail "a normal run exited non-zero"

# The whole point: the file has to verify with the standard tool.
( cd "$d" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ) \
  && pass "output verifies with sha256sum -c" || fail "sha256sum -c rejected the output"

grep -q " [*]qunleashed_0.13.0_windows_x64.exe$" "$d/SHA256SUMS" \
  && pass "names are bare and the mode is binary" || fail "wrong name or mode marker"

[[ "$(wc -l < "$d/SHA256SUMS")" -eq 3 ]] \
  && pass "covers every file and no directory" || fail "wrong line count"

grep -q "SHA256SUMS" "$d/SHA256SUMS" && fail "the sums file lists itself" \
  || pass "the sums file does not list itself"

# Deterministic: rerunning over unchanged assets must not churn the file.
before="$(cat "$d/SHA256SUMS")"
bash "$SCRIPT" "$d" >/dev/null 2>&1
[[ "$before" == "$(cat "$d/SHA256SUMS")" ]] \
  && pass "rerunning is byte-identical" || fail "output changed on rerun"

# A tampered asset must be caught, which is the only reason the file exists.
printf 'tampered\n' > "$d/qunleashed_0.13.0_macos_universal.dmg"
( cd "$d" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ) \
  && fail "a tampered asset still verified" || pass "a tampered asset fails verification"

empty="$TMP/empty"; mkdir -p "$empty"
bash "$SCRIPT" "$empty" >/dev/null 2>&1 \
  && fail "an empty directory was accepted" || pass "an empty directory is refused"

bash "$SCRIPT" "$TMP/does-not-exist" >/dev/null 2>&1 \
  && fail "a missing directory was accepted" || pass "a missing directory is refused"

if (( failures )); then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
