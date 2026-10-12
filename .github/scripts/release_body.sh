#!/usr/bin/env bash
# Writes the body of the GitHub release page to stdout.
#
#   release_body.sh --channel dev|release --summary "<one-liner>"
#
# This file owns the reasoning; `auto-release.yml`, `docs/releasing.md` and ADR
# 0014 §7 describe what it produces and point here for why.
#
# A release gets `CHANGELOG.md` as it stands, which is what the file is for: it
# accumulates until a stable release, so the page answers "what is new since the
# last release" in the prose somebody wrote at the time.
#
# A dev build got the same thing, re-published on every push, and nothing on the
# page marked what was new in *this* build - which `docs/releasing.md` used to
# say in as many words, until this change replaced that paragraph. So a dev body
# names only the bullets that have appeared since the previous dev build, and
# links the accumulated file for the rest.
#
# **The baseline is the previous dev build's commit, not HEAD~1 or the push
# range.** Those two miss a bullet whose push never built: `CHANGELOG.md` is
# matched by `**/*.md` in `auto-release.yml`'s `paths-ignore`, so a changelog-only
# push produces no run at all and its bullet would appear in no dev body ever.
# Diffing against the build somebody last installed cannot skip anything, which
# is also the question a reader of the page is asking.
#
# **And it comes from the `dev` tag**, which every dev build already moves to
# its own commit - ADR 0014 §7's single rolling prerelease, deleted and
# recreated per push by `auto-release.yml`. No API call, no token, nothing
# parsed out of the previous page's prose.
#
# What makes that safe is the checkout, not the step order: `actions/checkout`
# snapshots `refs/tags/dev` locally at the job's first step, and the clear step
# later deletes the *remote* ref, which cannot affect a local tag nothing
# re-fetches. So the clear step may be moved anywhere after the checkout - and
# it cannot precede the body step in any case, because its `if:` reads an
# output of it.
#
# What would break this is losing the snapshot: writing the body from a second
# job, or adding a `git fetch --prune --prune-tags` ahead of it. Pruning tags
# takes both flags - `--prune-tags` alone is a no-op and `--tags --force` only
# overwrites, so neither of those touches a tag the remote no longer has. The
# other way it breaks is a tag already moved to HEAD within this run, which the
# guard below catches on a first attempt.
set -Eeuo pipefail

# `-E` above is worth nothing without this. The caller redirects stdout into
# the body file, so a bare `awk`, `git` or `grep` diagnostic on an abort is
# easy to lose, and nothing would annotate the run at all.
trap 'echo "::error::release_body.sh failed at line $LINENO: $BASH_COMMAND" >&2' ERR

channel=""
summary=""
while (( $# )); do
  # `$# >= 2` before the shift: `--channel` with nothing after it would
  # otherwise fail on `shift 2` and exit with no message at all, which is the
  # one failure here that says nothing.
  case "$1" in
    --channel) (( $# >= 2 )) && [[ "$2" != --* ]] || break; channel="$2"; shift 2 ;;
    --summary) (( $# >= 2 )) && [[ "$2" != --* ]] || break; summary="$2"; shift 2 ;;
    *) break ;;
  esac
done

usage() { echo "Usage: $0 --channel dev|release --summary <one-liner>" >&2; }

if [[ "$channel" != dev && "$channel" != release ]]; then
  echo "::error::--channel must be dev or release, not '$channel'." >&2
  usage
  exit 1
fi
# The one-liner is the first line of the body and the whole of the push
# notification, so the caller owns it and this script is handed the same string
# rather than assembling a second copy that can drift from it.
if [[ -z "$summary" ]]; then
  echo "::error::--summary is required: it is the first line of the release body." >&2
  usage
  exit 1
fi
# Anything left over is a flag this does not have. Ignoring it would publish an
# ordinary page for a call that asked for something else.
if (( $# )); then
  echo "::error::Unrecognised argument '$1'." >&2
  usage
  exit 1
fi

# Every git read goes through an explicit root, so a step with a
# `working-directory:` cannot make them answer about the wrong tree.
# QU_REPO_ROOT is how the test points them at a fixture repository of its own.
repo_root="${QU_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
changelog="$repo_root/CHANGELOG.md"
if [[ ! -f "$changelog" ]]; then
  echo "::error::No CHANGELOG.md at $changelog." >&2
  exit 1
fi

# A bullet that is not the version line is a note. awk rather than grep because
# a changelog with no notes yet is the normal case on the first day of a cycle,
# and a plain `grep` exits 1 on no match, which `set -e` would take as fatal.
# This is the only copy in the release-body path: the workflow carried a second
# until the release warning moved in here with it. `check_changelog.sh` has an
# equivalent of its own, for validating the file rather than reading it.
notes() { awk '/^- / && !/^- Version: /' "$@"; }

# The version the file describes. `check_changelog.sh` guarantees there is
# exactly one of these and that it agrees with pubspec, which is what makes it
# usable as the identity of a release cycle below.
version_line() { awk '/^- Version: /{print; exit}' "$@"; }

has_notes=0
[[ -n "$(notes "$changelog")" ]] && has_notes=1

# The page as it stood before any of this: the one-liner, and under it the file
# minus its version line, which names the version being built toward and is
# already in the one-liner. A release publishes exactly this, and so does a dev
# build with no usable baseline.
#
# The one-liner goes out either way. A page whose entire body is
# "## Main changes" reads as a broken build rather than a new one.
whole_body() {
  printf '%s\n' "$summary"
  if (( has_notes )); then
    printf '\n'
    awk '!/^- Version: /' "$changelog"
  fi
}

if [[ "$channel" == release ]]; then
  whole_body
  # A release with nothing written is a mistake to name, not one to paper over
  # with a generated list that reads like notes.
  (( has_notes )) ||
    echo "::warning::No notes in CHANGELOG.md, so this release publishes with only its version line." >&2
  exit 0
fi

# --- a dev build: what is new since the one before it -----------------------
#
# Everything below runs only on a dev build - the release channel returned
# above - and that is what licenses the refusals in it. A dev build is
# disposable (ADR 0014 §6, §7): refusing one costs a red run that the next
# push repairs, where guessing costs a page somebody reads and believes. The
# release path has no runtime guard at all for the same reason in reverse.

# GITHUB_RUN_ATTEMPT is checked here rather than where it is read, because the
# guard below is the one place a missing variable would *weaken* a check
# instead of breaking an output: an unset value makes the step-order test
# false, which turns that error into a published page. Larger consequence
# than the other three, so it is held to the same standard.
for var in GITHUB_SERVER_URL GITHUB_REPOSITORY GITHUB_SHA GITHUB_RUN_ATTEMPT; do
  if [[ -z "${!var:-}" ]]; then
    echo "::error::$var is not set, so this page cannot be built safely." >&2
    exit 1
  fi
done
# Numerically below, so a padded or zero-padded value cannot disable it.
if [[ ! "$GITHUB_RUN_ATTEMPT" =~ ^[0-9]+$ ]]; then
  echo "::error::GITHUB_RUN_ATTEMPT is '$GITHUB_RUN_ATTEMPT', not a number, so the step-order guard cannot be evaluated." >&2
  exit 1
fi

# The link is pinned to GITHUB_SHA while every git read below is against HEAD,
# and pinned to a sha rather than `main` so somebody coming back to an older dev
# build reads the file as it stood for that build. The two are the same commit
# because `actions/checkout` checks out GITHUB_SHA, and a future `ref:` on that
# step would otherwise make the page link one commit's changelog while
# describing another's commits.
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
if [[ "$head_sha" != "$GITHUB_SHA" ]]; then
  echo "::error::GITHUB_SHA is $GITHUB_SHA but the checkout is at $head_sha, so the link and the notes would describe different commits." >&2
  exit 1
fi
link="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/blob/$GITHUB_SHA/CHANGELOG.md"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A depth-1 checkout gives the same "unknown revision" for `dev` that an
# absent tag does, so without this the steady state is every build publishing
# the whole changelog under a notice that blames a deleted release.
# `derive_version.sh` guards its commit count against the same read for the
# same reason: a shallow checkout answers plausibly rather than failing. Its
# version also tolerates "not a repository"; this one need not, because
# `rev-parse HEAD` above has already failed by then.
if [[ "$(git -C "$repo_root" rev-parse --is-shallow-repository)" != false ]]; then
  echo "::error::This checkout is shallow, so the dev tag cannot be resolved and every build would publish the whole changelog. Use fetch-depth: 0." >&2
  exit 1
fi

# Whatever git last wrote to `$tmp/err`, on one line: a multi-line `::warning::`
# loses everything after its first line in the run log.
git_said() { tr '\n' ' ' <"$tmp/err"; }

# Sets `base` to the commit the previous dev build came from and `$tmp/old` to
# the notes that build had already published - or leaves `base` empty, with an
# annotation saying why, when there is no baseline this page can honestly diff
# against.
#
# Each give-up `return`s instead of setting a sentinel and falling through to a
# test fifty lines on, which is what every new arm otherwise has to remember to
# do. It assigns rather than prints, because an `exit` inside a `$( )` leaves
# only the subshell - so a fatal guard written in the printing form would
# quietly become warn-and-publish.
#
# None of these is fatal. Every one of them has an honest page available - the
# whole changelog, which is what the release page carried before any of this -
# and a refusal here would block a dev publish for something a reader can see
# annotated on the run.
resolve_baseline() {
  base=""
  : >"$tmp/old"

  # Existence first, and `refs/tags/dev` rather than `dev`: a branch of the same
  # name makes the short form ambiguous, and the full ref cannot be.
  #
  # Which kind of absence this is turns on the ref, not on what git said. The
  # messages do differ - a missing tag says only "Needed a single revision"
  # while an unpeelable one leads with "dereferences to blob type" - but
  # matching either would pin git's wording across versions, and getting it
  # wrong names the wrong fault: "no dev tag" for a tag that is right there.
  if ! git -C "$repo_root" show-ref --verify --quiet refs/tags/dev; then
    if [[ -n "$(git -C "$repo_root" tag --list)" ]]; then
      # Other tags exist and `dev` does not, so the release was removed outside
      # this workflow - and every build after this one keeps publishing the
      # whole changelog until somebody notices.
      echo "::warning::There are tags but no dev tag, so the dev release was removed outside this workflow. Every build publishes the whole changelog until the next one republishes it." >&2
    else
      # No tags at all: a repository that has never published anything. Once in
      # its life, and genuinely a fact rather than a fault.
      echo "::notice::No dev tag yet, so there is no previous dev build to compare against and this page carries the whole changelog." >&2
    fi
    return
  fi

  local candidate ancestry was_version now_version
  if ! candidate="$(git -C "$repo_root" rev-parse --verify 'refs/tags/dev^{commit}' 2>"$tmp/err")"; then
    echo "::warning::The dev tag does not name a commit, so this page carries the whole changelog instead of what is new. git said: $(git_said)" >&2
    return
  fi
  if [[ -s "$tmp/err" ]]; then
    # `rev-parse` writes here on success too. Naming the ref in full took away
    # the ambiguity warning this first covered, so nothing names a case it is
    # known to catch - it stays because the one ref this whole output hinges on
    # is not the place to discard something git felt worth saying.
    echo "::warning::git said while resolving the dev tag: $(git_said)" >&2
  fi

  # A baseline off this branch makes every read below answer about an unrelated
  # history: `git show` succeeds against another file, and `rev-list a..HEAD`
  # counts one side of a fork. A force-push to `main`, or a tag moved by hand,
  # is how it happens.
  #
  # `--is-ancestor` exits 0 for yes, 1 for no, and >=2 when it could not tell:
  # a bad object, an unreadable store, a killed process. `! cmd` reads the last
  # two alike, and the message would then state "not an ancestor of HEAD" as a
  # fact git never gave, sending a reader after a force-push that never
  # happened.
  ancestry=0
  git -C "$repo_root" merge-base --is-ancestor "$candidate" HEAD 2>"$tmp/err" || ancestry=$?
  if (( ancestry >= 2 )); then
    echo "::warning::git could not decide whether $candidate is an ancestor of HEAD (exit $ancestry), so this page carries the whole changelog instead of what is new. git said: $(git_said)" >&2
    return
  elif (( ancestry )); then
    echo "::warning::The dev tag names $candidate, which is not an ancestor of HEAD, so this page carries the whole changelog instead of what is new." >&2
    return
  fi

  # `dev` naming HEAD is legitimate on a re-run - the first attempt moved it
  # here - and `docs/releasing.md` documents that. On a *first* attempt it means
  # the tag was moved within this run, so the body is being written after the
  # release was published.
  #
  # A warning rather than a refusal, because a refusal is the one thing that
  # does not work here: it prompts the re-run that makes the attempt number 2,
  # which skips this check and publishes "this is a rebuild" - the very page the
  # check exists to prevent, now green. A warning cannot be cleared by
  # re-running, and the whole changelog under it is honest.
  #
  # `10#` because bash reads a leading zero as octal: `01` is 1 either way, but
  # `08` is not valid octal and would abort rather than answer. Same trap
  # `derive_version_test.sh` pins for the version components.
  if [[ "$candidate" == "$head_sha" ]] && (( 10#$GITHUB_RUN_ATTEMPT == 1 )); then
    echo "::warning::The dev tag already names HEAD on the first attempt of this run, so this page carries the whole changelog. If this is not a re-run, the release is being published before its body is written." >&2
    return
  fi

  # Not "it had no changelog": `check_changelog.sh` runs on every push, so a
  # commit on main without one is an anomaly. Give up the baseline rather than
  # declare the whole accumulated file new under a "New in this build" heading,
  # which is the one degraded shape that reads as a confident lie.
  if ! git -C "$repo_root" show "$candidate:CHANGELOG.md" >"$tmp/was" 2>"$tmp/err"; then
    echo "::warning::Could not read CHANGELOG.md at $candidate, so this page carries the whole changelog instead of what is new. git said: $(git_said)" >&2
    return
  fi

  # A changelog diff is only defined between two revisions of one cycle, and the
  # `- Version:` line is the only record of which cycle a revision belongs to
  # *inside the file being compared* - pubspec's `version:` is the authority
  # (§2) but says nothing about an old revision of this file.
  # `open_next_cycle.sh` writes the line in the same commit as the reset, and
  # `check_changelog.sh` guarantees on every push that there is exactly one and
  # that it agrees with pubspec.
  #
  # The precondition is load-bearing because nothing clears the `dev` tag when a
  # release is cut, so the first dev build of a new cycle has a baseline from
  # the previous one. Without it those notes would all read as already-shipped,
  # and a new note whose wording repeats a shipped one would be dropped for
  # matching it.
  was_version="$(version_line "$tmp/was")"
  now_version="$(version_line "$changelog")"
  if [[ -z "$was_version" || -z "$now_version" ]]; then
    # With a line missing there is no cycle to compare, so "every note is new"
    # is a guess - and it is the guess that publishes shipped work under a "New
    # in this build" heading.
    echo "::warning::A changelog revision carries no '- Version:' line, so the cycle cannot be established and this page carries the whole changelog instead of what is new." >&2
    return
  fi

  if [[ "$was_version" == "$now_version" ]]; then
    notes "$tmp/was" >"$tmp/old"
  else
    # A cycle boundary. `$tmp/old` stays empty, which is what makes every note
    # in the current file count as new - the same state a freshly reset
    # changelog produces, and not a special case past this point.
    echo "::notice::The previous dev build was in another cycle ($was_version), so every note in the file counts as new." >&2
  fi
  base="$candidate"
}

resolve_baseline

if [[ -z "$base" ]]; then
  whole_body
  printf '\n[All changes](%s)\n' "$link"
  echo "Release body: no baseline, so the whole changelog." >&2
  exit 0
fi

# Comparing the two files' bullets, rather than reading `git diff`'s `+` lines:
# a bullet moved between the two sections is not new, and a diff calls it added.
# A reworded bullet does count as new, which is right - it is text nobody has
# read on a release page yet.
notes "$changelog" >"$tmp/new"

# `grep -v -f` with an empty pattern file matches nothing, so every line
# survives - which is the answer wanted at a cycle boundary and on the first
# build after one. Exit 1 is "nothing new", a normal build; `|| true` would
# swallow exit 2 with it, and grep prints matches *before* failing, so a read
# error would otherwise publish a truncated list under a count that agreed with
# it.
added="$(grep -Fxv -f "$tmp/old" "$tmp/new")" || (( $? == 1 ))

printf '%s\n\n## New in this build\n' "$summary"
if [[ -n "$added" ]]; then
  printf '%s\n' "$added"
  echo "Release body: $(wc -l <<<"$added" | tr -d '[:space:]') new note(s) since $base." >&2
else
  # Most pushes add no bullet, deliberately - `check_changelog.sh`'s own header
  # says a gate demanding one would be wrong more often than right. So this is
  # not a degraded case, it is the usual one, and the commits are what there is
  # to say about the build.
  total="$(git -C "$repo_root" rev-list --count "$base..HEAD")"
  if (( total )); then
    printf 'Nothing was added to the changelog. Commits since the previous dev build:\n'
    # `--max-count` is applied before `--reverse`, so this is the newest ten
    # printed oldest-first and the ones left out are the *oldest*. Hence the
    # count above the list and "earlier" in it: under the list it reads as a
    # claim that newer commits were trimmed.
    if (( total > 10 )); then
      printf -- '- ...and %s earlier commits\n' "$(( total - 10 ))"
    fi
    git -C "$repo_root" log --format='- %s' --max-count=10 --reverse "$base..HEAD"
  else
    # The publish job re-run on a commit that was already built, which is
    # allowed and documented (`docs/releasing.md`) - the first attempt moved
    # `dev` here, so this build's baseline is itself. An empty list under
    # "Commits since" would be the wrong thing to publish.
    printf 'Nothing new: this is a rebuild of the commit the previous dev build came from.\n'
  fi
  echo "Release body: no new notes, so $total commit subject(s) since $base." >&2
fi
printf '\n[All changes](%s)\n' "$link"
