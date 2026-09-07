#!/usr/bin/env bash
# Derives the app version from the release tag, so the build jobs and the
# pubspec sync job cannot disagree about what a tag means.
#
#   derive_version.sh                 # append the values to $GITHUB_ENV
#   derive_version.sh --print         # write "<name> <code>" to stdout instead
#   derive_version.sh --print 0.13.0  # ... for an explicit tag, for tests
#
# Without an explicit tag the value comes from $GITHUB_REF_NAME.
#
# --print is a production contract, not a test affordance: the pubspec sync job
# reads its stdout with `read`, which cannot tell a diagnostic line from the
# answer. Everything except the single result line must go to stderr.
#
# Caveat on provenance: the sync job checks out the default branch, so it runs
# main's copy of this script while the build jobs run the tag's. They agree as
# long as this file has not changed between the tagged commit and the release.
#
# QU_BUILD_SERVER_URL and QU_BUILD_SERVER_KEY are folded into the Flutter build
# arguments only when *both* are set, since a URL without a key authenticates
# nothing. QU_CARTO_KEY is independent. Leaving QU_CARTO_KEY unset ships a build
# whose basemap falls back to the key the user supplies; leaving the build-server
# pair unset does not disable that feature, because the app carries a default
# address (see remote_build_service.dart) - it only makes server builds fail.
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

if (( print_only )); then
  printf '%s %s\n' "$version_name" "$version_code"
  exit 0
fi

if [[ -z "${GITHUB_ENV:-}" ]]; then
  echo "::error::GITHUB_ENV is unset. Use --print outside a workflow." >&2
  exit 1
fi

# The build scripts re-split QUNLEASHED_FLUTTER_BUILD_ARGS on whitespace, so a
# secret carrying a newline or a space would silently drop every argument after
# it - or add one. Fail here instead of shipping a release missing a key.
for name in QU_BUILD_SERVER_URL QU_BUILD_SERVER_KEY QU_CARTO_KEY; do
  value="${!name:-}"
  if [[ -n "$value" && "$value" =~ [[:space:]] ]]; then
    echo "::error::$name contains whitespace, which would corrupt the build arguments." >&2
    exit 1
  fi
done

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

echo "Version name: $version_name" >&2
echo "Version code: $version_code" >&2
