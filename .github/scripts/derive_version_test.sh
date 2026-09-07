#!/usr/bin/env bash
# Covers derive_version.sh. auto-release.yml only runs on a tag push, so without
# this a regression would not surface until a release was already being cut.
#
# Both modes are exercised, because the mode the build jobs use is the one that
# writes $GITHUB_ENV, and every consumer of those variables reads them with a
# `${VAR:-}` default or String.fromEnvironment - so a wrong name does not fail a
# build, it ships one built at the wrong version.
#
# Invocations run under `env -i` so the developer's own QU_* secrets and
# GITHUB_REF_NAME cannot change the result.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVE="$HERE/derive_version.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# --- --print mode -----------------------------------------------------------

# Runs with a clean environment; $1 is the tag, or "" to omit it entirely.
run_print() {
  if [[ -n "$1" ]]; then
    env -i PATH="$PATH" bash "$DERIVE" --print "$1" 2>/dev/null
  else
    env -i PATH="$PATH" bash "$DERIVE" --print 2>/dev/null
  fi
}

ok() {
  local tag="$1" want="$2" got
  if ! got="$(run_print "$tag")"; then got="<rejected>"; fi
  [[ "$got" == "$want" ]] && pass "$tag -> $got" || fail "$tag -> $got (want $want)"
}

rejects() {
  local tag="$1"
  if run_print "$tag" >/dev/null 2>&1; then fail "'$tag' was accepted"; else pass "'$tag' rejected"; fi
}

echo "derive_version.sh --print"

# Tag shapes the version regex has to accept. This repository has tagged
# alpha- (22), beta- (22), wip- (5) and dev- (4); bare and v- are accepted too.
ok "alpha-0.8.4"   "0.8.4 8004"
ok "beta-0.11.2"   "0.11.2 11002"
ok "wip-0.3.6"     "0.3.6 3006"
ok "dev-0.12.1"    "0.12.1 12001"
ok "0.12.1"        "0.12.1 12001"
ok "v0.6.1"        "0.6.1 6001"

# Component scaling: patch, minor and major each get their own three-digit field.
ok "0.0.1"         "0.0.1 1"
ok "0.1.0"         "0.1.0 1000"
ok "1.0.0"         "1.0.0 1000000"
ok "0.10.11"       "0.10.11 10011"

# Zero padding is normalized in every component, name and code alike.
ok "01.08.09"      "1.8.9 1008009"
ok "0.010.0"       "0.10.0 10000"

rejects "no-version-here"
rejects "1.2"
rejects "0.0.0"

# No tag argument and no GITHUB_REF_NAME: the guard, not a fallback.
if env -i PATH="$PATH" bash "$DERIVE" --print >/dev/null 2>&1; then
  fail "a missing tag was accepted"
else
  pass "a missing tag is rejected"
fi

# The sync job calls --print with no argument and relies on this fallback.
got="$(env -i PATH="$PATH" GITHUB_REF_NAME="beta-0.11.2" bash "$DERIVE" --print 2>/dev/null || true)"
[[ "$got" == "0.11.2 11002" ]] && pass "--print reads GITHUB_REF_NAME" \
  || fail "--print GITHUB_REF_NAME fallback -> '$got'"

# --- $GITHUB_ENV mode -------------------------------------------------------

echo "derive_version.sh (GITHUB_ENV mode)"

# Returns the file's contents; the file is pre-seeded so truncation is visible.
run_env() {
  local ref="$1"; shift
  local out="$TMP/env"
  echo "PRE_EXISTING=1" > "$out"
  env -i PATH="$PATH" GITHUB_ENV="$out" GITHUB_REF_NAME="$ref" "$@" \
    bash "$DERIVE" >/dev/null 2>&1 || return 1
  cat "$out"
}

env_has() {
  local label="$1" line="$2" body="$3"
  grep -qxF -- "$line" <<<"$body" && pass "$label" || fail "$label (missing: $line)"
}

if ! body="$(run_env "beta-0.11.2")"; then fail "plain run exited non-zero"; body=""; fi
env_has "appends, does not truncate"   "PRE_EXISTING=1"                 "$body"
env_has "writes the version name"      "QUNLEASHED_VERSION_NAME=0.11.2" "$body"
env_has "writes the version code"      "QUNLEASHED_VERSION_CODE=11002"  "$body"
env_has "build args carry name+number" \
  "QUNLEASHED_FLUTTER_BUILD_ARGS=--build-name=0.11.2 --build-number=11002 --dart-define=QUNLEASHED_RELEASE_TAG=beta-0.11.2" \
  "$body"

if ! body="$(run_env "beta-0.11.2" QU_BUILD_SERVER_URL=https://b QU_BUILD_SERVER_KEY=k QU_CARTO_KEY=c)"; then
  fail "run with every secret exited non-zero"; body=""
fi
env_has "folds in every secret" \
  "QUNLEASHED_FLUTTER_BUILD_ARGS=--build-name=0.11.2 --build-number=11002 --dart-define=QUNLEASHED_RELEASE_TAG=beta-0.11.2 --dart-define=QU_BUILD_SERVER_URL=https://b --dart-define=QU_BUILD_SERVER_KEY=k --dart-define=QU_CARTO_KEY=c" \
  "$body"

# A URL without a key authenticates nothing, so neither is passed.
if ! body="$(run_env "beta-0.11.2" QU_BUILD_SERVER_URL=https://b)"; then
  fail "a URL without a key must still produce a build"
elif grep -q "QU_BUILD_SERVER_URL=https" <<<"$body"; then
  fail "a URL without a key must not be passed"
else
  pass "a URL without a key is dropped"
fi

# Whitespace in a secret would truncate the args when the build scripts re-split.
if run_env "beta-0.11.2" QU_CARTO_KEY="$(printf 'a\nb')" >/dev/null 2>&1; then
  fail "a secret containing a newline was accepted"
else
  pass "a secret containing a newline is rejected"
fi
if run_env "beta-0.11.2" QU_CARTO_KEY="a b" >/dev/null 2>&1; then
  fail "a secret containing a space was accepted"
else
  pass "a secret containing a space is rejected"
fi

# GITHUB_ENV unset must fail rather than silently produce nothing.
if env -i PATH="$PATH" GITHUB_REF_NAME="beta-0.11.2" bash "$DERIVE" >/dev/null 2>&1; then
  fail "a missing GITHUB_ENV was accepted"
else
  pass "a missing GITHUB_ENV is rejected"
fi

if (( failures )); then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
