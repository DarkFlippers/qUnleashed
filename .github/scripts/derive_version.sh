#!/usr/bin/env bash
# Derives the app version from the release tag, so the build jobs and the
# pubspec sync job cannot disagree about what a tag means.
#
#   derive_version.sh                 # append the values to $GITHUB_ENV
#   derive_version.sh --print         # print "<name> <code>" to stdout instead
#   derive_version.sh --print 0.13.0  # ... for an explicit tag, for tests
#
# Without an explicit tag the value comes from $GITHUB_REF_NAME.
#
# In the default mode QU_BUILD_SERVER_URL, QU_BUILD_SERVER_KEY and QU_CARTO_KEY
# are read from the environment and folded into the Flutter build arguments when
# set. A build without them still succeeds, with that feature disabled at
# runtime, so a fork can cut a build it can actually use.
set -Eeuo pipefail

print_only=0
if [[ "${1:-}" == "--print" ]]; then
  print_only=1
  shift
fi

tag="${1:-${GITHUB_REF_NAME:-}}"
if [[ -z "$tag" ]]; then
  echo "::error::No tag given and GITHUB_REF_NAME is unset." >&2
  exit 1
fi

if [[ ! "$tag" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  echo "::error::Tag must contain a semantic version like 0.6.1, dev-0.6.1, or beta-0.6.1." >&2
  exit 1
fi

# Forced base 10 once, so a zero-padded component cannot be read as octal and
# cannot leave the name and the code disagreeing (`0.08.09` -> 0.8.9 / 8009).
major=$((10#${BASH_REMATCH[1]}))
minor=$((10#${BASH_REMATCH[2]}))
patch=$((10#${BASH_REMATCH[3]}))
version_name="${major}.${minor}.${patch}"
version_code=$((major * 1000000 + minor * 1000 + patch))

if (( version_code <= 0 )); then
  echo "::error::Derived version code must be greater than zero." >&2
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

build_args="--build-name=$version_name --build-number=$version_code"
build_args="$build_args --dart-define=QUNLEASHED_RELEASE_TAG=$tag"
if [[ -n "${QU_BUILD_SERVER_URL:-}" && -n "${QU_BUILD_SERVER_KEY:-}" ]]; then
  build_args="$build_args --dart-define=QU_BUILD_SERVER_URL=$QU_BUILD_SERVER_URL"
  build_args="$build_args --dart-define=QU_BUILD_SERVER_KEY=$QU_BUILD_SERVER_KEY"
fi
if [[ -n "${QU_CARTO_KEY:-}" ]]; then
  build_args="$build_args --dart-define=QU_CARTO_KEY=$QU_CARTO_KEY"
fi

{
  echo "QUNLEASHED_VERSION_NAME=$version_name"
  echo "QUNLEASHED_VERSION_CODE=$version_code"
  echo "QUNLEASHED_FLUTTER_BUILD_ARGS=$build_args"
} >> "$GITHUB_ENV"

echo "Version name: $version_name"
echo "Version code: $version_code"
