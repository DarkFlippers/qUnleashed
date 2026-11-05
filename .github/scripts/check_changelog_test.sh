#!/usr/bin/env bash
# Covers check_changelog.sh.
#
# A format gate has two failure modes and the quiet one is worse: a gate that
# blocks everything gets noticed on the first push, while a gate that permits
# the drift it exists to catch looks green for weeks. Every case below names
# the mutation it would catch, because the guard's whole value is that it fails
# on the two things that actually shipped - a version line disagreeing with
# pubspec, and a bullet crediting nobody.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/check_changelog.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
NL=$'\n'

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# No suffix after the X's: BSD mktemp follows mkstemp(3) and rejects one, and
# `scripts-bsd` in ci.yml runs this file on macOS.
pubspec_with() {
  local f
  f="$(mktemp "$TMP/pubspec-XXXXXX")"
  printf 'name: qunleashed\nversion: %s\n' "$1" >"$f"
  printf '%s' "$f"
}

changelog_with() {
  local f
  f="$(mktemp "$TMP/changelog-XXXXXX")"
  printf '%s\n' "$1" >"$f"
  printf '%s' "$f"
}

# The same, with every line ending CRLF. Written byte by byte rather than by
# substituting into a here-string, because the fault under test is the bytes.
changelog_crlf() {
  local f
  f="$(mktemp "$TMP/crlf-XXXXXX")"
  printf '%s\n' "$1" | sed 's/$/\r/' >"$f"
  printf '%s' "$f"
}

# Asserts the guard accepts. Output is shown on failure, since a gate that
# refuses a good file is the mode a developer meets first.
accepts() {
  local label="$1" changelog="$2" pubspec="$3" out
  if out="$(bash "$CHECK" "$changelog" "$pubspec" 2>&1)"; then
    pass "$label"
  else
    fail "$label was refused: $out"
  fi
}

# Asserts the guard refuses, AND that it refused for the stated reason rather
# than tripping over something else in the fixture - the "passed for the wrong
# mechanism" trap this repository has hit four times.
refuses() {
  local label="$1" changelog="$2" pubspec="$3" because="$4" out
  if out="$(bash "$CHECK" "$changelog" "$pubspec" 2>&1)"; then
    fail "$label was accepted"
  elif ! grep -qF "$because" <<<"$out"; then
    fail "$label refused for the wrong reason: $out"
  else
    pass "$label rejected"
  fi
}

GOOD='## Main changes
- Version: 0.16.0
- Tools: **A headline** - what it does (by @mishamyte | PR #264 | Closes #142)
- Archive: a smaller one (by @apfxtech)
## Other changes
- Quality: grouped citations (by @mishamyte | PR #260, #261 | Closes #1, #2)
- Fixed: an upstream port (OFW PR 4462 | by @kormax)
- Docs: a fix with no issue (by @mishamyte | PR #247)'

PUBSPEC="$(pubspec_with 0.16.0)"

echo "the shape it is meant to accept"
accepts "a well-formed changelog" "$(changelog_with "$GOOD")" "$PUBSPEC"
accepts "a pubspec carrying a stale build number" \
  "$(changelog_with "$GOOD")" "$(pubspec_with '0.16.0+108370')"

echo
echo "the version line, which is what actually went wrong"
# Mutation it catches: dropping the pubspec comparison entirely. This is the
# defect that shipped - the file said 0.15.0 while 0.16.0-dev was published.
refuses "a version that disagrees with pubspec" \
  "$(changelog_with "$GOOD")" "$(pubspec_with 0.17.0)" \
  "CHANGELOG.md says 0.16.0 and pubspec.yaml says 0.17.0"
refuses "a version line with a 'changes since' clause" \
  "$(changelog_with "${GOOD/- Version: 0.16.0/- Version: 0.16.0 (build 108370), changes since 0.15.0}")" \
  "$PUBSPEC" "and nothing else"
refuses "no version line at all" \
  "$(changelog_with "${GOOD/- Version: 0.16.0$NL/}")" "$PUBSPEC" \
  "must carry a line"
# Mutation it catches: `grep -m1` without a count check. Two version lines is
# what a merge conflict resolution leaves behind, and version drift is the one
# thing this guard exists to catch.
refuses "two version lines" \
  "$(changelog_with '## Main changes
- Version: 0.16.0
- Tools: a thing (by @mishamyte)
- Version: 9.9.9
## Other changes
- Fixed: ok (by @apfxtech)')" "$PUBSPEC" "must carry exactly one"

# Mutation it catches: dropping the CR check. Every pattern below it is
# anchored, so a CRLF file fails on a runner with four errors that name
# headings, bullets and credits - and none of them says "line endings".
refuses "a CRLF changelog" \
  "$(changelog_crlf "$GOOD")" "$PUBSPEC" "CRLF line endings"

# Mutation it catches: dropping the `q` from the pubspec reader, which would
# make the LAST version line win. Survived the whole suite before this case.
refuses "a pubspec whose first version line is not its last" \
  "$(changelog_with "$GOOD")" "$(pubspec_with '9.9.9
version: 0.16.0')" "says 0.16.0 and pubspec.yaml says 9.9.9"

refuses "a two-part version" \
  "$(changelog_with "${GOOD/- Version: 0.16.0/- Version: 0.16}")" \
  "$(pubspec_with 0.16.0)" "and nothing else"

echo
# `Sub-GHz` is this project's own spelling and the class had no hyphen, so the
# first person to write it as an area got told the line must read what it
# already read. The credit-only bullet passed because `(` is not whitespace.
accepts "a hyphenated area" "$(changelog_with '## Main changes
- Version: 0.16.0
- Sub-GHz: a hyphenated area (by @mishamyte | PR #264)
## Other changes
- Pixel Draw: a space in the area (by @apfxtech)')" "$PUBSPEC"

echo
echo "the credit, which was the point of adopting this"
# Mutation it catches: making the attribution clause optional.
refuses "a bullet crediting nobody" \
  "$(changelog_with "${GOOD/ (by @apfxtech)/}")" "$PUBSPEC" \
  "no well-formed credit"
refuses "a credit missing the @" \
  "$(changelog_with "${GOOD/(by @apfxtech)/(by apfxtech)}")" "$PUBSPEC" \
  "no well-formed credit"
refuses "a PR number that is not a number" \
  "$(changelog_with "${GOOD/PR #247/PR #two-four-seven}")" "$PUBSPEC" \
  "no well-formed credit"
refuses "a Closes with no number" \
  "$(changelog_with "${GOOD/Closes #142/Closes}")" "$PUBSPEC" \
  "no well-formed credit"
# docs/releasing.md states one author per bullet, and the regex used to accept
# three spellings of two. Mutation it catches: putting the `(, @name)*` and
# `| and @name` arms back.
refuses "two authors in one credit"   "$(changelog_with "${GOOD/(by @apfxtech)/(by @apfxtech, @mishamyte)}")" "$PUBSPEC"   "no well-formed credit"
refuses "a second author after a pipe"   "$(changelog_with "${GOOD/(by @apfxtech)/(by @apfxtech | and @mishamyte)}")" "$PUBSPEC"   "no well-formed credit"
refuses "a handle that is only punctuation"   "$(changelog_with "${GOOD/(by @apfxtech)/(by @-----)}")" "$PUBSPEC"   "no well-formed credit"
refuses "a bullet whose body is only its credit"   "$(changelog_with '## Main changes
- Version: 0.16.0
- Tools: (by @mishamyte)
## Other changes
- Fixed: fine (by @apfxtech)')" "$PUBSPEC" "<Area>: <what changed>"
refuses "a credit that is not last on the line" \
  "$(changelog_with "${GOOD/ (by @apfxtech)/ (by @apfxtech) and more text}")" \
  "$PUBSPEC" "no well-formed credit"

echo
echo "the sections"
refuses "no Main changes heading" \
  "$(changelog_with '- Version: 0.16.0
- Tools: a thing (by @mishamyte)
## Other changes
- Fixed: another (by @apfxtech)')" "$PUBSPEC" "exactly one '## Main changes'"
refuses "no Other changes heading" \
  "$(changelog_with '## Main changes
- Version: 0.16.0
- Tools: a thing (by @mishamyte)')" "$PUBSPEC" "exactly one '## Other changes'"
refuses "the sections the wrong way round" \
  "$(changelog_with '## Other changes
- Version: 0.16.0
- Tools: a thing (by @mishamyte)
## Main changes
- Archive: another (by @apfxtech)')" "$PUBSPEC" "must come before"
refuses "a duplicated heading" \
  "$(changelog_with "$GOOD
## Other changes
- Tools: again (by @mishamyte)")" "$PUBSPEC" "exactly one '## Other changes'"

echo
echo "the bullet shape"
refuses "an asterisk bullet" \
  "$(changelog_with "${GOOD/- Archive: a smaller one/* Archive: a smaller one}")" \
  "$PUBSPEC" "not '* '"
refuses "a bullet with no area" \
  "$(changelog_with "${GOOD/- Archive: a smaller one/- a smaller one}")" \
  "$PUBSPEC" "<Area>: <what changed>"
refuses "an area with nothing after the colon" \
  "$(changelog_with '## Main changes
- Version: 0.16.0
- Archive:
## Other changes
- Tools: a thing (by @mishamyte)')" "$PUBSPEC" "<Area>: <what changed>"
# A standalone fixture, not a substitution: `${GOOD/## Other changes/...}` is
# parsed as `${GOOD/#...}`, the anchor-at-start form, so it quietly substitutes
# nothing - the same trap two earlier fixtures in this file fell into. The space
# sits on a heading line, so the bullet loop never sees it and the only fault
# reported is the one this case names.
#
# Built by printf rather than written out, because a trailing space does not
# survive being saved - an editor strips it, and so did the tooling that wrote
# this file, which is how this case spent two revisions testing nothing. The
# space is a line of its own, which no other check looks at: not a heading, not
# a bullet, not the version line. Two earlier versions of this case did not
# isolate - a space after a credit breaks the `)$` anchor, and a space after a
# heading breaks the heading match - so each caught its mutation by collateral
# damage rather than by the rule it names. Verified by disabling only the
# whitespace complaint: this case is the one that fails, and it fails saying so.
changelog_trailing_space() {
  local f
  f="$(mktemp "$TMP/trail-XXXXXX")"
  printf '## Main changes\n- Version: 0.16.0\n- Tools: a thing (by @mishamyte)\n## Other changes\n- Fixed: ok (by @apfxtech)\n%s\n' \
    ' ' >"$f"
  printf '%s' "$f"
}
refuses "trailing whitespace" "$(changelog_trailing_space)" "$PUBSPEC" \
  "Trailing whitespace"

echo
echo "it names everything at once"
# One push should surface every problem, not the first one. Three faults here.
out="$(bash "$CHECK" \
  "$(changelog_with '## Main changes
- Version: 0.16.0
- Archive: credits nobody
## Other changes
* Fixed: an asterisk bullet (by @apfxtech)')" \
  "$(pubspec_with 0.17.0)" 2>&1 || true)"
reported="$(grep -c '^::error::' <<<"$out")"
# Version mismatch, the uncredited bullet, the asterisk, and the summary.
if [[ "$reported" -eq 4 ]]; then
  pass "three faults and a summary are all reported"
else
  fail "expected four ::error:: lines, got $reported: $out"
fi

echo
echo "the repository's own file"
accepts "the committed CHANGELOG.md" "$HERE/../../CHANGELOG.md" "$HERE/../../pubspec.yaml"

echo
if (( failures )); then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
