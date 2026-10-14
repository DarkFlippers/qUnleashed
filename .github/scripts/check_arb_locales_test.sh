#!/usr/bin/env bash
# Covers check_arb_locales.sh.
#
# The Spanish fixture is what Crowdin actually sent on 2026-10-14, byte for
# byte: a language enabled in the project and not yet worked on comes back as
# the key and nothing else, 25 bytes with no trailing newline. The mapping
# cases are not invented either - they are read out of crowdin.yml, so a target
# added there that this script cannot derive fails here rather than on every
# job in the repository.
#
# Each case asserts the files as well as the status, because this one writes: a
# fixer that reports a change it did not make, or makes one it did not report,
# passes a check on the exit code alone. Where the file's own bytes are the
# point, the comparison is `cmp`, not `$(cat …)` - command substitution strips
# the trailing newline, which is exactly the byte the Crowdin fixture is here
# to carry.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/check_arb_locales.sh"
CROWDIN_YML="$HERE/../../crowdin.yml"
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A fresh tree for every case, because this writes to it.
fixture() {
  rm -rf "$work/translations" "$work/keep"
  mkdir -p "$work/translations"
  cd "$work"
  cat > translations/app_en.arb <<'ARB'
{
  "@@locale": "en",
  "appTitle": "qUnleashed",
  "@appTitle": {
    "description": "Application name."
  },
  "languageName": "English"
}
ARB
  cat > translations/app_ru.arb <<'ARB'
{
  "@@locale": "ru",
  "appTitle": "qUnleashed",
  "languageName": "Русский"
}
ARB
  printf '{\n  "@@locale": "es-ES"\n}' > translations/app_es.arb
  cp -r translations "$work/keep"
}

# One invocation per case, both streams kept. Capturing them by running the
# script twice - which the read-only summariser's suite does - would mean the
# second run saw the tree the first one had already fixed.
run() {
  rc=0
  bash "$SCRIPT" "$@" > "$work/out" 2> "$work/err" || rc=$?
  out="$(cat "$work/out")"
  err="$(cat "$work/err")"
}

locale_of() {
  sed -n 's/^[[:space:]]*"@@locale"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1"
}

# The label is written once. Typed into both arms it drifts, and the suite
# starts reporting one case under another case's name.
expect_rc() {
  if ((rc == $2)); then pass "$1"; else fail "$1 (exit $rc): $out $err"; fi
}
expect_out() {
  if [[ "$out" == *"$2"* ]]; then pass "$1"; else fail "$1: $out"; fi
}
expect_err() {
  if [[ "$err" == *"$2"* ]]; then pass "$1"; else fail "$1: $err"; fi
}
expect_locale() {
  local got
  got="$(locale_of "$2")"
  if [[ "$got" == "$3" ]]; then pass "$1"; else fail "$1: $got"; fi
}
# Bytes, not lines: the trailing newline is part of what must not change.
expect_same_bytes() {
  if cmp -s "$2" "$3"; then pass "$1"; else fail "$1: $2 and $3 differ"; fi
}
# Checking is the default, and the default may not write: everything under
# translations/ but the English source is Crowdin's, and a rewrite nobody asked
# for is a commit check_translation_sources.sh then refuses.
fixture
run
expect_rc "a file that disagrees with its filename fails the check" 1
expect_locale "and nothing is written" translations/app_es.arb "es-ES"
expect_same_bytes "and the whole file is byte-identical" \
  translations/app_es.arb "$work/keep/app_es.arb"
expect_out "and the file, what it declares and what was expected are named" \
  "app_es.arb declares es-ES, its filename says es"
expect_err "and the file is annotated for the pull request" \
  "::error file=translations/app_es.arb::"
expect_err "and the fix is named for whoever reads the red job" \
  "check_arb_locales.sh --write"

# The failure this exists for: #320, one key, a build nobody could read.
fixture
run --write
expect_rc "--write settles it" 0
expect_locale "and Crowdin's es-ES becomes the es its filename says" \
  translations/app_es.arb "es"
expect_out "and the change is reported" "app_es.arb: @@locale es-ES -> es"
expect_out "and the count of what was checked is reported" \
  "3 translations declare the locale their filename says"
expect_same_bytes "and a file that already agreed is untouched" \
  translations/app_ru.arb "$work/keep/app_ru.arb"
# One value, not a reformat - Crowdin exports the whole file, so the next sync
# would fight a rewrite of anything else in it. 22 bytes: `es-ES` to `es`, and
# still no trailing newline, which is asserted in bytes because `$(cat …)`
# cannot see it.
#
# This is GNU sed's answer. BSD sed terminates a final line that lacked a
# newline, so on macOS the file would come back a byte longer - which is why
# this suite is not in ci.yml's scripts-bsd job, unlike the four whose scripts
# run on a developer's own machine. Nothing runs --write but the sync, on
# ubuntu-latest; the bare check that the setup-flutter action runs on every
# runner reads the file and does not rewrite it, so that path is
# platform-independent either way.
printf '{\n  "@@locale": "es"\n}' > "$work/want-es.arb"
expect_same_bytes "and only that value changed, down to the missing newline" \
  translations/app_es.arb "$work/want-es.arb"

# Running it twice is what the sync does across two days.
run --write
expect_rc "a second --write has nothing to do" 0
run
expect_rc "and the check passes once it has run" 0

# The sync's own invocation: --write and a directory, from somewhere else. No
# other caller writes, and its pull requests are not where a mistake shows.
fixture
cd "$HERE"
run --write "$work/translations"
expect_rc "--write with a directory is the sync's call and works" 0
expect_locale "and it writes to that directory" "$work/translations/app_es.arb" "es"
cd "$work"

# The normal case for this repository, not an edge: crowdin.yml maps ten
# languages and the first sync to enable several delivers several wrong keys.
# A report that named one would have the reader push and fail again.
fixture
printf '{\n  "@@locale": "pt-PT"\n}' > translations/app_pt.arb
printf '{\n  "@@locale": "zh-CN"\n}' > translations/app_zh.arb
run
expect_rc "several offenders still fail the check" 1
if [[ "$out" == *"app_es.arb declares es-ES"* ]] &&
  [[ "$out" == *"app_pt.arb declares pt-PT"* ]] &&
  [[ "$out" == *"app_zh.arb declares zh-CN"* ]]; then
  pass "and every one of them is named, not just the first"
else
  fail "and every one of them is named: $out"
fi
run --write
expect_rc "and --write settles all of them" 0
expect_locale "pt" translations/app_pt.arb "pt"
expect_locale "zh" translations/app_zh.arb "zh"

# Read out of crowdin.yml rather than restated: locale_pattern is strict, so a
# target spelled `pt-BR` or `sr_latn` there would make this script exit 2 on
# every job. That belongs here, where it is one red test.
fixture
mappings="$(sed -n '/two_letters_code:/,/^[^ ]/p' "$CROWDIN_YML" |
  sed -n 's/^ \{4\}\([A-Za-z0-9-]*\): \([A-Za-z0-9_]*\)$/\1 \2/p')"
if [[ -n "$mappings" ]]; then
  pass "crowdin.yml's mapping parsed, so the cases below tested something"
else
  fail "crowdin.yml's mapping parsed, so the cases below tested something"
fi
mapping_failures=0
while read -r code target; do
  [[ -z "$code" ]] && continue
  printf '{\n  "@@locale": "%s"\n}' "$code" > "translations/app_$target.arb"
  rc=0
  bash "$SCRIPT" --write > /dev/null 2>&1 || rc=$?
  got="$(locale_of "translations/app_$target.arb")"
  if ((rc != 0)) || [[ "$got" != "$target" ]]; then
    mapping_failures=$((mapping_failures + 1))
    printf '        %s -> app_%s.arb left %s (exit %d)\n' "$code" "$target" "$got" "$rc"
  fi
  rm -f "translations/app_$target.arb"
done <<< "$mappings"
if ((mapping_failures == 0)); then
  pass "every language crowdin.yml maps is one this can derive and settle"
else
  fail "every language crowdin.yml maps is one this can derive ($mapping_failures)"
fi

# A region and a script subtag both survive the rewrite - but crowdin.yml maps
# `es-MX` and `sr-Latn`, so the loop above already covers both. What it does
# not cover is a code the mapping has no entry for, which is what an ARB
# arriving straight from a `%locale%` pattern would look like.
fixture
printf '{\n  "@@locale": "es-419"\n}' > translations/app_es_419.arb
run --write
expect_rc "a code the mapping does not list is settled on its own terms" 0
expect_locale "and a numeric region survives it" translations/app_es_419.arb "es_419"

# gen-l10n builds a bundle for every file in arb-dir, the template included, so
# a mismatch there fails `pub get` like any other - and app_en.arb is the one
# ARB a person edits by hand, so it is the one where this can be made rather
# than imported. Checked, and never rewritten.
fixture
printf '{\n  "@@locale": "en-US",\n  "languageName": "English"\n}' > translations/app_en.arb
cp translations/app_en.arb "$work/keep/app_en.arb"
run --write
expect_rc "app_en.arb disagreeing is a failure like any other" 1
expect_out "and it is named" "app_en.arb declares en-US"
expect_same_bytes "but --write does not touch the English source" \
  translations/app_en.arb "$work/keep/app_en.arb"
expect_err "and the message says it is corrected by hand" "by hand"

# gen-l10n parses JSON, not lines. A key the extractor cannot see used to share
# a branch with a key that is absent, so the exact #320 breakage passed the
# guard and the fixer, both green.
fixture
printf '{"@@locale": "es-ES", "appTitle": "x"}\n' > translations/app_es.arb
run --write
expect_rc "a key this cannot read is a failure, not a pass" 2
expect_err "and says what is wrong with it" "shape this cannot read"
expect_locale "and the file is left alone" translations/app_es.arb ""

# Dart's decoder is last-wins, so gen-l10n reads the second. Guessing which was
# meant is not this script's business.
fixture
printf '{\n  "@@locale": "es",\n  "@@locale": "es-ES"\n}' > translations/app_es.arb
run --write
expect_rc "two locale keys are a failure rather than a guess" 2
expect_err "and says how many there were" "more than once"

# A file that declares nothing is the one case where silence is right:
# gen-l10n takes the filename's locale, which is what this would have written.
fixture
printf '{\n  "appTitle": "qUnleashed"\n}' > translations/app_de.arb
cp translations/app_de.arb "$work/keep/app_de.arb"
run --write
expect_rc "a file that declares no locale is not an error" 0
expect_same_bytes "and it is left as it is, no key added" \
  translations/app_de.arb "$work/keep/app_de.arb"

# gen-l10n enumerates every *.arb in arb-dir, so a stray one is a file it reads
# and refuses. A guard that looked only at app_*.arb would pass it.
fixture
printf '{\n  "@@locale": "es-ES"\n}' > translations/es.arb
run
expect_rc "an ARB that is not named app_* is checked too" 1
expect_out "and is named" "es.arb declares es-ES"

# One unreadable name used to abort the loop, which hid every genuine mismatch
# behind it and left a half-written tree. Everything wrong is named at once.
fixture
printf '{\n  "@@locale": "es-ES"\n}' > translations/spanish.arb
run
expect_rc "a filename that names no locale is a failure, not a guess" 2
expect_err "and says which file" "not named for a locale"
expect_out "and the offenders behind it are still named" "app_es.arb declares es-ES"

# Called wrongly is its own status. Sharing 1 with a file that needs fixing
# would report a broken translation for a missing directory.
fixture
run "$work/absent"
expect_rc "a missing directory is a usage error" 2
expect_err "and says what was missing" "No ARB directory"

mkdir -p "$work/empty"
run "$work/empty"
expect_rc "a directory with no ARB files is a usage error, not a clean run" 2
expect_err "and says that too" "No .arb files"

run --nonsense
expect_rc "an unknown option is a usage error" 2
expect_err "and prints the usage" "usage:"

run translations extra
expect_rc "a second directory is a usage error rather than the last one winning" 2

run --write ""
expect_rc "an empty directory argument does not silently become the default" 2

if ((failures > 0)); then
  printf '%d failure(s)\n' "$failures"
  exit 1
fi
echo "all passed"
