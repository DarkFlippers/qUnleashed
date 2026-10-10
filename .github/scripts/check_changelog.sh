#!/usr/bin/env bash
# Fails when CHANGELOG.md has drifted from the shape the release notes need.
#
# The file is the release notes. Nothing generates it and, until this guard,
# nothing read it either - which is how it came to describe 0.15.0 while the
# published build was 0.16.0-dev, and to quote "build 15000" two weeks after
# ADR 0014 retired pubspec-held build numbers. Both were visible in the file
# for anyone who looked; nobody had a reason to.
#
# What this checks is the shape, not the prose. A bullet that says the wrong
# thing is a review problem and no script can see it. A bullet with no author,
# a version that disagrees with pubspec, a `Closes` with no number - those are
# mechanical, and they are what actually went wrong.
#
# Deliberately NOT checked: whether a given pull request added a bullet. Most
# changes here should not - #295 was CI only, #281 was a Crowdin sync, and the
# submodule bumps and test-only branches are the bulk of the history. A gate
# that is wrong that often needs a bypass label, and a bypass label used daily
# stops being read. The prompt to think about it belongs in the pull request
# template, where unleashed-firmware puts its own disclosure gate.
#
#   check_changelog.sh [path-to-changelog] [path-to-pubspec]
#
# Both default to the repository root's, so CI calls it with no arguments and
# the test calls it with fixtures. Prints one `::error::` per problem and exits
# 1 if there were any, so a run names everything wrong at once rather than
# making the author fix them one push at a time.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
changelog="${1:-$HERE/../../CHANGELOG.md}"
pubspec="${2:-$HERE/../../pubspec.yaml}"

problems=0
complain() {
  echo "::error::$1" >&2
  problems=$((problems + 1))
}

for f in "$changelog" "$pubspec"; do
  if [[ ! -f "$f" ]]; then
    echo "::error::No file at $f." >&2
    exit 1
  fi
done

# --- line endings, before anything anchored is tried -----------------------

# `tr`/`cmp` rather than `grep $'\r'`, because MSYS grep opens the file in text
# mode and strips the CR before matching - so on the author's own Windows
# checkout the grep form finds nothing and only the runners complain, which is
# the wrong way round. `cmp` compares bytes everywhere.
if ! tr -d '\r' <"$changelog" | cmp -s - "$changelog"; then
  complain "CHANGELOG.md has CRLF line endings. Every check below is anchored, so on a Linux or macOS runner they fail naming something else. Save it as LF - .gitattributes asks for it."
fi

# --- the two sections, once each, in order ----------------------------------

main_at="$(grep -n '^## Main changes$' "$changelog" | cut -d: -f1 || true)"
other_at="$(grep -n '^## Other changes$' "$changelog" | cut -d: -f1 || true)"

if [[ "$(printf '%s\n' "$main_at" | grep -c .)" != 1 ]]; then
  complain "CHANGELOG.md needs exactly one '## Main changes' heading."
  main_at=""
fi
if [[ "$(printf '%s\n' "$other_at" | grep -c .)" != 1 ]]; then
  complain "CHANGELOG.md needs exactly one '## Other changes' heading."
  other_at=""
fi
if [[ -n "$main_at" && -n "$other_at" && "$main_at" -ge "$other_at" ]]; then
  complain "'## Main changes' must come before '## Other changes'."
fi

# --- the version line, and pubspec agreeing with it -------------------------
#
# This is the one check that would have caught what shipped. The first content
# line names the version being built toward, and ADR 0014 says pubspec holds
# that same number - so they cannot disagree without one of them being wrong.
# No "changes since" clause: the file accumulates until a stable release, so
# there is no single predecessor to name.

version_lines="$(grep -c '^- Version: ' "$changelog" || true)"
version_line="$(grep -m1 '^- Version: ' "$changelog" || true)"
if [[ "$version_lines" -gt 1 ]]; then
  complain "CHANGELOG.md carries $version_lines '- Version:' lines and must carry exactly one. Two is what a merge conflict leaves behind."
fi
if [[ -z "$version_line" ]]; then
  complain "CHANGELOG.md must carry a line '- Version: <major.minor.patch>'."
elif [[ ! "$version_line" =~ ^-\ Version:\ ([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  complain "Version line must be '- Version: <major.minor.patch>' and nothing else, not '${version_line}'."
else
  changelog_version="${BASH_REMATCH[1]}"
  # derive_version.sh's reader, verbatim: the `q` takes the first `version:`
  # and nothing else, and it sits on its own line because BSD sed ends `q` at a
  # `;` or a newline and `}` is neither. Without the `q` the last line in the
  # file would win, which no test would notice.
  pubspec_version="$(
    sed -nE '/^version:/{
      s/^version:[[:space:]]*([^+[:space:]]+).*$/\1/p
      q
    }' "$pubspec"
  )"
  if [[ "$changelog_version" != "$pubspec_version" ]]; then
    complain "CHANGELOG.md says $changelog_version and pubspec.yaml says $pubspec_version. ADR 0014: pubspec holds the version being built toward, and the notes describe that build."
  fi
fi

# --- one bullet character ---------------------------------------------------
#
# The file used `*` under the headings and `-` for the version line. Mixing
# them is invisible in rendered Markdown and makes every check below need two
# patterns, so one is pinned: `-`, which is what the version line already was.

if grep -qE '^\*[[:space:]]' "$changelog"; then
  complain "Bullets use '- ', not '* '. Lines: $(grep -nE '^\*[[:space:]]' "$changelog" | cut -d: -f1 | paste -sd, -)."
fi

# --- every bullet names an area, and credits somebody ------------------------
#
# `Area: text (by @name | PR #1 | Closes #2)`. PR and the issue clause are
# optional - a change pushed straight to main has no pull request to cite, and
# most have no issue - but the author is not, because crediting everybody was
# the point of adopting this from unleashed-firmware. Grouped citations are
# allowed (`PR #260, #261`) since one bullet often merges several changes.

handle='@[A-Za-z0-9][A-Za-z0-9_-]*'
prs="( \| PR #[0-9]+(, #[0-9]+)*)?"
issues="( \| (Closes|Fixes) #[0-9]+(, #[0-9]+)*)?"
attribution="\((by $handle|OFW PR [0-9]+ \| by $handle)$prs$issues\)\$"

while IFS= read -r numbered; do
  line_no="${numbered%%:*}"
  line="${numbered#*:}"

  # The version line is the one bullet that is a fact rather than a change.
  [[ "$line" == "- Version: "* ]] && continue

  if [[ ! "$line" =~ ^-\ [A-Za-z][A-Za-z0-9/.+\ -]*:\ [^\([:space:]] ]]; then
    complain "Line $line_no must read '- <Area>: <what changed>': $line"
    continue
  fi
  if [[ ! "$line" =~ $attribution ]]; then
    complain "Line $line_no has no well-formed credit. Expected it to end '(by @name)', optionally '| PR #1' and '| Closes #2': $line"
  fi
done < <(grep -nE '^-[[:space:]]' "$changelog")

# --- nothing empty or ragged ------------------------------------------------

if grep -qE '[[:space:]]+$' "$changelog"; then
  complain "Trailing whitespace on lines: $(grep -nE '[[:space:]]+$' "$changelog" | cut -d: -f1 | paste -sd, -)."
fi

if (( problems )); then
  echo "::error::CHANGELOG.md: $problems problem(s). See docs/releasing.md for the shape." >&2
  exit 1
fi

echo "CHANGELOG.md: OK."
