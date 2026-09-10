#!/usr/bin/env bash
# Covers check_translation_sources.sh. The guard only ever runs on a pull
# request, so without this a mistake in it would surface either as a gate that
# blocks every change or, worse, as one that quietly permits the hand edits it
# exists to stop.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/check_translation_sources.sh"
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# Runs the guard over the given paths with a clean environment, so a developer's
# own GITHUB_HEAD_REF cannot change a result.
run() {
  local branch="$1"
  shift
  printf '%s\n' "$@" | env -i PATH="$PATH" GITHUB_HEAD_REF="$branch" \
    bash "$CHECK" 2>&1
}

# Both assertions check the exit code *and* the output. A non-zero exit alone
# would let a guard that cannot even start report every blocking case as
# working: 126 and 127 are not 0 either.
assert_allowed() {
  local what="$1" out="$2" status="$3"
  if ((status == 0)) && [[ "$out" != *"::error"* ]]; then
    pass "$what"
  else
    fail "$what (exit $status): $out"
  fi
}

# A guard that blocks the right change while naming the wrong file sends the
# author looking in the wrong place, so the offending path has to appear.
assert_blocked() {
  local what="$1" offender="$2" out="$3" status="$4"
  if ((status == 1)) && [[ "$out" == *"::error file=$offender::"* ]]; then
    pass "$what"
  else
    fail "$what (exit $status): $out"
  fi
}

allows() {
  local what="$1" branch="$2" out status=0
  shift 2
  out="$(run "$branch" "$@")" || status=$?
  assert_allowed "$what" "$out" "$status"
}

blocks() {
  local what="$1" branch="$2" offender="$3" out status=0
  shift 3
  out="$(run "$branch" "$@")" || status=$?
  assert_blocked "$what" "$offender" "$out" "$status"
}

allows "an ordinary code change" feature/x \
  lib/main.dart test/foo_test.dart

allows "adding a string to the English source" feature/x \
  translations/app_en.arb lib/pages/x.dart

allows "changing the English store listing" feature/x \
  fastlane/metadata/android/en-US/full_description.txt

blocks "hand-editing Russian" feature/x \
  translations/app_ru.arb \
  translations/app_ru.arb

blocks "hand-editing Russian alongside legitimate work" feature/x \
  translations/app_ru.arb \
  lib/main.dart translations/app_en.arb translations/app_ru.arb

blocks "hand-editing a language that does not exist yet" feature/x \
  translations/app_de.arb \
  translations/app_de.arb

# Moving the file is how it stops being Crowdin's export target while no line
# of it changes. CI passes the old path of a rename as well as the new one.
blocks "moving a translation out of the pattern" feature/x \
  translations/app_ru.arb \
  translations/locales/app_ru.arb translations/app_ru.arb

blocks "adding a translation in a subdirectory" feature/x \
  translations/locales/app_de.arb \
  translations/locales/app_de.arb

blocks "hand-editing a translated store listing" feature/x \
  fastlane/metadata/android/ru-RU/full_description.txt \
  fastlane/metadata/android/ru-RU/full_description.txt

blocks "hand-editing a translated changelog" feature/x \
  fastlane/metadata/android/ru-RU/changelogs/1.txt \
  fastlane/metadata/android/ru-RU/changelogs/1.txt

# crowdin.yml claims three texts per locale and nothing else. The screenshots
# and the icon have never been Crowdin's, and neither the store title nor the
# video URL is uploaded - so blocking them would leave no way to change them.
allows "replacing a translated screenshot" feature/x \
  fastlane/metadata/android/ru-RU/images/phoneScreenshots/1.png

allows "changing a translated store title" feature/x \
  fastlane/metadata/android/ru-RU/title.txt \
  fastlane/metadata/android/ru-RU/video.txt

# The sync itself edits exactly these files; blocking it would stop every
# translation from ever landing.
allows "the Crowdin sync updating Russian" l10n/crowdin \
  translations/app_ru.arb

allows "the Crowdin sync adding a language" l10n/crowdin \
  translations/app_de.arb translations/app_zh.arb

# A branch merely named like the sync's is still the sync's branch by the only
# means CI has of telling; what must not happen is a *similar* name passing.
blocks "a branch that only looks like the sync branch" l10n/crowdin-fix \
  translations/app_ru.arb \
  translations/app_ru.arb

# Empty input is a change that touched nothing relevant, not a failure.
allows "no changed files at all" feature/x ""

# A path list that does not end in a newline must not lose its last entry.
# This is the one case that cannot go through run(), whose printf always
# terminates its output - so it builds the input by hand and then makes the
# same assertion as everything else.
unterminated_status=0
unterminated_out="$(printf 'lib/main.dart\ntranslations/app_ru.arb' \
  | env -i PATH="$PATH" GITHUB_HEAD_REF=feature/x bash "$CHECK" 2>&1)" \
  || unterminated_status=$?
assert_blocked "input with no trailing newline" translations/app_ru.arb \
  "$unterminated_out" "$unterminated_status"

# crowdin.yml declares what Crowdin owns; the guard restates it in another
# syntax, and nothing has been keeping the two in step. The direction that
# fails quietly is the dangerous one: a file added to crowdin.yml and not to
# the guard is simply allowed through, and the guard goes on passing. So take
# every translation pattern crowdin.yml defines, make a concrete path of it,
# and require the guard to block that path.
owned=0
while IFS= read -r pattern; do
  sample="${pattern#/}"
  sample="${sample//%two_letters_code%/de}"
  sample="${sample//%locale%/de-DE}"
  sample="${sample//%original_file_name%/1.txt}"
  sample="${sample//%file_name%/1}"
  sample="${sample//%file_extension%/txt}"
  blocks "crowdin.yml owns $sample" feature/x "$sample" "$sample"
  owned=$((owned + 1))
done < <(sed -nE 's/^[[:space:]]*translation:[[:space:]]*"([^"]+)".*/\1/p' \
  "$HERE/../../crowdin.yml")

# Nothing parsed means the check above silently tested nothing.
if ((owned > 0)); then
  pass "crowdin.yml patterns were readable ($owned)"
else
  fail "crowdin.yml patterns were readable (found none)"
fi

if ((failures)); then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
