#!/usr/bin/env bash
# Covers derive_version.sh, which the release workflow depends on and which no
# other test can reach: auto-release.yml only ever runs on a tag push, so a
# regression there would surface while cutting a release.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVE="$HERE/derive_version.sh"
failures=0

ok() {
  local tag="$1" want="$2" got
  got="$("$DERIVE" --print "$tag")"
  if [[ "$got" == "$want" ]]; then
    printf '  ok    %-18s -> %s\n' "$tag" "$got"
  else
    printf '  FAIL  %-18s -> %s (want %s)\n' "$tag" "$got" "$want"
    failures=$((failures + 1))
  fi
}

rejects() {
  local tag="$1"
  if "$DERIVE" --print "$tag" >/dev/null 2>&1; then
    printf '  FAIL  %-18s was accepted\n' "'$tag'"
    failures=$((failures + 1))
  else
    printf '  ok    %-18s rejected\n' "'$tag'"
  fi
}

echo "derive_version.sh"

# The channel prefixes this project actually tags with.
ok "0.12.1"        "0.12.1 12001"
ok "dev-0.12.1"    "0.12.1 12001"
ok "beta-0.11.2"   "0.11.2 11002"
ok "v0.6.1"        "0.6.1 6001"

# Component scaling: patch, minor and major each land in their own decade.
ok "0.0.1"         "0.0.1 1"
ok "0.1.0"         "0.1.0 1000"
ok "1.0.0"         "1.0.0 1000000"
ok "0.10.11"       "0.10.11 10011"

# Leading zeroes must not be read as octal.
ok "0.08.09"       "0.8.9 8009"

rejects ""
rejects "no-version-here"
rejects "1.2"
rejects "0.0.0"

if (( failures )); then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
