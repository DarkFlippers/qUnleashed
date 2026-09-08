#!/usr/bin/env bash
# Checks that the project's Dart is formatted.
#
#   check_format.sh            # fail if anything would change
#   check_format.sh --write    # format in place
#
# The file list comes from `git ls-files`, which is the right set for three
# reasons: submodule contents under lib/modules are gitlinks rather than tracked
# files, so flipperlib, dartufbt and the C++ tree are excluded without naming
# them; generated files are gitignored, so lib/services/localization/gen and
# firebase_options.dart are skipped; and a new directory is covered the day it
# is added rather than needing to be enumerated here.
#
# `dart format` does not read the analyzer's exclude list, which is why this
# cannot simply be `dart format lib test`.
set -Eeuo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

mode=(--output=none --set-exit-if-changed)
if [[ "${1:-}" == "--write" ]]; then
  mode=()
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--write]" >&2
  exit 2
fi

count="$(git ls-files -- 'lib/*.dart' 'lib/**/*.dart' 'test/*.dart' 'test/**/*.dart' | wc -l)"
if (( count == 0 )); then
  echo "::error::No tracked Dart files found to format-check." >&2
  exit 1
fi

# Batched through xargs: the list is a few hundred paths, which overruns the
# command-line limit on some hosts. xargs reports non-zero if any batch does.
if ! git ls-files -z -- 'lib/*.dart' 'lib/**/*.dart' 'test/*.dart' 'test/**/*.dart' \
     | xargs -0 -r -n 100 dart format "${mode[@]}" --; then
  echo "::error::Dart formatting differs. Run .github/scripts/check_format.sh --write" >&2
  exit 1
fi
echo "Checked $count tracked Dart file(s)."
