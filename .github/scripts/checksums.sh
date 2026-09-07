#!/usr/bin/env bash
# Writes SHA256SUMS over the files in a directory, in the format `sha256sum -c`
# reads, so somebody can verify a downloaded release asset without trusting the
# page it came from.
#
#   checksums.sh [directory]   # default: dist
#
# Names are stored bare rather than as paths, so verification runs from inside
# whatever directory the assets were downloaded to:
#
#   sha256sum -c SHA256SUMS
#
# An empty directory is an error. The release job reaches this only after three
# build jobs have uploaded their artifacts, so nothing to checksum means
# something upstream failed without failing the run.
set -Eeuo pipefail

dir="${1:-dist}"
out="SHA256SUMS"

if [[ ! -d "$dir" ]]; then
  echo "::error::$dir is not a directory." >&2
  exit 1
fi

cd "$dir"

# LC_ALL=C keeps the order byte-wise, so the same assets always produce a
# byte-identical file regardless of the runner's locale.
shopt -s nullglob
files=()
for entry in *; do
  [[ -f "$entry" && "$entry" != "$out" ]] && files+=("$entry")
done
if (( ${#files[@]} == 0 )); then
  echo "::error::No files to checksum in $dir." >&2
  exit 1
fi
mapfile -t files < <(printf '%s\n' "${files[@]}" | LC_ALL=C sort)

# Binary mode explicitly: it never translates line endings and is what the
# assets are. Left to the default, coreutils picks text mode on Linux and binary
# under Git Bash, so the published file would differ by where it was generated.
sha256sum -b -- "${files[@]}" > "$out"

echo "Wrote $out covering ${#files[@]} file(s)." >&2
cat "$out" >&2
