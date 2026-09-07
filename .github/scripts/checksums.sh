#!/usr/bin/env bash
# Writes SHA256SUMS over the files in a directory, so a downloaded asset can be
# checked against the digest the release was built with. That catches a
# corrupted, truncated or mirrored download. The file is unsigned and is served
# from the same release as the assets, so it is not evidence about the release
# itself - see the signing issue for what would be.
#
#   checksums.sh [directory]   # default: dist
#
# Names are stored bare, so verification runs from wherever somebody downloaded
# to. Nobody fetches every asset, so the command has to tolerate the rest:
#
#   sha256sum --ignore-missing -c SHA256SUMS        # Linux
#   shasum -a 256 --ignore-missing -c SHA256SUMS    # macOS, which has no sha256sum
#   Get-FileHash <file> -Algorithm SHA256           # Windows, compared by eye
#
# This hashes whatever is in the directory and asserts only that it is not
# empty. It does not know the expected asset set, so it cannot notice a release
# that is short a platform - see #45.
set -Eeuo pipefail

# Byte-wise collation, which is what orders the glob below. Without it the file
# would differ between runners with different locales.
export LC_ALL=C

case "${1:-}" in
  --*) echo "Usage: $0 [directory]" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
  echo "Usage: $0 [directory]" >&2
  exit 2
fi

dir="${1:-dist}"
out="SHA256SUMS"

if [[ ! -d "$dir" ]]; then
  echo "::error::$dir is not a directory." >&2
  exit 1
fi

cd "$dir"

# Dotfiles are out of scope: no release glob publishes one, so listing it would
# vouch for a file nobody can download.
shopt -s nullglob
files=()
for entry in *; do
  [[ -f "$entry" && "$entry" != "$out" ]] || continue
  files+=("$entry")
done

# The guard sits immediately before the use: sha256sum with no operands reads
# stdin instead of failing, so an empty list would hash nothing, write the
# digest of empty input and exit 0 - a manifest that verifies and means nothing.
if (( ${#files[@]} == 0 )); then
  echo "::error::No files to checksum in $dir." >&2
  exit 1
fi

# Binary mode explicitly. Left to the default, coreutils picks text on Linux and
# binary under Git Bash, and the marker is part of the line ("  name" vs
# " *name"), so the file would differ by where it was generated.
sha256sum -b -- "${files[@]}" > "$out"

echo "Wrote $out covering ${#files[@]} file(s)."
cat "$out"
