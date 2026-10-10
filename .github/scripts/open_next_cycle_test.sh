#!/usr/bin/env bash
# Covers open_next_cycle.sh.
#
# It only ever runs on a release, which is the least-rehearsed path there is,
# and it edits the one file CI refuses a build over. A mistake here is either
# a `main` that stays red after a release or a pubspec written to a version
# nobody chose - both discovered by a person, days later.
#
# The last case is the one that matters most: it feeds the output straight to
# check_changelog.sh, so the skeleton this writes cannot drift from the shape
# the guard demands without a test going red.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPEN="$HERE/open_next_cycle.sh"
GUARD="$HERE/check_changelog.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# No suffix after the X's: BSD mktemp follows mkstemp(3) and rejects one.
fixture() {
  local dir
  dir="$(mktemp -d "$TMP/case-XXXXXX")"
  printf 'name: qunleashed\ndescription: a thing\nversion: %s\nenvironment:\n  sdk: ^3.13.0\n' \
    "$1" >"$dir/pubspec.yaml"
  printf '## Main changes\n- Version: %s\n- Tools: a thing (by @mishamyte | PR #1)\n## Other changes\n- Fixed: another (by @apfxtech)\n' \
    "${2:-$1}" >"$dir/CHANGELOG.md"
  printf '%s' "$dir"
}

version_of() {
  sed -nE '/^version:/{
    s/^version:[[:space:]]*([^+[:space:]]+).*$/\1/p
    q
  }' "$1/pubspec.yaml"
}

echo "the version it proposes"
d="$(fixture 0.16.0)"
got="$(bash "$OPEN" 0.16.0 "$d/pubspec.yaml" "$d/CHANGELOG.md")"
[[ "$got" == 0.17.0 ]] &&
  pass "0.16.0 -> 0.17.0 is printed" || fail "printed '$got', wanted 0.17.0"
[[ "$(version_of "$d")" == 0.17.0 ]] &&
  pass "pubspec holds 0.17.0" || fail "pubspec holds '$(version_of "$d")'"

# A minor bump, not a patch one, and not a major one.
for pair in "0.9.0 0.10.0" "1.4.7 1.5.0" "0.16.1 0.17.0" "2.0.0 2.1.0"; do
  set -- $pair
  d="$(fixture "$1")"
  got="$(bash "$OPEN" "$1" "$d/pubspec.yaml" "$d/CHANGELOG.md")"
  [[ "$got" == "$2" ]] && pass "$1 -> $2" || fail "$1 gave '$got', wanted $2"
done

# Zero-padded components are read base 10, the trap 0014 names: 0.08.0 must
# become 0.9.0, not 0.11.0 from octal 08 - which is not even valid octal.
d="$(fixture 0.08.0)"
got="$(bash "$OPEN" 0.08.0 "$d/pubspec.yaml" "$d/CHANGELOG.md" 2>&1 || true)"
[[ "$got" == 0.9.0 ]] && pass "0.08.0 -> 0.9.0, read base 10" ||
  fail "0.08.0 gave '$got', wanted 0.9.0"

echo
echo "the changelog it leaves behind"
d="$(fixture 0.16.0)"
bash "$OPEN" 0.16.0 "$d/pubspec.yaml" "$d/CHANGELOG.md" >/dev/null
want='## Main changes
- Version: 0.17.0
## Other changes'
[[ "$(cat "$d/CHANGELOG.md")" == "$want" ]] &&
  pass "the skeleton is exactly the three lines" ||
  fail "skeleton was: $(cat "$d/CHANGELOG.md")"
if ! grep -q 'Tools: a thing' "$d/CHANGELOG.md"; then
  pass "the shipped notes are gone"
else
  fail "the old notes survived the reset"
fi

# The whole point of the pairing: what this writes must satisfy the guard.
# Mutation it catches: dropping the version line from the skeleton, or writing
# the old version into it, both of which leave `main` red after the merge.
if out="$(bash "$GUARD" "$d/CHANGELOG.md" "$d/pubspec.yaml" 2>&1)"; then
  pass "check_changelog.sh accepts what it wrote"
else
  fail "the guard refused the skeleton: $out"
fi

echo
echo "what it refuses"
refuses() {
  local label="$1" because="$2"
  shift 2
  local out
  if out="$(bash "$OPEN" "$@" 2>&1)"; then
    fail "$label was accepted"
  elif ! grep -qF "$because" <<<"$out"; then
    fail "$label refused for the wrong reason: $out"
  else
    pass "$label rejected"
  fi
}

d="$(fixture 0.16.0)"
refuses "no version given" "Usage:" "" "$d/pubspec.yaml" "$d/CHANGELOG.md"
refuses "a two-part version" "not a major.minor.patch" 0.16 "$d/pubspec.yaml" "$d/CHANGELOG.md"
refuses "a tag-shaped version" "not a major.minor.patch" v0.16.0 "$d/pubspec.yaml" "$d/CHANGELOG.md"
refuses "a prerelease suffix" "not a major.minor.patch" 0.16.0-rc1 "$d/pubspec.yaml" "$d/CHANGELOG.md"
refuses "a missing pubspec" "No file at" 0.16.0 "$d/nope.yaml" "$d/CHANGELOG.md"
refuses "a missing changelog" "No file at" 0.16.0 "$d/pubspec.yaml" "$d/nope.md"

# The guard against running twice. A pubspec already on the next version means
# somebody bumped it by hand, and writing 0.18.0 over that would skip a cycle.
d="$(fixture 0.17.0 0.17.0)"
refuses "a cycle that is already open" "refusing to bump a second time" \
  0.16.0 "$d/pubspec.yaml" "$d/CHANGELOG.md"

echo
echo "it leaves the rest of pubspec alone"
d="$(fixture 0.16.0)"
bash "$OPEN" 0.16.0 "$d/pubspec.yaml" "$d/CHANGELOG.md" >/dev/null
if grep -q '^name: qunleashed$' "$d/pubspec.yaml" &&
  grep -q '^description: a thing$' "$d/pubspec.yaml" &&
  grep -q '^  sdk: \^3.13.0$' "$d/pubspec.yaml" &&
  [[ "$(grep -c '^version:' "$d/pubspec.yaml")" == 1 ]]; then
  pass "every other line is untouched, and there is one version line"
else
  fail "pubspec was mangled: $(cat "$d/pubspec.yaml")"
fi

# A pubspec carrying a build number loses it, which is correct: 0014 derives
# the number in CI and pubspec holds the name alone.
d="$(fixture '0.16.0+108370' 0.16.0)"
got="$(bash "$OPEN" 0.16.0 "$d/pubspec.yaml" "$d/CHANGELOG.md" 2>&1 || true)"
[[ "$got" == 0.17.0 && "$(version_of "$d")" == 0.17.0 ]] &&
  pass "a stale +build is read past, and not written back" ||
  fail "gave '$got', pubspec now '$(version_of "$d")'"

echo
if (( failures )); then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
