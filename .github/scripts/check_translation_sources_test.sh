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

# Both helpers assert on the exit code *and* the output. Checking only for a
# non-zero exit would let a guard that cannot even start report every blocking
# case as working: 126 and 127 are not 0 either.
allows() {
  local what="$1" branch="$2" out status=0
  shift 2
  out="$(run "$branch" "$@")" || status=$?
  if ((status == 0)) && [[ "$out" != *"::error"* ]]; then
    pass "$what"
  else
    fail "$what (exit $status): $out"
  fi
}

# The third argument is the path that must be named in the failure. A guard
# that blocks the right change while pointing at the wrong file sends the
# author looking in the wrong place.
blocks() {
  local what="$1" branch="$2" offender="$3" out status=0
  shift 3
  out="$(run "$branch" "$@")" || status=$?
  if ((status == 1)) && [[ "$out" == *"::error file=$offender::"* ]]; then
    pass "$what"
  else
    fail "$what (exit $status): $out"
  fi
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
# Every other case here goes through printf, which always terminates.
last_line_status=0
last_line_out="$(printf 'lib/main.dart\ntranslations/app_ru.arb' \
  | env -i PATH="$PATH" GITHUB_HEAD_REF=feature/x bash "$CHECK" 2>&1)" \
  || last_line_status=$?
if ((last_line_status == 1)) &&
  [[ "$last_line_out" == *"::error file=translations/app_ru.arb::"* ]]; then
  pass "input with no trailing newline"
else
  fail "input with no trailing newline (exit $last_line_status): $last_line_out"
fi

if ((failures)); then
  printf '\n%d check(s) failed\n' "$failures"
  exit 1
fi
printf '\nall passed\n'
