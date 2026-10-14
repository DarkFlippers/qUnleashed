#!/usr/bin/env bash
# Covers check_arb_locales.sh.
#
# The Spanish fixture is what Crowdin actually sent on 2026-10-14: a language
# enabled in the project and not yet worked on comes back as the key and
# nothing else. The rest of the shapes are the other entries in `crowdin.yml`'s
# mapping waiting to happen - a region, a script - and the two files that must
# not be touched.
#
# Each case asserts the files as well as the status, because this one writes:
# a fixer that reports a change it did not make, or makes one it did not
# report, passes a check on the exit code alone.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/check_arb_locales.sh"
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A fresh tree for every case, because this writes to it.
fixture() {
  rm -rf "$work/translations"
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
  # Crowdin's export for a language nobody has started. 25 bytes, no newline.
  printf '{\n  "@@locale": "es-ES"\n}' > translations/app_es.arb
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
  sed -n 's/^[[:space:]]*"@@locale"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" |
    head -n 1
}

# The label is written once. Typed into both the pass and the fail arm, the two
# drift and the suite starts reporting a case by another case's name.
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
# Checking is the default, and the default may not write. check_format.sh's
# shape, and the reason is the hand-edit guard: a rewrite nobody asked for is a
# commit check_translation_sources.sh then refuses.
fixture
run
expect_rc "a file that disagrees with its filename fails the check" 1
expect_locale "and nothing is written" translations/app_es.arb "es-ES"
expect_out "and the file and what it declares are named" "app_es.arb declares es-ES"
expect_err "and the file is annotated for the pull request" \
  "::error file=translations/app_es.arb::"

# The failure this exists for: #320, one key, a build nobody could read.
fixture
before_en="$(cat translations/app_en.arb)"
before_ru="$(cat translations/app_ru.arb)"
run --write
expect_rc "--write settles it" 0
expect_locale "and Crowdin's es-ES becomes the es its filename says" \
  translations/app_es.arb "es"
expect_out "and the change is reported" "app_es.arb: @@locale es-ES -> es"
if [[ "$(cat translations/app_en.arb)" == "$before_en" ]] &&
  [[ "$(cat translations/app_ru.arb)" == "$before_ru" ]]; then
  pass "and the files that already agreed are untouched"
else
  fail "and the files that already agreed are untouched"
fi
# One value, not a reformat: Crowdin exports the whole file, so the next sync
# would fight a rewrite of anything else in it.
if [[ "$(cat translations/app_es.arb)" == '{
  "@@locale": "es"
}' ]]; then
  pass "and only that value changed, the file's own shape included"
else
  fail "and only that value changed: $(cat translations/app_es.arb)"
fi

# Running it twice is what the sync does across two days.
run --write
expect_rc "a second --write has nothing to do" 0
expect_out "and says so" "declares the locale its filename says"
run
expect_rc "and the check passes once it has run" 0

# The rest of crowdin.yml's table. A region and a script both reach the
# filename with an underscore, which is the form gen-l10n compares against.
fixture
printf '{\n  "@@locale": "es-MX"\n}' > translations/app_es_MX.arb
printf '{\n  "@@locale": "sr-Latn"\n}' > translations/app_sr_Latn.arb
run --write
expect_rc "a region and a script are settled too" 0
expect_locale "a region keeps its region" translations/app_es_MX.arb "es_MX"
expect_locale "a script keeps its script" translations/app_sr_Latn.arb "sr_Latn"

# The source is this repository's own file, and a key in it is not the sync's
# to rewrite - whatever it says.
fixture
printf '{\n  "@@locale": "en-US",\n  "languageName": "English"\n}' > translations/app_en.arb
run --write
expect_rc "app_en.arb disagreeing is not an error" 0
expect_locale "and app_en.arb is left alone even then" translations/app_en.arb "en-US"

# gen-l10n takes the filename's locale when the key is absent, which is the
# same answer this would have written. Nothing to do is not a failure.
fixture
printf '{\n  "appTitle": "qUnleashed"\n}' > translations/app_de.arb
run --write
expect_rc "a file that declares no locale is not an error" 0
if [[ "$(cat translations/app_de.arb)" == '{
  "appTitle": "qUnleashed"
}' ]]; then
  pass "and it is left as it is, no key added"
else
  fail "and it is left as it is: $(cat translations/app_de.arb)"
fi

# A name gen-l10n cannot parse is one it ignores, trusting @@locale instead. A
# guess here would write a locale nothing asked for.
fixture
printf '{\n  "@@locale": "es-ES"\n}' > translations/app_spanish.arb
run --write
expect_rc "a filename that names no locale is a failure, not a guess" 2
expect_err "and says which file" "not named for a locale"

# Called wrongly is its own status. Sharing 1 with a file that needs fixing
# would report a broken translation for a missing directory.
fixture
run "$work/absent"
expect_rc "a missing directory is a usage error" 2
expect_err "and says what was missing" "No ARB directory"

mkdir -p "$work/empty"
run "$work/empty"
expect_rc "a directory with no ARB files is a usage error, not a clean run" 2
expect_err "and says that too" "No app_*.arb files"

run --nonsense
expect_rc "an unknown option is a usage error" 2
expect_err "and prints the usage" "usage:"

run translations extra
expect_rc "a second directory is a usage error rather than the last one winning" 2

if ((failures > 0)); then
  printf '%d failure(s)\n' "$failures"
  exit 1
fi
echo "all passed"
