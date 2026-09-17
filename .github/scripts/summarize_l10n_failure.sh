#!/usr/bin/env bash
# Turns the translation build's output into a verdict a reader can act on.
#
#   summarize_l10n_failure.sh <exit-status> <phase> <output-file> [root]
#
# <phase> is `deps` or `analyze`, whichever command produced the status. It is
# passed rather than inferred: the tree under test is main with only the
# branch's translations laid over it, so once dependencies resolve, anything
# the analyzer rejects was caused by a translation - nothing else changed.
# Inferring that from the text instead meant matching strings like `L10n` and
# `positional argument`, which also appear in diagnostics a submodule bump
# produces, and which would then blame a translator for someone else's commit.
#
# Exit codes:
#
#   0  the translations build
#   1  they do not
#   2  this script was called wrongly
#
# Two outcomes, not three: what a reader needs is which file to open, and that
# is prose, not a status. The text distinguishes a translation the build
# blamed from a failure nothing blamed on one - a pub server that cannot be
# reached is not a translator's mistake, and saying so keeps whoever reads the
# pull request from opening the wrong file.
#
# The translation sync opens its pull request with GITHUB_TOKEN, and GitHub
# does not start jobs for events that token raises: it records a run with zero
# jobs, so the pull request shows no checks while the Actions tab still lists
# something. See #40. This runs under the schedule instead, which is the only
# look a translation gets before it merges.
#
# Takes a path rather than reading stdin, unlike check_translation_sources.sh.
# Returning early from a stdin filter kills the producer with SIGPIPE and the
# caller's pipefail reports that instead, which is how this repository's other
# translation guard came to fail the sync it exempts. A file has no such edge.
set -Eeuo pipefail

if [[ $# -lt 3 ]]; then
  echo "::error::usage: summarize_l10n_failure.sh <status> <phase> <output> [root]" >&2
  exit 2
fi

status="$1"
phase="$2"
output="$3"
root="${4:-${GITHUB_WORKSPACE:-$PWD}}"

if [[ ! -f "$output" ]]; then
  echo "::error::No build output at $output" >&2
  exit 2
fi

if [[ "$status" == "0" ]]; then
  echo "Translations build."
  exit 0
fi

# Three failures, three shapes, all of them real - each was reproduced against
# this repository before this was written.
#
#   truncated file      gen-l10n names a path and a FormatException
#   placeholder renamed to a name ICU cannot lex - names file and key
#   placeholder renamed to a name it can - gen-l10n is silent and the analyzer
#                       fails instead, because the generated method grew an
#                       argument its callers do not pass
#
# The third is why this is not a gen-l10n check. `{area}` to `{zona}` compiles
# clean and breaks the build on main; only the analyzer sees it.
sites=()
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    *"The arb file "*)
      path="${line#*The arb file }"
      path="${path%% has the following*}"
      sites+=("$(basename "$path")")
      ;;
    "["*.arb:*)
      entry="${line#\[}"
      sites+=("${entry%%]*}")
      ;;
  esac
done < "$output"

if ((${#sites[@]} > 0)); then
  echo "A translation does not build."
  echo
  printf '%s\n' "${sites[@]}" | sort -u | while IFS= read -r what; do
    echo "::error::gen-l10n rejected $what" >&2
    echo "- \`$what\`"
  done
  echo
elif [[ "$phase" == "analyze" ]]; then
  echo "A translation builds, but no longer matches the code that uses it."
  echo
  echo "Only the translations differ from \`main\` here, so the analyzer is"
  echo "reporting their effect. A placeholder renamed to a name ICU accepts is"
  echo "valid on its own - the generated method changes shape and its callers"
  echo "stop matching. Compare the placeholders against"
  echo "\`translations/app_en.arb\`."
  echo
else
  echo "The translation build failed, and nothing blamed a translation."
  echo
fi

# The preamble is printed on every run including clean ones, and the absolute
# path is the runner's checkout root - noise to anyone reading this in a pull
# request. The root is stripped literally rather than by pattern: a greedy one
# eats into translated text, which gen-l10n echoes back when it complains.
echo "The build said:"
echo '```'
{ grep -v -e 'Because l10n.yaml exists' \
    -e 'To use the command line arguments' "$output" || true; } |
  sed "s#${root}[/\\\\]##g" |
  sed '/^[[:space:]]*$/d' |
  # Bounded, and fences neutered. One renamed placeholder yields an analyzer
  # error per call site, and a pull request body is capped at 65536
  # characters - past which `gh pr edit` fails and the verdict reaches nobody.
  # gen-l10n also echoes translated text back, so a translation containing a
  # fence would end this block early.
  sed 's/```/\x27\x27\x27/g' |
  # sed rather than `head -n 60`, which exits at the sixtieth line and
  # SIGPIPEs whatever is still writing upstream. Under `set -Eeuo
  # pipefail` that makes the pipeline 141 and the script exit right
  # here - before the closing fence below, leaving an unterminated code
  # block in the pull request body and a verdict nobody can read.
  #
  # Whether it fires is a race with the pipe buffer, so a short log
  # passes and a long one does not - precisely backwards, since a long
  # log is the case this exists for: one renamed placeholder yields an
  # analyzer error per call site. This sed reads to EOF and only stops
  # printing.
  sed -n '1,60p'
echo '```'

exit 1
