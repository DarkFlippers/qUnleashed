#!/usr/bin/env bash
# Writes SHA256SUMS over the files in a directory, so a downloaded asset can be
# checked against the digest the release was built with. That catches a
# corrupted, truncated or mirrored download. The file is not signed and is
# served from the same release, so it is not evidence about the release itself.
#
#   checksums.sh [directory]   # default: dist
#
# Names are stored bare rather than as paths, so verification runs from whatever
# directory somebody downloaded into. Nobody downloads every asset, so the
# command has to tolerate the ones they skipped:
#
#   sha256sum --ignore-missing -c SHA256SUMS   # Linux
#   shasum -a 256 --ignore-missing -c SHA256SUMS   # macOS, which has no sha256sum
#
# An empty directory is an error. Every build job uploads with
# if-no-files-found: error and publish needs all three, so a failed build skips
# this job outright - an empty dist means the download step matched no
# artifacts, which is a wiring bug rather than a build failure.
#
# Progress goes to stdout; only diagnostics go to stderr, so a healthy run does
# not render entirely in red.
set -Eeuo pipefail

# Byte-wise collation, which is what orders the glob below. Without it the file
# would differ between runners with different locales.
export LC_ALL=C

dir="${1:-dist}"
out="SHA256SUMS"

if [[ ! -d "$dir" ]]; then
  echo "::error::$dir is not a directory." >&2
  exit 1
fi

cd "$dir"

# Dotfiles are deliberately out of scope: no release glob publishes one, so
# listing it here would vouch for a file nobody can download.
shopt -s nullglob
files=()
for entry in *; do
  [[ -f "$entry" && "$entry" != "$out" ]] && files+=("$entry")
done

# The guard sits immediately before the use: sha256sum with no operands reads
# stdin instead of failing, so an empty list here would hash nothing, write the
# digest of empty input and exit 0 - a manifest that verifies and means nothing.
if (( ${#files[@]} == 0 )); then
  echo "::error::No files to checksum in $dir." >&2
  exit 1
fi

# Binary mode explicitly. Left to the default, coreutils picks text on Linux and
# binary under Git Bash, and the mode marker is part of the line ("  name" vs
# " *name"), so the published file would differ by where it was generated. The
# digest itself is identical either way.
#
# Written through a temp file so no failure can leave a partial manifest sitting
# in the asset directory for a later step to publish.
tmp="$(mktemp)"
trap 'rm -f -- "$tmp"' EXIT
sha256sum -b -- "${files[@]}" > "$tmp"
mv -- "$tmp" "$out"

echo "Wrote $out covering ${#files[@]} file(s)."
cat "$out"
