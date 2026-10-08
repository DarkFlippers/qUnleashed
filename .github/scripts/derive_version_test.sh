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

# Writes a pubspec holding $1 as its version and echoes the path.
#
# The version comes from pubspec now (ADR 0014 §2), so a test that used to pass
# a tag has to supply one of these.
#
# mktemp and not a counter. Every call site is inside `$(...)`, so a counter
# would be incremented in a subshell and lost - every call would hand back the
# same path and the last writer would win. That is not a hypothetical: the first
# draft did it, and the shape it produced was a later fixture quietly rewriting
# the one `BASE` had captured, which showed up as an unrelated assertion failing
# on a guard it was not testing.
pubspec_with() {
  local file
  file="$(mktemp "$TMP/pubspec-XXXXXX.yaml")"
  printf 'name: qunleashed\nversion: %s\n' "$1" > "$file"
  printf '%s' "$file"
}

# The published-version guard reads `git tag` from whatever repository the suite
# runs in, which the tests cannot control. Every assertion about shape waives
# it; the two about the guard itself pass their own tags instead.
NOGUARD=QU_SKIP_PUBLISHED_GUARD=1

# --- --print mode -----------------------------------------------------------

echo "derive_version.sh --print"

# A branch build: no tag, so nothing to check the version against, which is the
# shape a push to `main` has and the reason §2 exists at all.
ok() {
  local pv="$1" want="$2" got file
  file="$(pubspec_with "$pv")"
  if ! got="$(run "$NOGUARD" QU_PUBSPEC="$file" GITHUB_REF_TYPE=branch \
      GITHUB_REF_NAME=main bash "$DERIVE" --print)"; then got="<rejected>"; fi
  [[ "$got" == "$want" ]] && pass "pubspec $pv -> $got" \
    || fail "pubspec $pv -> $got (want $want)"
}

# Component scaling: patch, minor and major each get their own three-digit field.
ok "0.0.1"         "0.0.1 1"
ok "0.1.0"         "0.1.0 1000"
ok "1.0.0"         "1.0.0 1000000"
ok "0.10.11"       "0.10.11 10011"
ok "0.11.2+11002"  "0.11.2 11002"

# Zero padding is normalized in every component, name and code alike.
ok "01.08.09"      "1.8.9 1008009"
ok "0.010.0"       "0.10.0 10000"

# The build number in pubspec is not read. It is derived, and §6 will take it
# out of pubspec altogether - so trusting it would bake in what is going away.
ok "0.11.2+99999"  "0.11.2 11002"

refute_pubspec() {
  local label="$1" pv="$2" file
  file="$(pubspec_with "$pv")"
  refutes "$label" run "$NOGUARD" QU_PUBSPEC="$file" GITHUB_REF_TYPE=branch \
    GITHUB_REF_NAME=main bash "$DERIVE" --print
}
refute_pubspec "a pubspec with no version" "not-a-version"
refute_pubspec "a two-part version"        "1.2"
refute_pubspec "a four-part version"       "1.2.3.4"
refute_pubspec "a zero version"            "0.0.0"
refutes "an unknown flag"   run bash "$DERIVE" --bogus
refutes "a missing pubspec" run "$NOGUARD" QU_PUBSPEC="$TMP/nope.yaml" \
  GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main bash "$DERIVE" --print

# --- the tag is checked against pubspec, not read for the version ------------

echo "derive_version.sh tag guard"

# Tag shapes the regex has to accept. This repository has tagged alpha- (22),
# beta- (22), wip- (5) and dev- (4); bare and v- are accepted too. Each agrees
# with the pubspec beside it, so each is a release that may be built.
agrees() {
  local tag="$1" pv="$2" got file
  file="$(pubspec_with "$pv")"
  if ! got="$(run "$NOGUARD" QU_PUBSPEC="$file" bash "$DERIVE" --print -- "$tag")"
  then got="<rejected>"; fi
  [[ "$got" == "$pv "* ]] && pass "$tag agrees with $pv" \
    || fail "$tag against $pv -> $got"
}
agrees "alpha-0.8.4" "0.8.4"
agrees "beta-0.11.2" "0.11.2"
agrees "wip-0.3.6"   "0.3.6"
agrees "dev-0.12.1"  "0.12.1"
agrees "0.12.1"      "0.12.1"
agrees "v0.6.1"      "0.6.1"

# Guard one. It would have failed the release of 2026-10-01, where the tag said
# 0.13.0 and the commit's pubspec still said 0.12.1.
file="$(pubspec_with 0.12.1)"
refutes "a tag that disagrees with pubspec" \
  run "$NOGUARD" QU_PUBSPEC="$file" bash "$DERIVE" --print -- dev-0.13.0
refutes "a tag with no version in it" \
  run "$NOGUARD" QU_PUBSPEC="$file" bash "$DERIVE" --print -- no-version-here

# Guard two, and the reason the automatic bump could be dropped: a version that
# has gone out cannot be built again. The repository the suite runs in has
# tagged dev-0.14.1, which is what makes this assertable without creating one.
file="$(pubspec_with 0.14.1)"
refutes "a version already published" \
  run QU_PUBSPEC="$file" GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main \
  bash "$DERIVE" --print

# Building the tag that published it is the one case where the match is
# expected, so it is allowed - otherwise re-running a release job would fail.
got="$(run QU_PUBSPEC="$file" bash "$DERIVE" --print -- dev-0.14.1 || true)"
[[ "$got" == "0.14.1 14001" ]] && pass "rebuilding the tag that published it" \
  || fail "rebuilding dev-0.14.1 -> '$got'"

# --- how the tag reaches the script -----------------------------------------

# The workflow passes the tag after `--` in all four call sites, so the arm that
# consumes it is load-bearing.
file="$(pubspec_with 0.11.2)"
refutes "a tag of --print is not read as a flag" \
  run "$NOGUARD" QU_PUBSPEC="$file" bash "$DERIVE" --print -- --print

# `-- ""` is the tag-push shape: an empty argument after the separator. It has
# to fall back to the ref rather than be read as a tag.
got="$(run "$NOGUARD" QU_PUBSPEC="$file" GITHUB_REF_TYPE=tag \
  GITHUB_REF_NAME=beta-0.11.2 bash "$DERIVE" --print -- "" || true)"
[[ "$got" == "0.11.2 11002" ]] && pass "-- with an empty tag falls back" \
  || fail "-- empty tag -> '$got'"

got="$(run "$NOGUARD" QU_PUBSPEC="$file" GITHUB_REF_TYPE=tag \
  GITHUB_REF_NAME=beta-0.11.2 bash "$DERIVE" --print || true)"
[[ "$got" == "0.11.2 11002" ]] && pass "--print reads GITHUB_REF_NAME" \
  || fail "--print GITHUB_REF_NAME fallback -> '$got'"

# A branch ref is not a tag that failed to parse. It used to be fatal - the
# version had nowhere else to come from - and it is now the ordinary case.
got="$(run "$NOGUARD" QU_PUBSPEC="$file" GITHUB_REF_TYPE=branch \
  GITHUB_REF_NAME=main bash "$DERIVE" --print || true)"
[[ "$got" == "0.11.2 11002" ]] && pass "a branch ref builds rather than failing" \
  || fail "a branch ref -> '$got'"

# And a ref the trigger did not call a tag must not be checked as one, however
# much it looks like one: GITHUB_REF_TYPE is what decides.
got="$(run "$NOGUARD" QU_PUBSPEC="$file" GITHUB_REF_TYPE=branch \
  GITHUB_REF_NAME=release/0.99.0 bash "$DERIVE" --print || true)"
[[ "$got" == "0.11.2 11002" ]] && pass "a branch named like a tag is still a branch" \
  || fail "a tag-shaped branch -> '$got'"

# --- $GITHUB_ENV / $GITHUB_OUTPUT mode --------------------------------------

echo "derive_version.sh (workflow mode)"

# Writes both files pre-seeded, so truncation is visible, and echoes them.
run_env() {
  local out="$TMP/env" step="$TMP/out"
  echo "PRE_EXISTING=1" > "$out"; : > "$step"
  run GITHUB_ENV="$out" GITHUB_OUTPUT="$step" "$@" bash "$DERIVE" >/dev/null || return 1
  cat "$out" "$step"
}

# The three commit defines are pinned empty wherever a test asserts the whole
# args string, so these keep checking the shape they were written for rather
# than the SHA this checkout happens to sit on. NOCOMMITS expands to the three
# pins; the cases below that do pass a commit say so explicitly.
NOCOMMITS=(QU_COMMIT= QU_COMMIT_FLIPPERLIB= QU_COMMIT_DARTUFBT=)

# Every run below asserts the shape of what reaches a build, not the guards, so
# each one is given a pubspec to read and the published-version check waived.
# `GITHUB_REF_TYPE=tag` goes with each ref as well: without it a tag-shaped ref
# is a branch, which is the right default and the wrong fixture here.
BASE=("$NOGUARD" QU_PUBSPEC="$(pubspec_with 0.11.2)")

body=""
if ! body="$(run_env "${BASE[@]}" "${NOCOMMITS[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2)"; then fail "a plain run exited non-zero"; fi

has() { grep -qxF -- "$2" <<<"$body" && pass "$1" || fail "$1 (missing: $2)"; }
has "appends, does not truncate"  "PRE_EXISTING=1"
has "writes the version name"     "QUNLEASHED_VERSION_NAME=0.11.2"
has "writes the version code"     "QUNLEASHED_VERSION_CODE=11002"
has "publishes the step outputs"  "version_name=0.11.2"
has "build args carry name+number" \
  "QUNLEASHED_FLUTTER_BUILD_ARGS=--build-name=0.11.2 --build-number=11002 --dart-define=QU_CHANNEL=release"

if ! body="$(run_env "${BASE[@]}" "${NOCOMMITS[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2 QU_BUILD_SERVER_URL=https://b QU_BUILD_SERVER_KEY=k QU_CARTO_KEY=c)"; then
  fail "a run with every secret exited non-zero"
fi
has "folds in every secret" \
  "QUNLEASHED_FLUTTER_BUILD_ARGS=--build-name=0.11.2 --build-number=11002 --dart-define=QU_CHANNEL=release --dart-define=QU_BUILD_SERVER_URL=https://b --dart-define=QU_BUILD_SERVER_KEY=k --dart-define=QU_CARTO_KEY=c"

# ADR 0014 §3: a build has to be able to name the commit it came from, and all
# three of them, because a fault can be in a submodule. Pinned rather than read
# from this checkout so the assertion does not move with HEAD.
if ! body="$(run_env "${BASE[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2 QU_COMMIT=aaaaaaa1 QU_COMMIT_FLIPPERLIB=bbbbbbb2 QU_COMMIT_DARTUFBT=ccccccc3)"; then
  fail "a run with the three commits exited non-zero"
fi
has "carries all three commits"   "QUNLEASHED_FLUTTER_BUILD_ARGS=--build-name=0.11.2 --build-number=11002 --dart-define=QU_CHANNEL=release --dart-define=QU_COMMIT=aaaaaaa1 --dart-define=QU_COMMIT_FLIPPERLIB=bbbbbbb2 --dart-define=QU_COMMIT_DARTUFBT=ccccccc3"

# A desktop job need not have the submodules checked out, and must still build.
# The app's own commit is the one that matters; the others are then absent
# rather than empty, which is what String.fromEnvironment reads as "unknown".
if ! body="$(run_env "${BASE[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2 QU_COMMIT=aaaaaaa1 QU_COMMIT_FLIPPERLIB= QU_COMMIT_DARTUFBT=)"; then
  fail "a run with no submodule commits exited non-zero"
fi
has "a submodule commit is optional"   "QUNLEASHED_FLUTTER_BUILD_ARGS=--build-name=0.11.2 --build-number=11002 --dart-define=QU_CHANNEL=release --dart-define=QU_COMMIT=aaaaaaa1"

# Unset means "work it out from the checkout", which is the path every build job
# takes. It must produce a real SHA rather than nothing - the warning branch is
# for a checkout that has no git at all.
if ! body="$(run_env "${BASE[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2)"; then
  fail "a run resolving its own commit exited non-zero"
elif grep -qE -- "--dart-define=QU_COMMIT=[0-9a-f]{40}" <<<"$body"; then
  pass "an unset commit is resolved from the checkout"
else
  fail "an unset commit was not resolved from the checkout"
fi

# A commit carrying whitespace would truncate every argument after it, the same
# hazard the secrets are guarded for.
refutes "a commit with a space" run_env "${BASE[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2 QU_COMMIT="a b"

# --- the channel ------------------------------------------------------------
#
# ADR 0014 §1. This is the field three readers used to derive for themselves,
# and the one a push to `main` cannot derive at all, because there is no tag.

echo "derive_version.sh --print-channel"

# Each tag needs the pubspec that agrees with it, since guard one runs before
# the channel is printed - a disagreement is a failure whatever was asked for.
channel() {
  local label="$1" want="$2" tag="$3"; shift 3
  local got version="${tag##*-}"
  version="${version#v}"
  if ! got="$(run "$NOGUARD" QU_PUBSPEC="$(pubspec_with "$version")" \
      GITHUB_REF_TYPE=tag GITHUB_REF_NAME="$tag" "$@" \
      bash "$DERIVE" --print-channel)"; then got="<rejected>"; fi
  [[ "$got" == "$want" ]] && pass "$label -> $got" || fail "$label -> $got (want $want)"
}

channel "a dev tag"             dev     dev-0.14.1
channel "a bare tag"            release 0.15.0
# beta- and alpha- were cut by hand, so they are releases however they sorted
# on the releases page at the time.
channel "a beta tag"            release beta-0.11.2
channel "an alpha tag"          release alpha-0.8.4

# A branch is a dev build with no tag at all, which is the case the prefix rule
# cannot reach and the reason the channel has to come from the trigger.
got="$(run "$NOGUARD" QU_PUBSPEC="$(pubspec_with 0.15.0)" GITHUB_REF_TYPE=branch \
  GITHUB_REF_NAME=main bash "$DERIVE" --print-channel || true)"
[[ "$got" == dev ]] && pass "a branch is a dev build" || fail "a branch -> '$got'"

# And the variable wins over the prefix either way, which is what lets the
# workflow say what a build is rather than have it inferred.
channel "an explicit dev wins"  dev     0.15.0      QU_CHANNEL=dev
channel "an explicit release"   release dev-0.14.1  QU_CHANNEL=release

# A typo must not ship a build labelled with it, and `local` is the app's own
# default for a build nothing told - never something CI produces.
refutes "an unknown channel" run "${BASE[@]}" GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main QU_CHANNEL=nightly bash "$DERIVE" --print-channel
refutes "local from CI"      run "${BASE[@]}" GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main QU_CHANNEL=local bash "$DERIVE" --print-channel

# The channel reaches the build the same way the version does, and the publish
# job reads it from the step output rather than testing the prefix again.
if ! body="$(run_env "$NOGUARD" QU_PUBSPEC="$(pubspec_with 0.14.1)" \
    "${NOCOMMITS[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=dev-0.14.1)"; then
  fail "a dev run exited non-zero"
fi
has "writes the channel"          "QUNLEASHED_CHANNEL=dev"
has "publishes it as an output"   "channel=dev"
has "compiles it into the build" \
  "QUNLEASHED_FLUTTER_BUILD_ARGS=--build-name=0.14.1 --build-number=14001 --dart-define=QU_CHANNEL=dev"

# A URL without a key authenticates nothing, so neither is passed.
if ! body="$(run_env "${BASE[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2 QU_BUILD_SERVER_URL=https://b)"; then
  fail "a URL without a key must still produce a build"
elif grep -q "QU_BUILD_SERVER_URL=https" <<<"$body"; then
  fail "a URL without a key must not be passed"
else
  pass "a URL without a key is dropped"
fi

# Whitespace would truncate the args when the build scripts re-split them.
refutes "a secret with a newline" run_env "${BASE[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2 QU_CARTO_KEY="$(printf 'a\nb')"
refutes "a secret with a space"   run_env "${BASE[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2 QU_CARTO_KEY="a b"
refutes "a missing GITHUB_ENV"    run "${BASE[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2 bash "$DERIVE"

# A dispatch passes an explicit tag while GITHUB_REF_NAME is a branch that the
# version regex would reject. The argument has to win, and it has to reach
# $GITHUB_ENV - the push path only ever exercises the fallback.
out="$TMP/env"; step="$TMP/out"; : > "$out"; : > "$step"
if run "$NOGUARD" QU_PUBSPEC="$(pubspec_with 0.13.0)" \
     GITHUB_ENV="$out" GITHUB_OUTPUT="$step" GITHUB_REF_NAME=main \
     bash "$DERIVE" -- beta-0.13.0 >/dev/null; then
  body="$(cat "$out" "$step")"
  has "an explicit tag beats the branch ref" "QUNLEASHED_VERSION_NAME=0.13.0"
  has "and reaches the step output"          "version_code=13000"
else
  fail "an explicit tag in workflow mode exited non-zero"
fi

# The tag is passed after `--` so operator text cannot land in the option slot.
refutes "a tag of --print is not read as a flag" \
        run GITHUB_ENV="$TMP/env2" GITHUB_REF_NAME=beta-0.13.0 \
        bash "$DERIVE" -- --print

if (( failures )); then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
