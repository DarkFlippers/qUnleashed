#!/usr/bin/env bash
# Covers release_body.sh.
#
# The body is published and then read by somebody deciding whether to install a
# build, so a mistake here is wrong prose on a page rather than a red build.
# Nothing else would catch it: the publish job runs on a push to `main` and on a
# tag, neither of which is rehearsable, and the page is only looked at once it is
# already wrong.
#
# What matters most are the shapes that are *not* the happy path - a cycle
# boundary, a build whose push added no bullet, a baseline that will not resolve
# - because they are all normal and they all used to be the same single body.
#
# A mutation run over the first draft of this suite left thirteen changes to the
# script green, clustered in two places: the comparison's flags, and which
# commits the fallback picks. Both are covered below on purpose, and the cases
# that pin them say so.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BODY="$HERE/release_body.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

# `set -E` with no ERR trap is why inheriting GITHUB_RUN_ATTEMPT printed a
# green `ok` and then stopped the suite dead, with no case named. Aborting is
# still right - a negative assertion must not pass vacuously after the script
# has died - but it has to say where.
trap 'printf "  ABORT  %s:%s: %s\n" "${BASH_SOURCE[0]}" "$LINENO" "$BASH_COMMAND" >&2' ERR

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

export GITHUB_SERVER_URL="https://github.com"
export GITHUB_REPOSITORY="mishamyte/qUnleashed"
# A runner sets GITHUB_RUN_ATTEMPT in every step, to 1 on a first attempt, and
# the script's step-order guard tests it. Inheriting it meant the rebuild case
# below - whose `dev` tag names HEAD, which on a first attempt is what that
# guard exists to refuse - exited 1 mid-suite with no assertion named. Pinned to
# 2 because a rebuild *is* a re-run, so this is also the attempt number
# production reaches that path on. The two cases that test the guard itself set
# it explicitly.
export GITHUB_RUN_ATTEMPT=2
# `write_changelog` reads this, so an ambient value would rewrite every
# fixture's version line and turn ordinary cases into cycle boundaries. Same
# class as the inherited GITHUB_RUN_ATTEMPT above; unset rather than pinned,
# because the cases that vary it do so inline.
unset QU_TEST_VERSION

SUMMARY='version: 0.16.0-dev (108410) | commit: 0f12f3c'

# A fixture repository, because the baseline is a tag and the notes are read out
# of two revisions of one file. No suffix after the X's: BSD mktemp follows
# mkstemp(3) and rejects one.
repo() {
  local dir
  dir="$(mktemp -d "$TMP/repo-XXXXXX")"
  git -C "$dir" init --quiet
  git -C "$dir" config user.email t@example.com
  git -C "$dir" config user.name Test
  # The script compares a committed blob against the working file. With
  # autocrlf on, `git add` normalises the blob to LF while the working file
  # keeps CRLF, and every bullet then reads as new. Pinned rather than
  # inherited from whoever is running this.
  git -C "$dir" config core.autocrlf false
  printf '%s' "$dir"
}

# write_changelog <dir> [main-section bullets...]
# Writes the file only. `commit` is separate because several cases need to write
# twice between two commits.
write_changelog() {
  local dir="$1"; shift
  {
    printf '## Main changes\n- Version: %s\n' "${QU_TEST_VERSION:-0.16.0}"
    local line
    for line in "$@"; do printf -- '- %s\n' "$line"; done
    printf '## Other changes\n'
  } >"$dir/CHANGELOG.md"
}

# Prints nothing: every call site discarded the sha, and `git rev-parse` was
# the largest single source of this suite's git spawns. The cases that need a
# sha ask for it where they use it.
commit() {
  local dir="$1" subject="$2"
  git -C "$dir" add -A
  git -C "$dir" commit --quiet -m "$subject"
}

# The baseline the script reads: the tag the previous dev build left behind,
# always at HEAD - no call site has ever wanted it elsewhere.
#
# The status is checked for the message, not for safety: `set -e` would abort
# the suite on a failed `git tag` anyway, but it would abort naming git's
# command rather than the fixture that could not be built.
tag_dev() {
  git -C "$1" tag -f dev HEAD >/dev/null ||
    { echo "fixture: could not tag dev in $1" >&2; exit 1; }
}

# The three lines most cases open with: a baseline commit carrying one note,
# and `dev` on it. The cases where the baseline's *content* is the point pass
# their own bullets or stay inline.
baselined() {
  local dir="$1"; shift
  if (( $# )); then write_changelog "$dir" "$@"; else
    write_changelog "$dir" 'Tools: a thing (by @mishamyte | PR #1)'; fi
  commit "$dir" 'the previous build'
  tag_dev "$dir"
}

# stdout only. A non-zero exit aborts the suite rather than passing a negative
# assertion vacuously, which is what `set -e` on a bare assignment buys.
run() {
  local dir="$1" channel="$2"
  QU_REPO_ROOT="$dir" GITHUB_SHA="$(git -C "$dir" rev-parse HEAD)" \
    bash "$BODY" --channel "$channel" --summary "$SUMMARY" 2>/dev/null
}

# stderr only, for the annotations.
run_err() {
  local dir="$1" channel="$2"
  QU_REPO_ROOT="$dir" GITHUB_SHA="$(git -C "$dir" rev-parse HEAD)" \
    bash "$BODY" --channel "$channel" --summary "$SUMMARY" 2>&1 >/dev/null
}

echo "a release carries the changelog as it stands"
d="$(repo)"
write_changelog "$d" 'Tools: a thing (by @mishamyte | PR #1)'
commit "$d" 'first'
got="$(run "$d" release)"
# The whole body: an exact comparison says "no dev furniture" and "the right
# furniture" at once, where a set of negative greps cannot tell either from
# "printed nothing useful".
want="$SUMMARY

## Main changes
- Tools: a thing (by @mishamyte | PR #1)
## Other changes"
[[ "$got" == "$want" ]] &&
  pass "the one-liner, then the whole file with the version line dropped" ||
  fail "release body was: $got"

d="$(repo)"
write_changelog "$d"
commit "$d" 'first'
got="$(run "$d" release)"
[[ "$got" == "$SUMMARY" ]] &&
  pass "a changelog with no notes publishes the one-liner alone" ||
  fail "empty-changelog release body was: $got"

echo
echo "a dev build names what is new since the one before it"
d="$(repo)"
write_changelog "$d" 'Tools: shipped earlier (by @mishamyte | PR #1)'
commit "$d" 'the previous build'
tag_dev "$d"
base="$(git -C "$d" rev-parse HEAD)"
write_changelog "$d" \
  'Tools: shipped earlier (by @mishamyte | PR #1)' \
  'Archive: brand new (by @apfxtech | PR #2)'
commit "$d" 'the new one (#2)'
got="$(run "$d" dev)"
sha="$(git -C "$d" rev-parse HEAD)"
# The whole body, byte for byte, on the path that runs on every push. Grepping
# for the pieces left the blank lines free, and the one before the link is
# load-bearing: without it CommonMark reads the link as a lazy continuation of
# the last bullet and renders it *inside* that bullet. No grep can see that.
want="$SUMMARY

## New in this build
- Archive: brand new (by @apfxtech | PR #2)

[All changes](https://github.com/mishamyte/qUnleashed/blob/$sha/CHANGELOG.md)"
if [[ "$got" == "$want" ]]; then
  pass "the new bullet, its heading, the blank lines and the pinned link"
else
  fail "dev body was: $got"
fi
! grep -q 'shipped earlier' <<<"$got" &&
  pass "and the bullet the baseline already published is absent" ||
  fail "a shipped bullet was reprinted: $got"
err="$(run_err "$d" dev)"
# The count, not just the sha: this log line is the only place a maintainer can
# see what the script decided without reading the published page, and it was
# free to say any number.
grep -qF "Release body: 1 new note(s) since $base" <<<"$err" &&
  pass "the log names what it counted and the baseline it counted from" ||
  fail "log line was: $err"

# A reworded bullet is new text nobody has read on a page yet. The script's
# comment calls this deliberate, so it is asserted rather than assumed.
d="$(repo)"
baselined "$d"
write_changelog "$d" 'Tools: a thing, reworded (by @mishamyte | PR #1)'
commit "$d" 'reword it'
got="$(run "$d" dev)"
grep -q 'reworded' <<<"$got" &&
  pass "a reworded bullet counts as new" || fail "reword gave: $got"

# A bullet moved between the sections is not new. `git diff` would call it
# added, which is why the two files' bullets are compared instead.
d="$(repo)"
baselined "$d"
{
  printf '## Main changes\n- Version: 0.16.0\n## Other changes\n'
  printf -- '- Tools: a thing (by @mishamyte | PR #1)\n'
} >"$d/CHANGELOG.md"
commit "$d" 'moved it'
got="$(run "$d" dev)"
if ! grep -q 'Tools: a thing' <<<"$got" && grep -q 'Nothing was added' <<<"$got"; then
  pass "a bullet moved between sections does not count as new"
else
  fail "moved bullet was reported as new: $got"
fi

echo
echo "only a line that starts a bullet is a note"
# `check_changelog.sh` validates lines matching `^-[[:space:]]` and says
# nothing about indented ones, so a sub-bullet is permitted in the file. An
# unanchored match would publish one as a note of its own, and prose inside a
# bullet is full of ` - ` besides.
d="$(repo)"
baselined "$d"
{
  printf '## Main changes\n- Version: 0.16.0\n'
  printf -- '- Tools: a thing (by @mishamyte | PR #1)\n'
  printf -- '- Archive: a new one - with a dash in its prose (by @apfxtech | PR #2)\n'
  printf '  - an indented sub-bullet, which the guard permits\n'
  printf '## Other changes\n'
} >"$d/CHANGELOG.md"
commit "$d" 'add one (#2)'
got="$(run "$d" dev)"
if grep -q 'Archive: a new one' <<<"$got" &&
  ! grep -q 'indented sub-bullet' <<<"$got"; then
  pass "an indented sub-bullet is not a note, and a dash in prose is not one"
else
  fail "sub-bullet body was: $got"
fi

echo
echo "the comparison is whole-line and literal"
# Pins `-x`: a bullet extended with a trailing clause has the old one as a
# prefix, and substring matching drops it as already-seen.
d="$(repo)"
baselined "$d"
write_changelog "$d" \
  'Tools: a thing (by @mishamyte | PR #1)' \
  'Tools: a thing (by @mishamyte | PR #1) and then some (by @apfxtech | PR #2)'
commit "$d" 'extend it'
got="$(run "$d" dev)"
grep -q 'and then some' <<<"$got" &&
  pass "a bullet whose prefix is an old bullet is still new" ||
  fail "prefix bullet was swallowed: $got"

# Pins `-F`: the real changelog is full of `**`, `(`, `|`, `.` and brackets, and
# an unterminated `[` makes grep exit 2 rather than match nothing.
d="$(repo)"
write_changelog "$d" 'Tools: a [thing] with **bold** and (parens) (by @mishamyte | PR #1)'
commit "$d" 'the previous build'
tag_dev "$d"
write_changelog "$d" \
  'Tools: a [thing] with **bold** and (parens) (by @mishamyte | PR #1)' \
  'Archive: another [one] (by @apfxtech | PR #2)'
commit "$d" 'add one (#2)'
got="$(run "$d" dev)"
if grep -q 'Archive: another' <<<"$got" && ! grep -q 'Tools: a \[thing\]' <<<"$got"; then
  pass "bullets holding regex metacharacters are matched literally"
else
  fail "metacharacter bullets gave: $got"
fi

echo
echo "a cycle boundary is not a diff"
# Nothing clears the `dev` tag when a release is cut, so the first dev build of a
# new cycle baselines against the previous cycle's full changelog. Its notes all
# shipped; the version line is what says so.
d="$(repo)"
QU_TEST_VERSION=0.16.0 write_changelog "$d" \
  'Tools: shipped in 0.16.0 (by @mishamyte | PR #1)'
commit "$d" 'the last build of the old cycle'
tag_dev "$d"
QU_TEST_VERSION=0.17.0 write_changelog "$d" \
  'Archive: the first note of the new cycle (by @apfxtech | PR #2)'
commit "$d" 'open the 0.17.0 cycle'
got="$(run "$d" dev)"
if grep -q 'the first note of the new cycle' <<<"$got" &&
  ! grep -q 'shipped in 0.16.0' <<<"$got"; then
  pass "the new cycle's notes are all new, and the old cycle's are gone"
else
  fail "cycle boundary gave: $got"
fi
err="$(run_err "$d" dev)"
grep -q 'another cycle' <<<"$err" &&
  pass "the log says the baseline was in another cycle" ||
  fail "no cycle note in the log: $err"

# The same boundary with a note whose text repeats one already shipped. Diffing
# across the boundary would drop it for matching.
d="$(repo)"
QU_TEST_VERSION=0.16.0 write_changelog "$d" 'Fixed: the same wording (by @apfxtech)'
commit "$d" 'the last build of the old cycle'
tag_dev "$d"
QU_TEST_VERSION=0.17.0 write_changelog "$d" 'Fixed: the same wording (by @apfxtech)'
commit "$d" 'open the 0.17.0 cycle'
got="$(run "$d" dev)"
grep -q 'the same wording' <<<"$got" &&
  pass "a repeated wording in a new cycle is not dropped" ||
  fail "repeated wording was dropped: $got"

# Pins the empty-pattern-file case directly: the build after a cycle opened, so
# the baseline's changelog is the skeleton and has no notes at all. This fires
# once every cycle, on the build carrying the cycle's first bullet.
d="$(repo)"
write_changelog "$d"
commit "$d" 'the cycle opener'
tag_dev "$d"
write_changelog "$d" 'Tools: the first note of the cycle (by @mishamyte | PR #1)'
commit "$d" 'the first real change (#1)'
got="$(run "$d" dev)"
if grep -q 'the first note of the cycle' <<<"$got" &&
  ! grep -q 'Nothing was added' <<<"$got"; then
  pass "a notes-free baseline makes every note new"
else
  fail "notes-free baseline gave: $got"
fi

echo
echo "a dev build whose push added no note"
d="$(repo)"
baselined "$d"
printf 'nothing to do with the notes\n' >"$d/lib.dart"
commit "$d" 'Tidy the CI scripts (#300)'
got="$(run "$d" dev)"
if grep -q 'Nothing was added to the changelog' <<<"$got" &&
  grep -q -- '^- Tidy the CI scripts (#300)$' <<<"$got" &&
  ! grep -q 'Tools: a thing' <<<"$got"; then
  pass "the commit subjects stand in, and no stale bullet is reprinted"
else
  fail "no-note body was: $got"
fi
grep -q 'All changes' <<<"$got" &&
  pass "the link is there either way" || fail "no link: $got"

# Which ten, and where the count sits. `--max-count` is applied before
# `--reverse`, so the ten printed are the newest and the ones left out are the
# oldest - the count has to sit above the list to say so. Asserting the count
# alone left both the selection and the order free.
d="$(repo)"
baselined "$d"
for i in $(seq 1 12); do
  printf 'change %s\n' "$i" >"$d/lib.dart"
  commit "$d" "commit number $i"
done
got="$(run "$d" dev)"
if [[ "$(grep -c '^- commit number' <<<"$got")" == 10 ]] &&
  grep -q -- '^- \.\.\.and 2 earlier commits$' <<<"$got"; then
  pass "ten subjects and a count for the rest"
else
  fail "twelve-commit body was: $got"
fi
if grep -q -- '^- commit number 12$' <<<"$got" &&
  ! grep -q -- '^- commit number 1$' <<<"$got"; then
  pass "the ten kept are the newest, and the oldest are the ones dropped"
else
  fail "the wrong ten were kept: $got"
fi
# The count names the end of the list it is next to.
listed="$(grep -n -- '^- ' <<<"$got")"
if [[ "$(sed -n '1p' <<<"$listed")" == *'earlier commits'* ]] &&
  [[ "$(sed -n '2p' <<<"$listed")" == *'commit number 3'* ]]; then
  pass "the count sits above the list, next to the end it describes"
else
  fail "the count is in the wrong place: $listed"
fi

# The cap boundary. Exactly ten must not print "and 0 earlier commits".
d="$(repo)"
baselined "$d"
for i in $(seq 1 10); do
  printf 'change %s\n' "$i" >"$d/lib.dart"
  commit "$d" "commit number $i"
done
got="$(run "$d" dev)"
if [[ "$(grep -c '^- commit number' <<<"$got")" == 10 ]] &&
  ! grep -q 'earlier commits' <<<"$got"; then
  pass "exactly ten commits print ten subjects and no count"
else
  fail "ten-commit body was: $got"
fi

# A publish re-run on a commit that was already built: the previous run retagged
# `dev` here, so the baseline is this commit.
d="$(repo)"
write_changelog "$d" 'Tools: a thing (by @mishamyte | PR #1)'
commit "$d" 'the only build'
tag_dev "$d"
got="$(run "$d" dev)"
if grep -q 'rebuild of the commit' <<<"$got" &&
  ! grep -q 'Commits since' <<<"$got"; then
  pass "a rebuild of the same commit says so"
else
  fail "rebuild body was: $got"
fi

echo
echo "a dev build with no usable baseline falls back to the whole changelog"
d="$(repo)"
write_changelog "$d" 'Tools: a thing (by @mishamyte | PR #1)'
commit "$d" 'first'
got="$(run "$d" dev)"
if grep -q 'Tools: a thing' <<<"$got" &&
  grep -q 'All changes' <<<"$got" &&
  ! grep -q 'New in this build' <<<"$got" &&
  ! grep -q 'Version: 0.16.0' <<<"$got"; then
  pass "no dev tag at all degrades to the whole file, link included"
else
  fail "no-tag body was: $got"
fi
err="$(run_err "$d" dev)"
if grep -q '::notice::No dev tag' <<<"$err" && ! grep -q '::warning::' <<<"$err"; then
  pass "a repository with no dev tag says so as a notice, not a warning"
else
  fail "no-tag annotation was: $err"
fi

# A tag that resolves to a commit whose changelog cannot be read. The whole
# accumulated file must NOT appear under "New in this build", which would claim
# weeks-old work as new in this build.
d="$(repo)"
printf 'no changelog here yet\n' >"$d/lib.dart"
commit "$d" 'before the changelog existed'
tag_dev "$d"
write_changelog "$d" 'Tools: shipped weeks ago (by @mishamyte | PR #1)'
commit "$d" 'add the changelog'
got="$(run "$d" dev)"
if grep -q 'Tools: shipped weeks ago' <<<"$got" &&
  ! grep -q 'New in this build' <<<"$got"; then
  pass "an unreadable baseline changelog degrades rather than claiming it new"
else
  fail "unreadable baseline gave: $got"
fi
err="$(run_err "$d" dev)"
grep -q '::warning::.*Could not read CHANGELOG.md' <<<"$err" &&
  pass "and says so at warning level" ||
  fail "no warning: $err"

# A changelog with nothing in it either: the body is the one-liner and the link,
# which is the least the page can say without reading as a broken build.
d="$(repo)"
write_changelog "$d"
commit "$d" 'first'
got="$(run "$d" dev)"
[[ "$got" == "$SUMMARY

[All changes](https://github.com/mishamyte/qUnleashed/blob/$(git -C "$d" rev-parse HEAD)/CHANGELOG.md)" ]] &&
  pass "no baseline and no notes still publishes a link" ||
  fail "bare body was: $got"

echo
echo "it says which kind of trouble the baseline is in"
# The classifier exists to separate an absent ref from git failing to answer, and
# only the absent arm was covered. A tag naming a blob reaches the other one.
d="$(repo)"
baselined "$d"
blob="$(git -C "$d" hash-object -w "$d/CHANGELOG.md")"
git -C "$d" update-ref refs/tags/dev "$blob"
printf 'something\n' >"$d/lib.dart"
commit "$d" 'a later commit'
err="$(run_err "$d" dev)"
got="$(run "$d" dev)"
if grep -q '::warning::The dev tag does not name a commit' <<<"$err" &&
  grep -q 'git said:' <<<"$err" &&
  ! grep -q 'New in this build' <<<"$got"; then
  pass "a dev tag that is not a commit names that, not a missing tag"
else
  fail "non-commit tag gave log: $err"
fi

# Tags but no `dev`: a release removed by hand, after which every build keeps
# publishing the whole changelog. Louder than a repository's first-ever build.
d="$(repo)"
write_changelog "$d" 'Tools: a thing (by @mishamyte | PR #1)'
commit "$d" 'first'
git -C "$d" tag 0.15.0
err="$(run_err "$d" dev)"
if grep -q '::warning::There are tags but no dev tag' <<<"$err" &&
  ! grep -q '::notice::' <<<"$err"; then
  pass "tags but no dev tag warns, rather than taking the first-build notice"
else
  fail "deleted-release log was: $err"
fi

# A branch called `dev` must not change the answer. The short `dev` would be
# ambiguous here; the script names `refs/tags/dev` so there is nothing to be
# ambiguous about, and nothing to annotate.
d="$(repo)"
baselined "$d"
git -C "$d" branch dev
printf 'something\n' >"$d/lib.dart"
write_changelog "$d" \
  'Tools: a thing (by @mishamyte | PR #1)' \
  'Archive: and another (by @apfxtech | PR #2)'
commit "$d" 'a later commit (#2)'
err="$(run_err "$d" dev)"
got="$(run "$d" dev)"
if grep -q 'Archive: and another' <<<"$got" &&
  ! grep -q 'Tools: a thing' <<<"$got" &&
  ! grep -q '::warning::' <<<"$err"; then
  pass "a branch named dev changes nothing, and warns about nothing"
else
  fail "branch named dev gave log: $err / body: $got"
fi

# A depth-1 checkout answers for `dev` exactly as an absent tag does, so without
# the guard the steady state is the whole changelog on every build, forever,
# under a notice blaming a deletion.
d="$(repo)"
baselined "$d"
printf 'something\n' >"$d/lib.dart"
commit "$d" 'a later commit'
shallow="$(mktemp -d "$TMP/shallow-XXXXXX")"
if git clone --quiet --depth=1 "file://$d" "$shallow/repo" 2>/dev/null &&
  [[ "$(git -C "$shallow/repo" rev-parse --is-shallow-repository)" == true ]]; then
  if out="$(QU_REPO_ROOT="$shallow/repo" \
    GITHUB_SHA="$(git -C "$shallow/repo" rev-parse HEAD)" \
    bash "$BODY" --channel dev --summary "$SUMMARY" 2>&1)"; then
    fail "a shallow checkout published instead of refusing: $out"
  elif grep -q '::error::This checkout is shallow' <<<"$out"; then
    pass "a shallow checkout is refused, naming fetch-depth"
  else
    fail "shallow checkout gave: $out"
  fi
else
  fail "could not build a shallow fixture, so the guard is untested"
fi

# A revision with no version line is an anomaly, not a cycle boundary - and it is
# the one that would publish shipped notes under "New in this build".
d="$(repo)"
baselined "$d" 'Tools: shipped a fortnight ago (by @mishamyte | PR #1)'
{
  printf '## Main changes\n'
  printf -- '- Tools: shipped a fortnight ago (by @mishamyte | PR #1)\n'
  printf -- '- Archive: actually new (by @apfxtech | PR #2)\n'
  printf '## Other changes\n'
} >"$d/CHANGELOG.md"
commit "$d" 'lose the version line (#2)'
got="$(run "$d" dev)"
err="$(run_err "$d" dev)"
if ! grep -q 'New in this build' <<<"$got" &&
  grep -q "::warning::A changelog revision carries no" <<<"$err"; then
  pass "a missing version line gives up the baseline rather than guessing"
else
  fail "missing version line gave body: $got / log: $err"
fi

echo
echo "the release warning that moved in from the workflow"
# It arrived here untested: the companion case asserts the body, and `run`
# discards stderr.
d="$(repo)"
write_changelog "$d"
commit "$d" 'first'
err="$(run_err "$d" release)"
grep -q '::warning::No notes in CHANGELOG.md' <<<"$err" &&
  pass "a release with nothing written is annotated" ||
  fail "no-notes release log was: $err"
d="$(repo)"
write_changelog "$d" 'Tools: a thing (by @mishamyte | PR #1)'
commit "$d" 'first'
err="$(run_err "$d" release)"
! grep -q '::warning::' <<<"$err" &&
  pass "and a release with notes is not" ||
  fail "spurious release warning: $err"

echo
echo "the fixtures satisfy the guard the real changelog is held to"
# open_next_cycle_test.sh pairs with check_changelog.sh for this reason: what the
# fixture writes has to satisfy the guard, or `notes()` is being tested against a
# grammar the committed file never has and the suite is blind to the drift.
d="$(repo)"
write_changelog "$d"   'Tools: **A headline** - what it does (by @mishamyte | PR #1 | Closes #2)'   'Fixed: a smaller one (by @apfxtech)'
printf 'name: qunleashed
description: a thing
version: 0.16.0
environment:
  sdk: ^3.13.0
'   >"$d/pubspec.yaml"
if out="$(bash "$HERE/check_changelog.sh" "$d/CHANGELOG.md" "$d/pubspec.yaml" 2>&1)"; then
  pass "a representative fixture passes check_changelog.sh"
else
  fail "the fixture grammar has drifted from the guard: $out"
fi

echo
echo "it gives up a baseline it cannot trust"
# A `dev` off this branch - a force-push, or a tag moved by hand. Every read
# would otherwise answer about an unrelated history.
d="$(repo)"
baselined "$d"
git -C "$d" checkout --quiet -b sideways
printf 'elsewhere
' >"$d/lib.dart"
write_changelog "$d" 'Tools: written on another branch (by @apfxtech)'
commit "$d" 'a commit nobody will merge'
tag_dev "$d"
git -C "$d" checkout --quiet -
got="$(run "$d" dev)"
err="$(run_err "$d" dev)"
if ! grep -q 'New in this build' <<<"$got" &&
  grep -q '::warning::.*not an ancestor of HEAD' <<<"$err"; then
  pass "a dev tag off this branch is given up, and named"
else
  fail "off-branch tag gave body: $got / log: $err"
fi

# `dev` already naming HEAD is the documented re-run. On a *first* attempt it
# means the body is being written after the release was published - and the
# answer is a warning plus the whole changelog, not a refusal. A refusal is the
# one thing that cannot work: it prompts the re-run that makes the attempt
# number 2, which skips the check and publishes "this is a rebuild" - the page
# the check exists to prevent. So this asserts the shape, not an exit code.
d="$(repo)"
write_changelog "$d" 'Tools: a thing (by @mishamyte | PR #1)'
commit "$d" 'the only build'
tag_dev "$d"
run_first() {
  QU_REPO_ROOT="$d" GITHUB_SHA="$(git -C "$d" rev-parse HEAD)" \
    GITHUB_RUN_ATTEMPT="${1:-1}" bash "$BODY" --channel dev --summary "$SUMMARY" 2>"$TMP/first-err"
}
got="$(run_first)"
err="$(cat "$TMP/first-err")"
if grep -q 'Tools: a thing' <<<"$got" &&
  ! grep -q 'New in this build' <<<"$got" &&
  ! grep -q 'rebuild of the commit' <<<"$got" &&
  grep -q '::warning::The dev tag already names HEAD on the first attempt' <<<"$err"; then
  pass "dev naming HEAD on the first attempt warns and carries the whole changelog"
else
  fail "first-attempt self-baseline gave body: $got / log: $err"
fi
# `01` is attempt 1 written with a leading zero, so it must take the same
# branch - and the `10#` in the script is what stops `08` aborting on invalid
# octal.
for one in 1 01 001; do
  err="$(run_first "$one" >/dev/null; cat "$TMP/first-err")"
  grep -q '::warning::The dev tag already names HEAD on the first attempt' <<<"$err" &&
    pass "GITHUB_RUN_ATTEMPT='$one' is read as attempt 1, base 10" ||
    fail "GITHUB_RUN_ATTEMPT='$one' gave: $err"
done
# And a padded attempt number that is not 1 must not abort on octal either.
out="$(QU_REPO_ROOT="$d" GITHUB_SHA="$(git -C "$d" rev-parse HEAD)" GITHUB_RUN_ATTEMPT=08 \
  bash "$BODY" --channel dev --summary "$SUMMARY" 2>/dev/null)"
grep -q 'rebuild of the commit' <<<"$out" &&
  pass "GITHUB_RUN_ATTEMPT='08' is read base 10, not as invalid octal" ||
  fail "octal attempt gave: $out"

out="$(QU_REPO_ROOT="$d" GITHUB_SHA="$(git -C "$d" rev-parse HEAD)" GITHUB_RUN_ATTEMPT=2 \
  bash "$BODY" --channel dev --summary "$SUMMARY" 2>/dev/null)"
grep -q 'rebuild of the commit' <<<"$out" &&
  pass "and on a later attempt it is the documented re-run" ||
  fail "second-attempt rebuild gave: $out"

echo
echo "it refuses what it cannot build a body from"
d="$(repo)"
write_changelog "$d" 'Tools: a thing (by @mishamyte | PR #1)'
commit "$d" 'first'
sha="$(git -C "$d" rev-parse HEAD)"

# Each refusal is matched on its reason, not just on a non-zero exit: three
# tests that assert only "it failed" cannot tell one cause from another.
# `grep -F -e`: four of these five patterns open with `--`, which grep would
# otherwise read as an option of its own.
check_refusal() {
  local label="$1" want="$2"; shift 2
  local out
  if out="$(QU_REPO_ROOT="$d" GITHUB_SHA="$sha" bash "$BODY" "$@" 2>&1)"; then
    fail "$label was accepted, printing: $out"
  elif grep -qF -e "$want" <<<"$out"; then
    pass "$label is refused, naming '$want'"
  else
    fail "$label was refused without naming '$want': $out"
  fi
}

check_refusal "a bad channel" "--channel must be" --channel nightly --summary x
check_refusal "a missing summary" "--summary is required" --channel dev
check_refusal "a dangling --channel" "--channel must be" --channel
check_refusal "a missing channel" "--channel must be" --summary x
check_refusal "an unknown flag" "Unrecognised argument"   --channel dev --summary x --oops

# Every one of the four, not only GITHUB_SHA. GITHUB_RUN_ATTEMPT is in the loop
# because an unset value silently *weakens* the step-order guard rather than
# breaking an output, which is the worse direction to fail in.
#
# The status is asserted as well as the message: a guard downgraded to
# warning-and-continue would still print its message, and still publish.
for var in GITHUB_SERVER_URL GITHUB_REPOSITORY GITHUB_SHA GITHUB_RUN_ATTEMPT; do
  if out="$(QU_REPO_ROOT="$d" GITHUB_SHA="$sha" env "$var=" \
    bash "$BODY" --channel dev --summary x 2>&1)"; then
    fail "an unset $var published instead of refusing: $out"
  elif grep -q "::error::$var is not set" <<<"$out"; then
    pass "an unset $var is refused, and named"
  else
    fail "unset $var gave: $out"
  fi
done

# A non-numeric value must not quietly disable that guard. `01` is not in this
# list: it *is* attempt 1, and the case below proves the guard still fires on
# it rather than the value being refused.
for bad in " 1" abc 1.0; do
  if out="$(QU_REPO_ROOT="$d" GITHUB_SHA="$sha" GITHUB_RUN_ATTEMPT="$bad" \
    bash "$BODY" --channel dev --summary x 2>&1)"; then
    fail "GITHUB_RUN_ATTEMPT='$bad' published instead of refusing: $out"
  elif grep -q '::error::GITHUB_RUN_ATTEMPT' <<<"$out"; then
    pass "GITHUB_RUN_ATTEMPT='$bad' is refused as not a number"
  else
    fail "GITHUB_RUN_ATTEMPT='$bad' gave: $out"
  fi
done

# The link is built from GITHUB_SHA and the notes are read from HEAD. A `ref:`
# on the checkout step would make them different commits silently.
if out="$(QU_REPO_ROOT="$d" GITHUB_SHA=0000000000000000000000000000000000000000 \
  bash "$BODY" --channel dev --summary x 2>&1)"; then
  fail "a GITHUB_SHA that is not HEAD published instead of refusing: $out"
elif grep -q 'GITHUB_SHA is 0000000' <<<"$out" && grep -q "$sha" <<<"$out"; then
  pass "a GITHUB_SHA that is not HEAD is refused, naming both"
else
  fail "sha mismatch gave: $out"
fi

if out="$(QU_REPO_ROOT="$TMP/not-a-repo" GITHUB_SHA="$sha" bash "$BODY" \
  --channel release --summary x 2>&1)"; then
  fail "a missing changelog was accepted, printing: $out"
else
  grep -q 'No CHANGELOG.md at' <<<"$out" &&
    pass "a missing changelog is refused" ||
    fail "refused for the wrong reason: $out"
fi

echo
if (( failures )); then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
