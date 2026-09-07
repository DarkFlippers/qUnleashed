#!/usr/bin/env bash
# Covers derive_version.sh. auto-release.yml only runs on a tag push, so without
# this a regression would not surface until a release was already being cut.
#
# Both modes are exercised, because the mode the build jobs use is the one that
# writes $GITHUB_ENV, and every consumer of those variables reads them with a
# `${VAR:-}` default or String.fromEnvironment - so a wrong name does not fail a
# build, it ships one built at the wrong version.
#
# Every invocation runs under `env -i` so the developer's own QU_* secrets and
# GITHUB_REF_NAME cannot change a result.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVE="$HERE/derive_version.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# Runs the script with a clean environment. Extra NAME=VALUE pairs go before the
# command; the tag, when given, goes after `--print`.
run() { env -i PATH="$PATH" "$@" 2>/dev/null; }

# Asserts that a command fails. Every negative case shares this shape.
refutes() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$label was accepted"; else pass "$label rejected"; fi
}

# --- --print mode -----------------------------------------------------------

echo "derive_version.sh --print"

ok() {
  local tag="$1" want="$2" got
  if ! got="$(run bash "$DERIVE" --print "$tag")"; then got="<rejected>"; fi
  [[ "$got" == "$want" ]] && pass "$tag -> $got" || fail "$tag -> $got (want $want)"
}

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

refutes "no-version-here" run bash "$DERIVE" --print "no-version-here"
refutes "1.2"             run bash "$DERIVE" --print "1.2"
refutes "0.0.0"           run bash "$DERIVE" --print "0.0.0"
refutes "an unknown flag" run bash "$DERIVE" --bogus
refutes "a missing tag"   run bash "$DERIVE" --print

# The tag falls back to GITHUB_REF_NAME when no argument is given.
got="$(run GITHUB_REF_NAME=beta-0.11.2 bash "$DERIVE" --print || true)"
[[ "$got" == "0.11.2 11002" ]] && pass "--print reads GITHUB_REF_NAME" \
  || fail "--print GITHUB_REF_NAME fallback -> '$got'"

# --- $GITHUB_ENV / $GITHUB_OUTPUT mode --------------------------------------

echo "derive_version.sh (workflow mode)"

# Writes both files pre-seeded, so truncation is visible, and echoes them.
run_env() {
  local out="$TMP/env" step="$TMP/out"
  echo "PRE_EXISTING=1" > "$out"; : > "$step"
  run GITHUB_ENV="$out" GITHUB_OUTPUT="$step" "$@" bash "$DERIVE" >/dev/null || return 1
  cat "$out" "$step"
}

body=""
if ! body="$(run_env GITHUB_REF_NAME=beta-0.11.2)"; then fail "a plain run exited non-zero"; fi

has() { grep -qxF -- "$2" <<<"$body" && pass "$1" || fail "$1 (missing: $2)"; }
has "appends, does not truncate"  "PRE_EXISTING=1"
has "writes the version name"     "QUNLEASHED_VERSION_NAME=0.11.2"
has "writes the version code"     "QUNLEASHED_VERSION_CODE=11002"
has "publishes the step outputs"  "version_name=0.11.2"
has "build args carry name+number" \
  "QUNLEASHED_FLUTTER_BUILD_ARGS=--build-name=0.11.2 --build-number=11002 --dart-define=QUNLEASHED_RELEASE_TAG=beta-0.11.2"

if ! body="$(run_env GITHUB_REF_NAME=beta-0.11.2 QU_BUILD_SERVER_URL=https://b QU_BUILD_SERVER_KEY=k QU_CARTO_KEY=c)"; then
  fail "a run with every secret exited non-zero"
fi
has "folds in every secret" \
  "QUNLEASHED_FLUTTER_BUILD_ARGS=--build-name=0.11.2 --build-number=11002 --dart-define=QUNLEASHED_RELEASE_TAG=beta-0.11.2 --dart-define=QU_BUILD_SERVER_URL=https://b --dart-define=QU_BUILD_SERVER_KEY=k --dart-define=QU_CARTO_KEY=c"

# A URL without a key authenticates nothing, so neither is passed.
if ! body="$(run_env GITHUB_REF_NAME=beta-0.11.2 QU_BUILD_SERVER_URL=https://b)"; then
  fail "a URL without a key must still produce a build"
elif grep -q "QU_BUILD_SERVER_URL=https" <<<"$body"; then
  fail "a URL without a key must not be passed"
else
  pass "a URL without a key is dropped"
fi

# Whitespace would truncate the args when the build scripts re-split them.
refutes "a secret with a newline" run_env GITHUB_REF_NAME=beta-0.11.2 QU_CARTO_KEY="$(printf 'a\nb')"
refutes "a secret with a space"   run_env GITHUB_REF_NAME=beta-0.11.2 QU_CARTO_KEY="a b"
refutes "a missing GITHUB_ENV"    run GITHUB_REF_NAME=beta-0.11.2 bash "$DERIVE"

if (( failures )); then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
