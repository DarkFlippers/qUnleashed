#!/usr/bin/env bash
# Covers derive_version.sh, which now turns every trigger into a build
# identity: a push to `main` as well as a release tag.
#
# A regression surfaces on the next merge rather than at the next release, now
# that `main` builds - but a wrong *value* still ships silently, because every
# consumer reads these variables with a `${VAR:-}` default or
# String.fromEnvironment. Nothing fails; a build just goes out claiming to be
# something it is not. That is why both modes are exercised and why the
# env-mode assertions pin the whole argument string literally.
#
# Every invocation runs under `env -i` so the developer's own QU_* secrets and
# GITHUB_REF_NAME cannot change a result, and the assertions that read git use
# a fixture repository rather than this checkout - `ci.yml` clones shallow and
# with no tags, so borrowing the ambient history was red in CI and green
# locally.
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
# would be incremented in a subshell and lost - every call would hand back
# the same path and the last writer would win.
pubspec_with() {
  local file
  file="$(mktemp "$TMP/pubspec-XXXXXX")"
  printf 'name: qunleashed\nversion: %s\n' "$1" > "$file"
  printf '%s' "$file"
}

# The published-version guard reads `git tag`, and there is no way to switch it
# off - a skip-the-guard lever in shipped CI code was its own hazard. So every
# assertion runs the guard for real, against a repository with no tags, and
# passes it by construction. NOTAGS is that repository; the guard's own
# assertions use PUBLISHED_REPO, which has some.
#
# Defined after fixture_repo and before its first use.

# A repository with $1 commits and the tags named after it, echoing its path.
#
# Owned rather than borrowed. These used to read the qUnleashed checkout's own
# tags and commits, which failed two ways at once: `ci.yml` checks out shallow
# and with no tags, so the guard assertion was red in CI and the exemption
# beside it passed vacuously - with no tags the loop never runs, so deleting the
# "building the tag that published it is allowed" branch would not have been
# caught. That branch is what lets a failed release job be re-run.
fixture_repo() {
  local commits="$1"; shift
  local dir
  dir="$(mktemp -d "$TMP/repo-XXXXXX")"
  (
    cd "$dir"
    git init -q .
    git config user.email t@example.com
    git config user.name Test
    local i
    for (( i = 0; i < commits; i++ )); do
      git commit -q --allow-empty -m "commit $i"
    done
    local tag
    for tag in "$@"; do git tag "$tag"; done
  ) >/dev/null 2>&1
  printf '%s' "$dir"
}

# A repository that has published 0.14.1, 0.10.10 and 0.11.0, built once
# because several assertions share it. The prefixes are the ones this project
# has used, including a `dev-` one, so the boundary cases below are checked
# against tag text that really occurs.
PUBLISHED_REPO="$(fixture_repo 3 beta-0.14.1 beta-0.10.10 dev-0.11.0)"
NOTAGS=QU_REPO_ROOT="$(fixture_repo 1)"

# --- --print mode -----------------------------------------------------------

echo "derive_version.sh --print"

# A branch build: no tag, so nothing to check the version against, which is the
# shape a push to `main` has and the reason §2 exists at all. The commit count
# is pinned so the assertion is about the name; the number has its own section.
COUNT=QU_COMMIT_COUNT=808

ok() {
  local pv="$1" want="$2" got file
  file="$(pubspec_with "$pv")"
  if ! got="$(run "$NOTAGS" "$COUNT" QU_PUBSPEC="$file" GITHUB_REF_TYPE=branch \
      GITHUB_REF_NAME=main bash "$DERIVE" --print)"; then got="<rejected>"; fi
  [[ "$got" == "$want 108080" ]] && pass "pubspec $pv -> $got" \
    || fail "pubspec $pv -> $got (want '$want 108080')"
}

ok "0.0.1"         "0.0.1"
ok "0.1.0"         "0.1.0"
ok "1.0.0"         "1.0.0"
ok "0.10.11"       "0.10.11"
ok "0.11.2+11002"  "0.11.2"

# Zero padding is normalized in every component. It has to be, because the tag
# is compared against this and `0.08.09` must not read as a different version
# from `0.8.9`.
ok "01.08.09"      "1.8.9"
ok "0.010.0"       "0.10.0"

# The build number in pubspec is not read - §6 derives it, and it does not come
# from the name at all any more, so a stale `+` in pubspec means nothing.
ok "0.11.2+99999"  "0.11.2"

refute_pubspec() {
  local label="$1" pv="$2" file
  file="$(pubspec_with "$pv")"
  refutes "$label" run "$NOTAGS" "$COUNT" QU_PUBSPEC="$file" \
    GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main bash "$DERIVE" --print
}
refute_pubspec "a pubspec with no version" "not-a-version"
refute_pubspec "a two-part version"        "1.2"
refute_pubspec "a four-part version"       "1.2.3.4"
refute_pubspec "a zero version"            "0.0.0"
refutes "an unknown flag"   run bash "$DERIVE" --bogus
refutes "a missing pubspec" run "$NOTAGS" "$COUNT" QU_PUBSPEC="$TMP/nope.yaml" \
  GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main bash "$DERIVE" --print

# --- the build number -------------------------------------------------------
#
# §6: 100000 + commits × 10 + slot. Decoupled from the name, because §2 makes
# every dev build in a cycle share one name - so the name carries no ordering
# and the number has to carry all of it.

echo "derive_version.sh build number"

number() {
  local label="$1" want="$2" got
  shift 2
  if ! got="$(run "$NOTAGS" QU_PUBSPEC="$(pubspec_with 0.15.0)" "$@" \
      bash "$DERIVE" --print)"; then got="<rejected>"; fi
  [[ "$got" == "0.15.0 $want" ]] && pass "$label -> $got" \
    || fail "$label -> $got (want '0.15.0 $want')"
}

# A dev build takes slot 0; the tenth commit is ten higher than the first.
number "a dev build at 808 commits" 108080 \
  QU_COMMIT_COUNT=808 GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main
number "one commit later"           108090 \
  QU_COMMIT_COUNT=809 GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main

# The floor clears every number ever shipped - the highest is 14001 - so
# nothing has to remember the high-water mark.
number "the first commit"           100010 \
  QU_COMMIT_COUNT=1 GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main

# A release takes the attempt, so re-running a failed release job produces a
# number the store has not already refused - and so a release tagged at a
# commit a dev build already came from differs from it.
number "a release, first attempt"   108081 \
  QU_COMMIT_COUNT=808 GITHUB_REF_TYPE=tag GITHUB_REF_NAME=0.15.0 GITHUB_RUN_ATTEMPT=1
number "a release, third attempt"   108083 \
  QU_COMMIT_COUNT=808 GITHUB_REF_TYPE=tag GITHUB_REF_NAME=0.15.0 GITHUB_RUN_ATTEMPT=3
number "a release with no attempt"  108081 \
  QU_COMMIT_COUNT=808 GITHUB_REF_TYPE=tag GITHUB_REF_NAME=0.15.0

# A dev re-run collides with itself, deliberately: the build is disposable, the
# rolling prerelease is overwritten anyway, and the fix is another commit.
number "a dev re-run collides"      108080 \
  QU_COMMIT_COUNT=808 GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main GITHUB_RUN_ATTEMPT=4

refute_number() {
  local label="$1"; shift
  refutes "$label" run "$NOTAGS" QU_PUBSPEC="$(pubspec_with 0.15.0)" "$@" \
    GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main bash "$DERIVE" --print
}
# Ten slots per commit and no more. A tenth attempt wants a new commit rather
# than a number that has run into the next one's.
refute_number "a tenth attempt" QU_COMMIT_COUNT=808 QU_CHANNEL=release GITHUB_RUN_ATTEMPT=10
refute_number "a count of zero" QU_COMMIT_COUNT=0
refute_number "a count that is not a number" QU_COMMIT_COUNT=lots

# --- the tag is checked against pubspec, not read for the version ------------

echo "derive_version.sh tag guard"

# Tag shapes the regex has to accept. This repository has tagged alpha- (22),
# beta- (22), dev- (7) and wip- (5); bare and v- are accepted too. Each agrees
# with the pubspec beside it, so each is a release that may be built - except
# dev-, which is refused outright now (see below).
agrees() {
  local tag="$1" pv="$2" got file
  file="$(pubspec_with "$pv")"
  if ! got="$(run "$NOTAGS" "$COUNT" QU_PUBSPEC="$file" bash "$DERIVE" --print -- "$tag")"
  then got="<rejected>"; fi
  [[ "$got" == "$pv "* ]] && pass "$tag agrees with $pv" \
    || fail "$tag against $pv -> $got"
}
agrees "alpha-0.8.4" "0.8.4"
agrees "beta-0.11.2" "0.11.2"
agrees "wip-0.3.6"   "0.3.6"
agrees "0.12.1"      "0.12.1"
agrees "v0.6.1"      "0.6.1"

# A dev- tag is refused, and this is the assertion that matters most in the
# file. `dev` is the rolling prerelease now, so mapping the prefix to the dev
# channel would make a pushed dev-0.15.0 delete and recreate that prerelease,
# leave its own tag with no release and no assets, label the binaries a dev
# build and take slot 0 - colliding with the dev build already made from that
# commit. Every job would have succeeded. Seven of this repository's tags are
# dev-, so it is the shape habit reaches for.
file="$(pubspec_with 0.15.0)"
refutes "a dev- tag"   run "$NOTAGS" "$COUNT" QU_PUBSPEC="$file" bash "$DERIVE" --print -- dev-0.15.0

# Anchored, which 0014's Consequences asked for: unanchored, a release
# candidate matched the release's version and built claiming to be it.
refutes "a release candidate suffix"   run "$NOTAGS" "$COUNT" QU_PUBSPEC="$file" bash "$DERIVE" --print -- beta-0.15.0-rc1
refutes "a fourth component"   run "$NOTAGS" "$COUNT" QU_PUBSPEC="$file" bash "$DERIVE" --print -- 0.15.0.1
refutes "anything after the patch"   run "$NOTAGS" "$COUNT" QU_PUBSPEC="$file" bash "$DERIVE" --print -- 0.15.0-hotfix

# Guard one. It would have failed the release of 2026-10-01, where the tag said
# 0.13.0 and the commit's pubspec still said 0.12.1.
file="$(pubspec_with 0.12.1)"
refutes "a tag that disagrees with pubspec" \
  run "$NOTAGS" "$COUNT" QU_PUBSPEC="$file" bash "$DERIVE" --print -- beta-0.13.0
refutes "a tag with no version in it" \
  run "$NOTAGS" "$COUNT" QU_PUBSPEC="$file" bash "$DERIVE" --print -- no-version-here

# Guard two, and the reason the automatic bump could be dropped: a version that
# has gone out cannot be built again. Against the owned fixture, which has
# published 0.14.1, 0.10.10 and 0.11.0.
in_repo() { run "$COUNT" QU_REPO_ROOT="$PUBLISHED_REPO" "$@"; }

file="$(pubspec_with 0.14.1)"
refutes "a version already published" \
  in_repo QU_PUBSPEC="$file" GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main \
  bash "$DERIVE" --print

# Building the tag that published it is the one case where the match is
# expected, so it is allowed - otherwise re-running a release job would fail.
# Against the repository's own tags this passed vacuously: with none fetched
# the loop never ran, so deleting this branch of the guard would not have been
# caught, and that branch is what lets a failed release be rebuilt.
got="$(in_repo QU_PUBSPEC="$file" QU_COMMIT=aaaaaaa1 bash "$DERIVE" --print -- beta-0.14.1 || true)"
[[ "$got" == "0.14.1 108081" ]] && pass "rebuilding the tag that published it" \
  || fail "rebuilding beta-0.14.1 -> '$got'"

# The exemption is exact tag equality, so a *differently* tagged build of a
# published version is refused. Deliberate, and pinned here because it was
# accidental before anyone said so: going forward a release tag is the version
# itself, so the tag being rebuilt and the tag that published it are the same
# string. What this costs is that the seven historical `dev-*` versions can
# never be rebuilt - which is moot, since a `dev-*` tag is refused outright.
refutes "the same version under a different tag" \
  in_repo QU_PUBSPEC="$file" QU_COMMIT=aaaaaaa1 bash "$DERIVE" --print -- 0.14.1

# The boundaries on the version match. A false positive here hard-blocks every
# build of a legitimate new version, with an error telling the operator to bump
# a pubspec they just bumped.
got="$(in_repo QU_PUBSPEC="$(pubspec_with 0.10.1)" GITHUB_REF_TYPE=branch \
  GITHUB_REF_NAME=main bash "$DERIVE" --print || true)"
[[ "$got" == "0.10.1 108080" ]] && pass "0.10.1 is not blocked by beta-0.10.10" \
  || fail "0.10.1 against beta-0.10.10 -> '$got'"

got="$(in_repo QU_PUBSPEC="$(pubspec_with 0.1.1)" GITHUB_REF_TYPE=branch \
  GITHUB_REF_NAME=main bash "$DERIVE" --print || true)"
[[ "$got" == "0.1.1 108080" ]] && pass "0.1.1 is not blocked by dev-0.11.0" \
  || fail "0.1.1 against dev-0.11.0 -> '$got'"

# The guard has to be able to fail. Swallowing the read would make "no tag
# names this version" and "I could not read the tags" the same answer, and the
# second is the hole it exists to close.
refutes "a repository whose tags cannot be read" \
  run "$COUNT" QU_REPO_ROOT="$TMP/not-a-repo" QU_PUBSPEC="$file" \
  GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main bash "$DERIVE" --print

# --- the commit count, derived rather than pinned ----------------------------
#
# Every assertion above pins QU_COMMIT_COUNT, so without these the formula's
# input is never exercised: neither `git rev-list --count` nor the refusal that
# stops a shallow checkout producing a plausible wrong number.
THREE_REPO="$(fixture_repo 3)"
got="$(run QU_REPO_ROOT="$THREE_REPO" QU_PUBSPEC="$(pubspec_with 0.15.0)" \
  GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main bash "$DERIVE" --print || true)"
[[ "$got" == "0.15.0 100030" ]] && pass "the count comes from the repository" \
  || fail "a derived count -> '$got' (want '0.15.0 100030')"

SHALLOW_REPO="$TMP/shallow"
git clone -q --depth 1 "file://$THREE_REPO" "$SHALLOW_REPO" >/dev/null 2>&1
refutes "a shallow checkout" \
  run QU_REPO_ROOT="$SHALLOW_REPO" QU_PUBSPEC="$(pubspec_with 0.15.0)" \
  GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main bash "$DERIVE" --print

# The default pubspec path, which every other assertion overrides - so a moved
# script or a wrong `../..` would fail all five build jobs with the suite green.
#
# The one case that cannot borrow a fixture repository, because QU_REPO_ROOT
# moves the default pubspec path with it, and that path is what is under test.
# So the guard runs against this repository and passes because the version it
# holds is unpublished - which the branch would already be failing CI over if
# it were not.
# Read without sed, so this is an independent oracle rather than a second
# copy of the parser under test. Two copies of one expression cannot disagree,
# which is how the BSD-only `;q}` passed this assertion all the way to a
# release job.
want=""
while IFS= read -r line; do
  [[ "$line" == version:* ]] || continue
  want="${line#version:}"
  want="${want%%+*}"
  want="${want//[[:space:]]/}"
  break
done < "$HERE/../../pubspec.yaml"
got="$(run "$COUNT" GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main \
  bash "$DERIVE" --print || true)"
[[ "$got" == "$want 108080" ]] && pass "the default pubspec path resolves" \
  || fail "the default pubspec -> '$got' (want '$want 108080')"

# --- how the tag reaches the script -----------------------------------------

# The workflow passes the tag after `--` in all four call sites, so the arm that
# consumes it is load-bearing.
file="$(pubspec_with 0.11.2)"
refutes "a tag of --print is not read as a flag" \
  run "$NOTAGS" "$COUNT" QU_PUBSPEC="$file" bash "$DERIVE" --print -- --print

# `-- ""` is the tag-push shape: an empty argument after the separator. It has
# to fall back to the ref rather than be read as a tag.
got="$(run "$NOTAGS" "$COUNT" QU_PUBSPEC="$file" GITHUB_REF_TYPE=tag \
  GITHUB_REF_NAME=beta-0.11.2 bash "$DERIVE" --print -- "" || true)"
[[ "$got" == "0.11.2 108081" ]] && pass "-- with an empty tag falls back" \
  || fail "-- empty tag -> '$got'"

got="$(run "$NOTAGS" "$COUNT" QU_PUBSPEC="$file" GITHUB_REF_TYPE=tag \
  GITHUB_REF_NAME=beta-0.11.2 bash "$DERIVE" --print || true)"
[[ "$got" == "0.11.2 108081" ]] && pass "--print reads GITHUB_REF_NAME" \
  || fail "--print GITHUB_REF_NAME fallback -> '$got'"

# A branch ref is not a tag that failed to parse; it is the ordinary case.
got="$(run "$NOTAGS" "$COUNT" QU_PUBSPEC="$file" GITHUB_REF_TYPE=branch \
  GITHUB_REF_NAME=main bash "$DERIVE" --print || true)"
[[ "$got" == "0.11.2 108080" ]] && pass "a branch ref builds rather than failing" \
  || fail "a branch ref -> '$got'"

# And a ref the trigger did not call a tag must not be checked as one, however
# much it looks like one: GITHUB_REF_TYPE is what decides.
got="$(run "$NOTAGS" "$COUNT" QU_PUBSPEC="$file" GITHUB_REF_TYPE=branch \
  GITHUB_REF_NAME=release/0.99.0 bash "$DERIVE" --print || true)"
[[ "$got" == "0.11.2 108080" ]] && pass "a branch named like a tag is still a branch" \
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

# The commit defines are pinned wherever a test asserts the whole args string,
# so these keep checking the shape they were written for rather than the SHA
# this checkout happens to sit on.
#
# The app's own commit is pinned to a value rather than to empty: a release
# build with no commit is fatal now - only the commit ties a store binary to a
# tree - so an empty one is no longer a usable fixture for an assertion about
# argument shape. The submodules stay empty, which is the ordinary state of a
# desktop job.
PINNED=(QU_COMMIT=aaaaaaa1 QU_COMMIT_FLIPPERLIB= QU_COMMIT_DARTUFBT=)

# Every run below asserts the shape of what reaches a build, not the guards, so
# each one is given a pubspec to read and the published-version check waived.
# `GITHUB_REF_TYPE=tag` goes with each ref as well: without it a tag-shaped ref
# is a branch, which is the right default and the wrong fixture here.
BASE=("$NOTAGS" "$COUNT" QU_PUBSPEC="$(pubspec_with 0.11.2)")

body=""
if ! body="$(run_env "${BASE[@]}" "${PINNED[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2)"; then fail "a plain run exited non-zero"; fi

has() { grep -qxF -- "$2" <<<"$body" && pass "$1" || fail "$1 (missing: $2)"; }
has "appends, does not truncate"  "PRE_EXISTING=1"
has "writes the version name"     "QUNLEASHED_VERSION_NAME=0.11.2"
has "writes the version code"     "QUNLEASHED_VERSION_CODE=108081"
has "publishes the step outputs"  "version_name=0.11.2"
has "build args carry name+number" \
  "QUNLEASHED_FLUTTER_BUILD_ARGS=--build-name=0.11.2 --build-number=108081 --dart-define=QU_CHANNEL=release --dart-define=QU_COMMIT=aaaaaaa1"

if ! body="$(run_env "${BASE[@]}" "${PINNED[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2 QU_BUILD_SERVER_URL=https://b QU_BUILD_SERVER_KEY=k QU_CARTO_KEY=c QU_SENTRY_DSN=https://k@o1.ingest.de.sentry.io/2)"; then
  fail "a run with every secret exited non-zero"
fi
has "folds in every secret" \
  "QUNLEASHED_FLUTTER_BUILD_ARGS=--build-name=0.11.2 --build-number=108081 --dart-define=QU_CHANNEL=release --dart-define=QU_BUILD_SERVER_URL=https://b --dart-define=QU_BUILD_SERVER_KEY=k --dart-define=QU_CARTO_KEY=c --dart-define=QU_SENTRY_DSN=https://k@o1.ingest.de.sentry.io/2 --dart-define=QU_COMMIT=aaaaaaa1"

# ADR 0014 §5, and the string that has to match `BuildStamp.sentryRelease`
# exactly: the symbols are uploaded under this name and the events carry that
# one, so a disagreement puts the two in different releases and symbolication
# silently stops working.
#
# Asserted per channel rather than once, because the suffix is the part that
# differs and the release case is the one with no suffix at all.
# Named without the QUNLEASHED_ prefix every sibling carries, because that is
# the name `sentry_dart_plugin` reads from the environment - and in the plugin
# the environment outranks its own argument, so this line is the whole wiring.
has "names the Sentry release" \
  "SENTRY_RELEASE=qunleashed@0.11.2+108081"
has "and publishes it as an output" "sentry_release=qunleashed@0.11.2+108081"

if ! body="$(run_env "${BASE[@]}" "${PINNED[@]}" GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main)"; then
  fail "a dev run exited non-zero"
fi
has "a dev build's release says dev" \
  "SENTRY_RELEASE=qunleashed@0.11.2-dev+108080"
# The asset name carries the same two facts and cannot carry a `+`, so the two
# spellings differ on purpose. Pinned together so nobody "fixes" one into the
# other.
has "and the asset name is the other spelling" \
  "QUNLEASHED_ASSET_VERSION=0.11.2-dev.108080"

# ADR 0014 §3: a build has to be able to name the commit it came from, and all
# three of them, because a fault can be in a submodule. Pinned rather than read
# from this checkout so the assertion does not move with HEAD.
if ! body="$(run_env "${BASE[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2 QU_COMMIT=aaaaaaa1 QU_COMMIT_FLIPPERLIB=bbbbbbb2 QU_COMMIT_DARTUFBT=ccccccc3)"; then
  fail "a run with the three commits exited non-zero"
fi
has "carries all three commits"   "QUNLEASHED_FLUTTER_BUILD_ARGS=--build-name=0.11.2 --build-number=108081 --dart-define=QU_CHANNEL=release --dart-define=QU_COMMIT=aaaaaaa1 --dart-define=QU_COMMIT_FLIPPERLIB=bbbbbbb2 --dart-define=QU_COMMIT_DARTUFBT=ccccccc3"

# Only the commit ties a store build to a tree, so a release without one fails
# rather than warning. A dev build warns and goes on: it is disposable, and the
# channel and version still identify it well enough to throw away.
refutes "a release with no commit" \
  run_env "${BASE[@]}" QU_COMMIT= GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2
if ! body="$(run_env "${BASE[@]}" QU_COMMIT= GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main)"; then
  fail "a dev build with no commit must still build"
else
  pass "a dev build with no commit still builds"
fi

# A desktop job need not have the submodules checked out, and must still build.
# The app's own commit is the one that matters; the others are then absent
# rather than empty, which is what String.fromEnvironment reads as "unknown".
if ! body="$(run_env "${BASE[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2 QU_COMMIT=aaaaaaa1 QU_COMMIT_FLIPPERLIB= QU_COMMIT_DARTUFBT=)"; then
  fail "a run with no submodule commits exited non-zero"
fi
has "a submodule commit is optional"   "QUNLEASHED_FLUTTER_BUILD_ARGS=--build-name=0.11.2 --build-number=108081 --dart-define=QU_CHANNEL=release --dart-define=QU_COMMIT=aaaaaaa1"

# Unset means "work it out from the repository", which is the path every build
# job takes. It must produce a real SHA rather than nothing.
#
# Against the fixture, not this checkout: `ci.yml` clones shallow and with no
# tags, so an assertion that borrowed the ambient repository's history was red
# in CI and green locally - which is the worst way round.
if ! body="$(run_env "${BASE[@]}" QU_REPO_ROOT="$THREE_REPO" \
    GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2)"; then
  fail "a run resolving its own commit exited non-zero"
elif grep -qE -- "--dart-define=QU_COMMIT=[0-9a-f]{40}" <<<"$body"; then
  pass "an unset commit is resolved from the repository"
else
  fail "an unset commit was not resolved from the repository"
fi

# A commit carrying whitespace would truncate every argument after it, the same
# hazard the secrets are guarded for.
refutes "a commit with a space" run_env "${BASE[@]}" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2 QU_COMMIT="a b"

# --- the channel ------------------------------------------------------------
#
# ADR 0014 §1. This is the field three readers used to derive for themselves,
# and the one a push to `main` cannot derive at all, because there is no tag.

echo "derive_version.sh --print-channel"

# The channel depends on the trigger and on nothing else, so none of these need
# a pubspec, a guard waiver or a repository. That is the point: the publish job
# asks for exactly this much.
channel() {
  local label="$1" want="$2" got
  shift 2
  if ! got="$(run "$@" bash "$DERIVE" --print-channel)"; then got="<rejected>"; fi
  [[ "$got" == "$want" ]] && pass "$label -> $got" || fail "$label -> $got (want $want)"
}

channel "a bare tag"   release GITHUB_REF_TYPE=tag GITHUB_REF_NAME=0.15.0
# beta- and alpha- were cut by hand, so they are releases however they sorted
# on the releases page at the time.
channel "a beta tag"   release GITHUB_REF_TYPE=tag GITHUB_REF_NAME=beta-0.11.2
channel "an alpha tag" release GITHUB_REF_TYPE=tag GITHUB_REF_NAME=alpha-0.8.4

# A branch is a dev build with no tag at all, which is the case the prefix rule
# cannot reach and the reason the channel has to come from the trigger.
channel "a branch"     dev     GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main

# And the variable wins over the prefix either way, which is what lets the
# workflow say what a build is rather than have it inferred.
channel "an explicit dev wins" dev \
  GITHUB_REF_TYPE=tag GITHUB_REF_NAME=0.15.0 QU_CHANNEL=dev
channel "an explicit release"  release \
  GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main QU_CHANNEL=release

# And the override does not reopen the dev- hole: a tag whose prefix collides
# with the rolling prerelease's name is refused before the channel is read at
# all, because the publish job would still be handed that tag.
refutes "a dev- tag even with an override" \
  run GITHUB_REF_TYPE=tag GITHUB_REF_NAME=dev-0.15.0 QU_CHANNEL=release \
  bash "$DERIVE" --print-channel

# A typo must not ship a build labelled with it, and `local` is the app's own
# default for a build nothing told - never something CI produces.
refutes "an unknown channel" run GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main QU_CHANNEL=nightly bash "$DERIVE" --print-channel
refutes "local from CI"      run GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main QU_CHANNEL=local bash "$DERIVE" --print-channel

# The channel reaches the build the same way the version does, and the publish
# job reads it from the step output rather than testing the prefix again.
if ! body="$(run_env "$NOTAGS" "$COUNT" QU_PUBSPEC="$(pubspec_with 0.14.1)" \
    "${PINNED[@]}" GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main)"; then
  fail "a dev run exited non-zero"
fi
has "writes the channel"          "QUNLEASHED_CHANNEL=dev"
has "publishes it as an output"   "channel=dev"
has "compiles it into the build" \
  "QUNLEASHED_FLUTTER_BUILD_ARGS=--build-name=0.14.1 --build-number=108080 --dart-define=QU_CHANNEL=dev --dart-define=QU_COMMIT=aaaaaaa1"
# The asset name carries the suffix and the number, so a sideloaded dev APK is
# not byte-identical to the release of the same cycle - the one place §2's
# suffix was missing. Its own variable, so the numeric name every other
# consumer reads is unchanged and --build-name stays store-valid.
has "names the assets apart from a release" \
  "QUNLEASHED_ASSET_VERSION=0.14.1-dev.108080"
has "and leaves the numeric name numeric" "QUNLEASHED_VERSION_NAME=0.14.1"

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
if run "$NOTAGS" "$COUNT" QU_PUBSPEC="$(pubspec_with 0.13.0)" \
     GITHUB_ENV="$out" GITHUB_OUTPUT="$step" GITHUB_REF_NAME=main \
     bash "$DERIVE" -- beta-0.13.0 >/dev/null; then
  body="$(cat "$out" "$step")"
  has "an explicit tag beats the branch ref" "QUNLEASHED_VERSION_NAME=0.13.0"
  has "and reaches the step output"          "version_code=108081"
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
