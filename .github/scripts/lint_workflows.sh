#!/usr/bin/env bash
# Runs actionlint over the workflows and the composite action.
#
#   lint_workflows.sh
#
# Workflow mistakes are otherwise only found by running the workflow, and the
# release workflow publishes on a tag. Two that reached this repository would
# have been caught here: a `secrets` reference in a step-level `if:`, which is a
# template-parse failure that kills the whole file, and an input that the action
# being called does not declare, which GitHub ignores silently.
#
# The binary is pinned and its checksum verified, because this runs in the same
# repository whose release job holds the signing key. See the issue on Gradle
# distribution verification for the same argument applied to the build.
set -Eeuo pipefail

VERSION="1.7.12"
SHA256="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
ARCHIVE="actionlint_${VERSION}_linux_amd64.tar.gz"
URL="https://github.com/rhysd/actionlint/releases/download/v${VERSION}/${ARCHIVE}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "::error::This script fetches the Linux build; run it on a Linux runner." >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "$URL" -o "$tmp/$ARCHIVE"
echo "$SHA256  $tmp/$ARCHIVE" | sha256sum -c - >/dev/null \
  || { echo "::error::actionlint checksum mismatch; refusing to run it." >&2; exit 1; }

tar -xzf "$tmp/$ARCHIVE" -C "$tmp" actionlint
"$tmp/actionlint" -version

# shellcheck is not installed on the runner by default; actionlint skips it and
# says so. Workflow-level checks are the point here.
"$tmp/actionlint" -color
