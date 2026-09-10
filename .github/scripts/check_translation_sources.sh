#!/usr/bin/env bash
# Fails when a change edits a localization file that Crowdin owns.
#
# English is the only source: every other language is written in Crowdin and
# reaches this repository through the Crowdin RX pull request. Editing one by
# hand creates a second writer, and the two do not merge - Crowdin exports the
# whole file, so the next sync silently reverts whatever was written here. That
# is not hypothetical: it is how e0aed07 came to exist, and why the Russian
# translation has had to be restored by hand once already.
#
# Reads the changed paths on stdin, one per line, so the caller decides how to
# work out the diff and this stays testable without a repository.
#
#   git diff --name-only "origin/$BASE"...HEAD | check_translation_sources.sh
#
# Give it the old path of a rename as well as the new one. A file moved out of
# the pattern stops being Crowdin's export target without anything about the
# change looking like an edit to it.
#
# Set CROWDIN_BRANCH to the branch the sync opens its pull request from; a
# change on that branch is the sync doing its job and is allowed. Naming a
# branch that deliberately turns the check off, which is the point: this
# catches the mistake of not knowing the rule, and someone who does know it
# has a legitimate reason now and then.
set -Eeuo pipefail

crowdin_branch="${CROWDIN_BRANCH:-l10n/crowdin}"
branch="${GITHUB_HEAD_REF:-}"

if [[ "$branch" == "$crowdin_branch" ]]; then
  echo "On $crowdin_branch: this is the Crowdin sync, nothing to check."
  exit 0
fi

offenders=()
# The `|| [[ -n "$path" ]]` keeps the last line when the producer sends no
# trailing newline; without it the guard skips whichever file happens to be
# last, and says nothing about having done so.
while IFS= read -r path || [[ -n "$path" ]]; do
  [[ -z "$path" ]] && continue
  case "$path" in
    # The source of every string. Editing this is how strings are added.
    translations/app_en.arb) ;;
    fastlane/metadata/android/en-US/*) ;;
    # Everything else under translations/ is Crowdin's, at whatever depth. A
    # narrower pattern would miss app_de.arb moved one directory down, which
    # is just as broken and much harder to see.
    translations/*) offenders+=("$path") ;;
    # Of the store listing, Crowdin holds only the three texts crowdin.yml
    # names. The screenshots, the icon, the title and the video URL are kept
    # here for every locale, so they have to stay editable here.
    fastlane/metadata/android/*/short_description.txt | \
      fastlane/metadata/android/*/full_description.txt | \
      fastlane/metadata/android/*/changelogs/*.txt)
      offenders+=("$path")
      ;;
  esac
done

if ((${#offenders[@]} == 0)); then
  echo "No hand-edited translations."
  exit 0
fi

echo "::error::This change edits translations that Crowdin owns."
for path in "${offenders[@]}"; do
  echo "::error file=$path::$path is written in Crowdin, not here."
done
cat <<'MESSAGE' >&2

Add or change strings in translations/app_en.arb only. Everything else arrives
through the Crowdin sync, which exports each file whole - so an edit made here
is reverted by the next sync rather than merged with it.

To correct a translation, change it in Crowdin; it reaches this repository on
the next sync. To add a language, ask for it to be enabled in Crowdin.

Of the store listing Crowdin holds only short_description.txt,
full_description.txt and the changelogs. Screenshots, the icon, title.txt and
video.txt are kept here and can be changed in any locale.
MESSAGE
exit 1
