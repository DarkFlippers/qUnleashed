#!/usr/bin/env bash
# Turns a trigger into a build identity, so no two jobs can disagree about what
# a build is. ADR 0014 §4.
#
#   derive_version.sh                    # write to $GITHUB_ENV and $GITHUB_OUTPUT
#   derive_version.sh -- <tag>           # ... for an explicit tag
#   derive_version.sh --print [--] <tag> # write "<name> <code>" to stdout instead
#   derive_version.sh --print-channel …  # write "dev" or "release" instead
#
# **The version comes from `pubspec.yaml`, not from the tag** (§2). It used to
# come from the tag, and that made a dev build impossible: a push to `main` has
# no tag, so there was nothing to read and this script refused to run. Pubspec
# on `main` holds the version being built *toward*, every dev build in a cycle
# is named it, and they are told apart by the build number and the commit.
#
# The tag is still read, for two things. It picks the channel, and it is checked
# against pubspec - see the two guards below. `QU_PUBSPEC` overrides which file
# is read, which is how the tests feed a version without rewriting the repo's.
#
# Pass a caller-supplied tag after `--`. The release workflow does, because on a
# tag push `${{ inputs.tag }}` expands to an empty argument and on a dispatch it
# is whatever an operator typed - without the separator, a tag of `--print`
# would take the print arm, write nothing to $GITHUB_ENV and exit 0, and the
# build would go out with no dart-defines at all.
#
# With no argument the ref is used, but only when it names a tag
# (`GITHUB_REF_TYPE`); a branch is a dev build and has no tag to check. --print
# exists for the tests; jobs consume the values through the environment or the
# step output, so nothing in the workflow depends on this script's stdout.
#
# QU_BUILD_SERVER_URL and QU_BUILD_SERVER_KEY are folded into the Flutter build
# arguments only when both are set, since a URL without a key authenticates
# nothing. QU_CARTO_KEY is independent.
#
# The three commits are resolved from git rather than passed in, so that one
# step produces them for every build job instead of each job repeating a
# `git rev-parse` - ADR 0014 §4 asks this script to be the one place a trigger
# becomes a build identity. Each is overridable by an environment variable of
# the same name, which is how the tests pin them; set one to the empty string
# and that define is left out.
#
# **Every job that runs this needs `fetch-depth: 0`.** The build number counts
# commits (§6) and the published-version guard reads every tag, and a default
# checkout has neither. The script refuses to guess rather than produce a
# plausible wrong number - see the shallow check below.
set -Eeuo pipefail

print_only=0
print_channel=0
case "${1:-}" in
  --print) print_only=1; shift ;;
  --print-channel) print_channel=1; shift ;;
  --) shift ;;
  --*) echo "Usage: $0 [--print|--print-channel] [--] [tag]" >&2; exit 2 ;;
esac
if [[ "${1:-}" == "--" ]]; then shift; fi

# An explicit argument wins; otherwise the ref, but only when it is a tag. A
# branch name is not a tag that failed to parse, it is a dev build, and the
# difference is the whole of what makes §2 work.
tag="${1:-}"
if [[ -z "$tag" && "${GITHUB_REF_TYPE:-}" == tag ]]; then
  tag="${GITHUB_REF_NAME:-}"
fi

# --- the channel, decided by the trigger alone -------------------------------
#
# Before the version, and before anything reads pubspec, because it depends on
# nothing else: `--print-channel` is a property of how the build was started.
# The publish job asks for exactly that and nothing more.
#
# No tag means a branch build, which is a dev build by definition: a release is
# something somebody cuts, and cutting it makes a tag. A tag is a release.
#
# `QU_CHANNEL` overrides the inference, for a caller that knows better than the
# trigger. Nothing in CI sets it today; the tests pin it, and the validation
# below is what stops a typo shipping as a channel.
#
# Two values here and never `local`: the script only runs in CI, and `local` is
# what the app reads when nothing passed a define at all.
#
# `dev-*` is refused rather than mapped to the dev channel, which is what §1's
# interim rule turns into once a push to `main` builds. Seven of this
# repository's 56 tags are `dev-*` - it was how a dev build was made before
# `main` built on its own - and `dev` is now the name of the single rolling
# prerelease (§7). Mapping the prefix would make those two meanings collide,
# silently and expensively: a pushed `dev-0.15.0` would resolve to the dev
# channel, the publish job would delete and recreate the rolling `dev` release,
# the pushed tag would get no release and no assets, the binaries would call
# themselves a dev build, and the build number would take slot 0 - the same
# number as the dev build already made from that commit, which is the collision
# §6's slot exists to prevent. Every job would have succeeded.
#
# Unconditional, before QU_CHANNEL is consulted: an override that let the tag
# through would still hand the publish job a tag whose prefix collides with the
# rolling prerelease's name. The rolling tag itself is `dev`, not
# `dev-something`, so nothing legitimate is caught by this.
if [[ "$tag" == dev-* ]]; then
  echo "::error::The tag $tag uses the dev- prefix, which is no longer a channel: a dev build comes from a push to main, and 'dev' is the rolling prerelease. Tag the version itself." >&2
  exit 1
fi

channel="${QU_CHANNEL:-}"
if [[ -z "$channel" ]]; then
  if [[ -z "$tag" ]]; then channel=dev; else channel=release; fi
fi
if [[ "$channel" != dev && "$channel" != release ]]; then
  echo "::error::QU_CHANNEL must be dev or release, not '$channel'." >&2
  exit 1
fi

if (( print_channel )); then
  printf '%s\n' "$channel"
  exit 0
fi

# The repository being built, found from this script rather than from the
# caller's cwd. Every `git` read below goes through it: a step with a
# `working-directory:`, or a checkout at a non-default `path:`, otherwise makes
# them answer about the wrong tree or not at all.
#
# QU_REPO_ROOT is how the tests point the tag and commit-count reads at a
# fixture repository of their own instead of this one's history.
repo_root="${QU_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
pubspec="${QU_PUBSPEC:-$repo_root/pubspec.yaml}"
if [[ ! -f "$pubspec" ]]; then
  echo "::error::No pubspec.yaml at $pubspec." >&2
  exit 1
fi

# The name only. The build number is a counter now (§6) and does not live in
# pubspec at all, so the `[^+]` is here to ignore a stale `+` left in the file
# rather than to skip a number worth reading.
# Quitting on the first match rather than `| head -n 1`: under `pipefail`, head
# closing the pipe early makes sed die of SIGPIPE and the whole script exit 141
# with nothing printed. Not reachable at pubspec's size, but it is a silent exit
# waiting for a longer file.
#
# Two things about the shape, and the second one cost a dev build. The quit
# has to hang off an address, because a block cannot attach to an `s`:
# `s/…/…/{p;q}` is not valid sed. And the closing `}` needs a newline before
# it, which POSIX states outright - "the <right-brace> shall be preceded by a
# <newline> or <semicolon>" - and which BSD sed, the sed on the macOS runners,
# enforces: `;q}` is `extra characters at the end of q command` there, because
# `q` ends at a `;` or a newline and `}` is neither. GNU sed accepts the bare
# `;q}`, so the non-conforming form passed every job that is not macOS.
pubspec_version="$(
  sed -nE '/^version:/{
    s/^version:[[:space:]]*([^+[:space:]]+).*$/\1/p
    q
  }' "$pubspec"
)"
if [[ ! "$pubspec_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "::error::pubspec.yaml version must be major.minor.patch, not '$pubspec_version'." >&2
  exit 1
fi

# Normalized through base 10 at parse time so the name and the code see the same
# number: a zero-padded component cannot be read as octal (`0.010.0` is 10, not
# 8), and the name cannot drift from the code the way it used to (`0.08.09`
# produced the name 0.08.09 against the code 8009).
major=$((10#${BASH_REMATCH[1]}))
minor=$((10#${BASH_REMATCH[2]}))
patch=$((10#${BASH_REMATCH[3]}))
version_name="${major}.${minor}.${patch}"

if (( major == 0 && minor == 0 && patch == 0 )); then
  echo "::error::pubspec.yaml version must be greater than 0.0.0." >&2
  exit 1
fi

# --- guard one: a release tag has to agree with pubspec ----------------------
#
# Satisfied by construction under §2, because pubspec already holds the version
# being released - which is the point of holding the next one rather than the
# last. It would have failed the release of 2026-10-01, when `dev-0.13.0`
# pointed at a commit whose pubspec still said 0.12.1, because the old
# sync-version wrote the version *after* publishing.
# Anchored, which 0014's Consequences asks for. Unanchored,
# `beta-0.14.0-rc1` matched `0.14.0` and built as it - a release candidate
# claiming the identity of the release, published under its name, with the
# published-version guard waving it through because the tag it matched was
# its own.
if [[ -n "$tag" ]]; then
  if [[ ! "$tag" =~ ^([A-Za-z][A-Za-z0-9]*-)?v?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "::error::Tag must be a semantic version with an optional prefix - 0.6.1, v0.6.1, alpha-0.6.1 - and nothing after the patch number. Got '$tag'." >&2
    exit 1
  fi
  # Group 1 is the optional prefix, so the components start at 2.
  tag_version="$((10#${BASH_REMATCH[2]})).$((10#${BASH_REMATCH[3]})).$((10#${BASH_REMATCH[4]}))"
  if [[ "$tag_version" != "$version_name" ]]; then
    echo "::error::Tag $tag names $tag_version but pubspec.yaml says $version_name. Bump pubspec in a commit of its own, or tag the version it holds." >&2
    exit 1
  fi
fi

# --- guard two: a version that has gone out cannot be built again ------------
#
# This is what replaces the automatic bump. Choosing patch against minor against
# major is a decision, so pubspec moves in a deliberate commit and CI never
# picks a digit; what CI can settle is whether the digit was moved at all.
#
# Without this, releasing 0.15.0 and forgetting to bump means the next dev build
# is named 0.15.0 too - and TestFlight refuses it, because that short version has
# been released. Days later, far from the commit, reported as a store problem.
#
# "Has gone out" means a tag names it. Building that tag is the one case where
# the match is expected, so it is allowed; anything else is the hole above. The
# `[^0-9]` boundaries are what keep 0.10.1 from being blocked by an existing
# beta-0.10.10 - a false positive here hard-blocks every build of a legitimate
# new version, with an error telling the operator to bump a pubspec they just
# bumped.
#
# The read has to be able to fail, and what it actually catches is narrower
# than it looks: `git tag --list` exits 0 with empty output when a repository
# simply has no tags, so "no tag names this version" and "there are no tags"
# are already the same answer here. What this turns from silence into a failure
# is the case where the path is not a repository at all. The shallow-checkout
# hole is closed separately, further down, and after this guard runs. There is
# nothing to fall back to either way, so it is fatal.
#
# There is no way to switch this off. An earlier draft had one, for tests that
# were about something else, and a skip-the-guard lever in shipped CI code is
# its own hazard - anything exporting it turns off the check that replaced the
# automatic version bump, with no signal. The tests point QU_REPO_ROOT at a
# fixture repository instead, so the guard always runs.
if ! published_tags="$(git -C "$repo_root" tag --list)"; then
  echo "::error::Could not read the tags, so the published-version guard cannot run. Use fetch-depth: 0." >&2
  exit 1
fi
while IFS= read -r published; do
  [[ -z "$published" ]] && continue
  [[ "$published" == "$tag" ]] && continue
  if [[ "$published" =~ (^|[^0-9])${version_name//./\\.}([^0-9]|$) ]]; then
    echo "::error::Version $version_name has already been published as $published. Open the next cycle by bumping pubspec.yaml." >&2
    exit 1
  fi
done <<< "$published_tags"

# --- the build number is a counter, and means nothing else -------------------
#
#   100000 + <commits on main> × 10 + slot      (§6)
#
# The name and the number are decoupled, because §2 makes every dev build in a
# cycle share one name - so the name carries no ordering at all and the number
# has to carry every bit of it. The old formula derived the number *from* the
# name (major × 1e6 + minor × 1e3 + patch), which hands every dev build in a
# cycle the same number: it fails on the second build of a cycle rather than
# after a thousand commits.
#
# `100000 +` clears every number ever shipped in one step - the highest is
# 14001 - so nothing has to remember what the high-water mark was. `× 10`
# leaves ten slots per commit, which is what lets two builds of one commit
# differ; a release is frequently tagged at a commit a dev build already came
# from. The ceiling Android imposes is 2 100 000 000, which is 210 million
# commits away.
commit_count="${QU_COMMIT_COUNT:-}"
if [[ -z "$commit_count" ]]; then
  # A shallow checkout answers 1, which is not an error anything else would
  # notice: it produces a plausible number that collides with every other
  # shallow build. Fail instead - `fetch-depth: 0` is the fix, and §6 says so.
  if [[ "$(git -C "$repo_root" rev-parse --is-shallow-repository 2>/dev/null || echo true)" != false ]]; then
    echo "::error::This checkout is shallow or not a repository, so the commit count would be wrong. Use fetch-depth: 0." >&2
    exit 1
  fi
  # HEAD and not an explicit `main`: every build comes off main, so in CI they
  # are the same commit, and counting HEAD is what makes the number
  # recomputable from any checkout - any commit can state the number it would
  # build as, which is the property §6 asks for.
  commit_count="$(git -C "$repo_root" rev-list --count HEAD)"
fi
if [[ ! "$commit_count" =~ ^[0-9]+$ ]] || (( commit_count == 0 )); then
  echo "::error::Commit count must be a positive integer, not '$commit_count'." >&2
  exit 1
fi

# A dev build takes slot 0 and a re-run collides with itself, deliberately: it
# is disposable, the rolling prerelease is overwritten anyway, and the fix for
# wanting a new one is another commit. A release takes the attempt number, so
# re-running a failed release job produces a number the store has not already
# refused.
if [[ "$channel" == dev ]]; then
  slot=0
else
  slot="${GITHUB_RUN_ATTEMPT:-1}"
fi
if [[ ! "$slot" =~ ^[0-9]$ ]]; then
  echo "::error::Build slot must be a single digit, not '$slot'. A tenth attempt needs a new commit." >&2
  exit 1
fi

version_code=$((100000 + commit_count * 10 + slot))
if (( version_code > 2100000000 )); then
  echo "::error::Build number $version_code is above the 2100000000 Android allows." >&2
  exit 1
fi

if (( print_only )); then
  printf '%s %s\n' "$version_name" "$version_code"
  exit 0
fi

if [[ -z "${GITHUB_ENV:-}" ]]; then
  echo "::error::GITHUB_ENV is unset. Use --print outside a workflow." >&2
  exit 1
fi

# Resolved from the checkout unless the caller said otherwise. `-` and not `:-`
# on purpose: an unset variable means "work it out", an empty one means "leave
# it out", and the tests need the second to assert the shape without a commit.
#
# Resolved against the repository root rather than the caller's cwd, like
# $pubspec above. Relative paths looked right and were not: a step with a
# `working-directory:`, or a checkout at a non-default `path:`, made all three
# `git -C` calls fail into empty strings, and the build then shipped with no
# submodule commits and nothing said about it.
commit="${QU_COMMIT-$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)}"
commit_flipperlib="${QU_COMMIT_FLIPPERLIB-$(
  git -C "$repo_root/lib/modules/flipperlib" rev-parse HEAD 2>/dev/null || true
)}"
commit_dartufbt="${QU_COMMIT_DARTUFBT-$(
  git -C "$repo_root/lib/modules/dartufbt" rev-parse HEAD 2>/dev/null || true
)}"

# A build that cannot name its commit is useless to the thing this ADR is for,
# and for a release it is worse than useless - §6's counter orders builds but
# only the commit ties a store binary to a tree. So a release fails and a dev
# build warns.
if [[ -z "$commit" ]]; then
  if [[ "$channel" == release ]]; then
    echo "::error::No commit resolved, so a release would not say which commit it is." >&2
    exit 1
  fi
  echo "::warning::No commit resolved. The build will not say which commit it is." >&2
fi

# A submodule that is checked out but unreadable is a different thing from one
# the job did not ask for, and only the first is a problem worth naming.
for module in flipperlib dartufbt; do
  resolved="commit_$module"
  if [[ -z "${!resolved}" && -d "$repo_root/lib/modules/$module/.git" ]]; then
    echo "::warning::lib/modules/$module is checked out but its commit could not be read." >&2
  fi
done

# The build scripts re-split QUNLEASHED_FLUTTER_BUILD_ARGS on whitespace, so a
# secret carrying a newline or a space would silently drop every argument after
# it - or add one. Failing here beats shipping a release missing a key. This
# guards one producer of a string transport that cannot carry whitespace at all;
# see the issue on replacing that transport.
for name in QU_BUILD_SERVER_URL QU_BUILD_SERVER_KEY QU_CARTO_KEY \
            QU_SENTRY_DSN QU_COMMIT QU_COMMIT_FLIPPERLIB \
            QU_COMMIT_DARTUFBT QU_CHANNEL; do
  if [[ "${!name:-}" =~ [[:space:]] ]]; then
    echo "::error::$name contains whitespace, which would corrupt the build arguments." >&2
    exit 1
  fi
done

args=(--build-name="$version_name" --build-number="$version_code")
args+=(--dart-define=QU_CHANNEL="$channel")
if [[ -n "${QU_BUILD_SERVER_URL:-}" && -n "${QU_BUILD_SERVER_KEY:-}" ]]; then
  args+=(--dart-define=QU_BUILD_SERVER_URL="$QU_BUILD_SERVER_URL")
  args+=(--dart-define=QU_BUILD_SERVER_KEY="$QU_BUILD_SERVER_KEY")
fi
if [[ -n "${QU_CARTO_KEY:-}" ]]; then
  args+=(--dart-define=QU_CARTO_KEY="$QU_CARTO_KEY")
fi
# A DSN identifies a project and authorises nothing but writing to it, so it is
# a define like the rest. SENTRY_AUTH_TOKEN is not and must never be: a define
# is compiled into the binary. The upload step reads that one from the
# environment. ADR 0013.
#
# Say when it is missing, on the same grounds as the commit above: a misnamed
# or rotated secret expands to the empty string, the define is dropped, and the
# only symptom is one line in the shipped app's own log, on a user's machine.
# That is how `secrets.QU_SENTRY_DSN` - a secret that never existed - shipped
# five green builds that reported nothing.
#
# A warning and not an error, because a fork has no secrets and has to be able
# to build - the same trade the symbol upload makes. Unconditional, because
# `channel` is `dev` or `release` by the check above and nothing else reaches
# here: this script is the CI path, and a `local` build is the one that never
# runs it.
if [[ -n "${QU_SENTRY_DSN:-}" ]]; then
  args+=(--dart-define=QU_SENTRY_DSN="$QU_SENTRY_DSN")
else
  echo "::warning::No DSN, so this $channel build will report nothing. Check the SENTRY_DSN secret." >&2
fi
if [[ -n "$commit" ]]; then
  args+=(--dart-define=QU_COMMIT="$commit")
fi
if [[ -n "$commit_flipperlib" ]]; then
  args+=(--dart-define=QU_COMMIT_FLIPPERLIB="$commit_flipperlib")
fi
if [[ -n "$commit_dartufbt" ]]; then
  args+=(--dart-define=QU_COMMIT_DARTUFBT="$commit_dartufbt")
fi

# What the asset filenames are named after. Its own variable rather than an
# overload of QUNLEASHED_VERSION_NAME, which stays numeric - the pubspec
# fallback in each build script expects a numeric version, so anyone adding a
# consumer would assume one.
#
# It exists because without the suffix a dev build and the release of the same
# cycle produce byte-identical filenames - `qunleashed_0.15.0_android_universal
# .apk` both - and identical entries in two different SHA256SUMS, so a
# sideloaded dev APK is indistinguishable from the shipped version once it is
# on disk. §2 keeps the suffix wherever a person reads the version, and a
# downloaded filename was the one place left out. The build number goes in too,
# so two dev builds of one cycle differ.
#
# Dots and dashes only, never a `+`: each build script's fallback matches
# `[0-9A-Za-z._-]+` and android.sh truncates at the first `+`, so a plus would
# read as a separator rather than as part of the name.
if [[ "$channel" == dev ]]; then
  asset_version="$version_name-dev.$version_code"
else
  asset_version="$version_name"
fi

# What Sentry calls this build. 0014 §5, and the one string the upload step
# and the app itself both have to produce: the app formats it in
# `BuildStamp.sentryRelease`, and if the two ever disagree the symbols land
# under a release name no event carries.
#
# `SENTRY_RELEASE` and not `QUNLEASHED_SENTRY_RELEASE`, which is the only one of
# these that breaks the prefix. It is the name `sentry_dart_plugin` and
# `sentry-cli` both read from the environment, and in the plugin it outranks
# both its argument and the pubspec - so writing it to GITHUB_ENV is the whole
# wiring, with no flag on the upload step to drift from this line. The prefix
# exists to mark what this script owns; this value is owned by the tool that
# consumes it.
#
# The suffix follows §2 rather than the asset name's: a `+` is correct here -
# Sentry's release is a free-form string - where the asset name cannot carry
# one. So this is `qunleashed@0.15.0-dev+108080` against the asset's
# `0.15.0-dev.108080`, deliberately, and not a second spelling of the same
# thing.
if [[ "$channel" == release ]]; then
  sentry_release="qunleashed@$version_name+$version_code"
else
  sentry_release="qunleashed@$version_name-$channel+$version_code"
fi

{
  echo "QUNLEASHED_VERSION_NAME=$version_name"
  echo "QUNLEASHED_ASSET_VERSION=$asset_version"
  echo "QUNLEASHED_VERSION_CODE=$version_code"
  echo "QUNLEASHED_CHANNEL=$channel"
  echo "SENTRY_RELEASE=$sentry_release"
  echo "QUNLEASHED_FLUTTER_BUILD_ARGS=${args[*]}"
} >> "$GITHUB_ENV"

# Also published as a step output so a later job can reuse the version without
# re-deriving it from its own checkout of this script.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version_name=$version_name"
    echo "version_code=$version_code"
    echo "channel=$channel"
    echo "sentry_release=$sentry_release"
  } >> "$GITHUB_OUTPUT"
fi

echo "Version name: $version_name" >&2
echo "Version code: $version_code" >&2
echo "Channel: $channel" >&2
echo "Commit: ${commit:-<none>}" >&2
