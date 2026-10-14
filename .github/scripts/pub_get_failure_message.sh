#!/usr/bin/env bash
# Says what failed when `flutter pub get --enforce-lockfile` fails.
#
#   pub_get_failure_message.sh <output-file>
#
# Prints one `::error::` annotation for the run and exits 0; the caller decides
# the step's status. 2 means it was called wrongly.
#
# ## Why this is not one message
#
# `generate: true` makes `pub get` compile the translations, so one command
# fails for two unrelated families of reason, and setup-flutter used to report
# every one of them as a stale `pubspec.lock`. Run 38542162783 is what that
# cost: `app_es.arb` from Crowdin declared `es-ES` while its filename said
# `es`, gen-l10n refused the pair, and the job told the reader to regenerate a
# lockfile that was fine. Nothing in the output mentioned a lockfile.
#
# A script rather than inline YAML in the composite action, because this is
# where the choosing happens and nothing can test bash inside a `run:` block.
# `summarize_l10n_failure.sh` was moved out for the same reason; #318 is the
# open complaint about what is still inline.
#
# ## Why each branch is matched the way it is
#
# The locale shape first and by its own sentence, because it is the only one
# gen-l10n reports without naming a file - telling that reader to look at "the
# file above" sends them to a filename that was never printed.
#
# Then any other localizations failure, from the line gen-l10n prints ahead of
# its diagnostics. `(synthetic )?` covers both spellings: the synthetic package
# is what `generate: true` builds today and the wording loses that word when it
# goes.
#
# Then the lockfile, matched on `pubspec.lock` appearing at all rather than
# assumed from everything left over: all four of the sentences pub has for this
# name the file, so the substring is enough. They are in the pinned SDK's pub
# snapshot if the list is ever worth checking again.
#
# And then nothing: a pub server that cannot be reached, a submodule that is
# not checked out so a path dependency has no pubspec, an SDK constraint, a
# full disk. Those used to be reported as the lockfile too. Saying "I do not
# know, read the output" is worth more than a confident wrong answer - that is
# the whole lesson of the run above.
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "::error::usage: pub_get_failure_message.sh <output-file>" >&2
  exit 2
fi

output="$1"
if [[ ! -f "$output" ]]; then
  echo "::error::No pub get output at $output" >&2
  exit 2
fi

if grep -q 'The locale specified in @@locale and the arb filename do not match' "$output"; then
  echo "::error::A translation declares an @@locale its filename contradicts, and gen-l10n refuses the pair. It names no file - the file is the one named for the 'Current filename extension' value above. '.github/scripts/check_arb_locales.sh' names it, and --write settles it. Nothing is wrong with pubspec.lock." >&2
elif grep -qE 'Generating (synthetic )?localizations package failed' "$output"; then
  echo "::error::A translation failed to compile. pub get generates the localizations, so this command is what reports it, and the gen-l10n output above names the file. Nothing is wrong with pubspec.lock." >&2
elif grep -q 'pubspec.lock' "$output"; then
  echo "::error::pubspec.lock does not match pubspec.yaml or the pinned Flutter SDK. Run 'flutter pub get' locally and commit the regenerated pubspec.lock. Do not drop --enforce-lockfile - that is what keeps CI and releases on the committed dependency set." >&2
else
  echo "::error::flutter pub get failed and this step could not say why. Read its output above; it is not necessarily pubspec.lock - a pub server that cannot be reached, a missing submodule and a full disk all land here." >&2
fi
