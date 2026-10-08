#!/usr/bin/env bash
# Derives the app version from the release tag, so no two jobs can disagree
# about what a tag means.
#
#   derive_version.sh                    # write to $GITHUB_ENV and $GITHUB_OUTPUT
#   derive_version.sh -- <tag>           # ... for an explicit tag
#   derive_version.sh --print [--] <tag> # write "<name> <code>" to stdout instead
#   derive_version.sh --print-channel …  # write "dev" or "release" instead
#
# Pass a caller-supplied tag after `--`. The release workflow does, because on a
# tag push `${{ inputs.tag }}` expands to an empty argument and on a dispatch it
# is whatever an operator typed - without the separator, a tag of `--print`
# would take the print arm, write nothing to $GITHUB_ENV and exit 0, and the
# build would silently fall back to the pubspec version with no dart-defines.
#
# An empty or absent tag falls back to $GITHUB_REF_NAME. --print exists for the
# tests; jobs consume the values through the environment or the step output, so
# nothing in the workflow depends on this script's stdout.
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
# and that define is left out. A shallow checkout still resolves HEAD, so no
# job needs `fetch-depth: 0` for this (§6's build number is what will).
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

tag="${1:-${GITHUB_REF_NAME:-}}"
if [[ -z "$tag" ]]; then
  echo "::error::No tag given and GITHUB_REF_NAME is unset." >&2
  exit 1
fi

if [[ ! "$tag" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  echo "::error::Tag must contain a semantic version like 0.6.1, alpha-0.6.1, or beta-0.6.1." >&2
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
version_code=$((major * 1000000 + minor * 1000 + patch))

if (( version_code <= 0 )); then
  echo "::error::Derived version code must be greater than zero." >&2
  exit 1
fi

# Which of the two published channels this build is, decided by the trigger.
#
# `QU_CHANNEL` wins when the caller sets it, which is how the workflow that
# builds a push to `main` says `dev` without there being a tag to read. Until
# that workflow exists the tag prefix decides, which is ADR 0014 §1's interim
# rule and the same test the publish job used to make for itself.
#
# Two values here and never `local`: the script only runs in CI, and `local` is
# what the app reads when nothing passed a define at all.
channel="${QU_CHANNEL:-}"
if [[ -z "$channel" ]]; then
  if [[ "$tag" == dev-* ]]; then channel=dev; else channel=release; fi
fi
if [[ "$channel" != dev && "$channel" != release ]]; then
  echo "::error::QU_CHANNEL must be dev or release, not '$channel'." >&2
  exit 1
fi

if (( print_channel )); then
  printf '%s\n' "$channel"
  exit 0
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
commit="${QU_COMMIT-$(git rev-parse HEAD 2>/dev/null || true)}"
commit_flipperlib="${QU_COMMIT_FLIPPERLIB-$(
  git -C lib/modules/flipperlib rev-parse HEAD 2>/dev/null || true
)}"
commit_dartufbt="${QU_COMMIT_DARTUFBT-$(
  git -C lib/modules/dartufbt rev-parse HEAD 2>/dev/null || true
)}"

# A checkout with no commit to name is worth saying out loud rather than
# shipping a build that cannot say what it is. Not fatal: a submodule a given
# job does not touch is absent rather than wrong.
if [[ -z "$commit" ]]; then
  echo "::warning::No commit resolved. The build will not say which commit it is." >&2
fi

# The build scripts re-split QUNLEASHED_FLUTTER_BUILD_ARGS on whitespace, so a
# secret carrying a newline or a space would silently drop every argument after
# it - or add one. Failing here beats shipping a release missing a key. This
# guards one producer of a string transport that cannot carry whitespace at all;
# see the issue on replacing that transport.
for name in QU_BUILD_SERVER_URL QU_BUILD_SERVER_KEY QU_CARTO_KEY \
            QU_COMMIT QU_COMMIT_FLIPPERLIB QU_COMMIT_DARTUFBT QU_CHANNEL; do
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
if [[ -n "$commit" ]]; then
  args+=(--dart-define=QU_COMMIT="$commit")
fi
if [[ -n "$commit_flipperlib" ]]; then
  args+=(--dart-define=QU_COMMIT_FLIPPERLIB="$commit_flipperlib")
fi
if [[ -n "$commit_dartufbt" ]]; then
  args+=(--dart-define=QU_COMMIT_DARTUFBT="$commit_dartufbt")
fi

{
  echo "QUNLEASHED_VERSION_NAME=$version_name"
  echo "QUNLEASHED_VERSION_CODE=$version_code"
  echo "QUNLEASHED_CHANNEL=$channel"
  echo "QUNLEASHED_FLUTTER_BUILD_ARGS=${args[*]}"
} >> "$GITHUB_ENV"

# Also published as a step output so a later job can reuse the version without
# re-deriving it from its own checkout of this script.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version_name=$version_name"
    echo "version_code=$version_code"
    echo "channel=$channel"
  } >> "$GITHUB_OUTPUT"
fi

echo "Version name: $version_name" >&2
echo "Version code: $version_code" >&2
echo "Channel: $channel" >&2
echo "Commit: ${commit:-<none>}" >&2
