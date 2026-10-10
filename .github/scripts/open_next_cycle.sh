#!/usr/bin/env bash
# Writes the two files that open a new cycle, and prints the version it chose.
#
# Publishing a release breaks `main` on purpose: until `pubspec.yaml` names a
# version that has not been published, every push fails with "Version 0.16.0
# has already been published" (docs/releasing.md). Two files have to move, and
# they have to move together - `check_changelog.sh` refuses a changelog whose
# version line disagrees with pubspec - so this does both or neither.
#
#   open_next_cycle.sh <released-version> [pubspec] [changelog]
#
# **The next version is a minor bump by default, and the default is a guess.**
# ADR 0014 §2 keeps the digit for a person, because patch against minor against
# major is a decision no rule over the previous version can make - and the tags
# bear that out rather than contradicting it. The eight released transitions
# since 0.11.0 are four patches and four minors: 0.11.1, 0.11.2, 0.12.1 and
# 0.14.1 against 0.12.0, 0.13.0, 0.14.0 and 0.15.0.
#
# So this proposes a minor because one of the two has to be proposed, not
# because it is usually right. Two things follow, and they are the reason the
# workflow does what it does: the pull request is opened as a **draft**, so the
# digit cannot be merged by reflex on the one day somebody wants `main` green
# in a hurry; and nothing downstream depends on the number this picked, so
# editing the two lines in that pull request is the whole correction.
#
# It refuses to run unless pubspec still holds the released version. Opening
# the 0.17.0 cycle over a pubspec that already says 0.17.0 would mean the bump
# happened by hand and this is a second, conflicting attempt.
#
# The changelog reset here is unconditional, and deliberately so: whether a
# note landed after the release was cut is a question only the caller can
# answer, because only it knows the tag. `open-next-cycle` compares `main`
# against the tag and refuses before it ever reaches this script.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
released="${1:-}"
pubspec="${2:-$HERE/../../pubspec.yaml}"
changelog="${3:-$HERE/../../CHANGELOG.md}"

if [[ -z "$released" ]]; then
  echo "::error::Usage: open_next_cycle.sh <released-version> [pubspec] [changelog]" >&2
  exit 2
fi
if [[ ! "$released" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "::error::'$released' is not a major.minor.patch version." >&2
  exit 1
fi

# Base 10 explicitly: a zero-padded component read as octal is how `0.08.09`
# became a version nobody meant, which 0014 calls out by name.
major="$((10#${BASH_REMATCH[1]}))"
minor="$((10#${BASH_REMATCH[2]}))"
next="$major.$((minor + 1)).0"

for f in "$pubspec" "$changelog"; do
  if [[ ! -f "$f" ]]; then
    echo "::error::No file at $f." >&2
    exit 1
  fi
done

# Read it the way derive_version.sh does, including the `q` on its own line -
# BSD sed ends `q` at a `;` or a newline and `}` is neither.
current="$(
  sed -nE '/^version:/{
    s/^version:[[:space:]]*([^+[:space:]]+).*$/\1/p
    q
  }' "$pubspec"
)"
if [[ "$current" != "$released" ]]; then
  echo "::error::pubspec.yaml says '$current', not the released '$released'. The cycle looks already open - refusing to bump a second time." >&2
  exit 1
fi

# pubspec: the version line only. Written in place with a temporary file rather
# than `sed -i`, which takes a mandatory argument on BSD and none on GNU.
tmp="$(mktemp "${TMPDIR:-/tmp}/pubspec-XXXXXX")"
trap 'rm -f "$tmp"' EXIT
# `-v v=`, not `-v next=`: `next` is an awk keyword and gawk refuses it as a
# variable name outright. `!seen` is what keeps this to the FIRST `version:`
# line, matching the reader above - without it every one is rewritten, which is
# how a pubspec with a commented-out version would lose both.
awk -v v="$next" '
  !seen && /^version:/ { print "version: " v; seen = 1; next }
  { print }
' "$pubspec" >"$tmp"
cat "$tmp" >"$pubspec"

# The changelog: back to the skeleton. The notes that were in it have shipped,
# and the next cycle writes its own as its changes land - not at release time,
# which is how five cycles went by with the file describing the first of them.
cat >"$changelog" <<EOF
## Main changes
- Version: $next
## Other changes
EOF

printf '%s\n' "$next"
