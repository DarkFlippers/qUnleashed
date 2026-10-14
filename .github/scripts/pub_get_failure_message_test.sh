#!/usr/bin/env bash
# Covers pub_get_failure_message.sh.
#
# Three of the four fixtures are captured output: the locale one is run
# 38542162783's, the gen-l10n one and the unreachable-server one come from
# summarize_l10n_failure_test.sh, which captured them by breaking this
# repository. The lockfile one is pub's own sentence, read out of the pinned
# SDK's snapshot rather than captured - breaking a lockfile on purpose to
# capture it would mean committing one.
#
# Every case asserts which message was chosen *and* that the others were not.
# A chooser that printed two, or the right one for the wrong reason, passes on
# a substring check alone.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/pub_get_failure_message.sh"
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

run() {
  rc=0
  bash "$SCRIPT" "$@" > "$work/out" 2> "$work/err" || rc=$?
  out="$(cat "$work/out")"
  err="$(cat "$work/err")"
}

# Which of the four it chose, by a word only that one carries.
chose() {
  case "$1" in
    locale) [[ "$err" == *"declares an @@locale its filename contradicts"* ]] ;;
    genl10n) [[ "$err" == *"A translation failed to compile"* ]] ;;
    lockfile) [[ "$err" == *"pubspec.lock does not match pubspec.yaml"* ]] ;;
    unknown) [[ "$err" == *"could not say why"* ]] ;;
  esac
}

expect_only() {
  local label="$1" want="$2" other
  if ! chose "$want"; then
    fail "$label: chose something else - $err"
    return
  fi
  for other in locale genl10n lockfile unknown; do
    [[ "$other" == "$want" ]] && continue
    if chose "$other"; then
      fail "$label: also printed the $other message - $err"
      return
    fi
  done
  pass "$label"
}

# Run 38542162783, the failure this whole chain exists for. Note what is in it:
# a hundred lines of package listing, "Got dependencies!", and then gen-l10n -
# so a reader who stops at the first screen sees a clean dependency resolution.
cat > "$work/locale.txt" <<'FIXTURE'
Resolving dependencies...
Downloading packages...
  analyzer 14.4.0 (14.5.0 available)
Got dependencies!
96 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Generating synthetic localizations package failed with 1 error:

Error: The locale specified in @@locale and the arb filename do not match.
Please make sure that they match, since this prevents any confusion
with which locale to use. Otherwise, specify the locale in either the
filename or the @@locale key only.
Current @@locale value: es-ES
Current filename extension: es
FIXTURE
run "$work/locale.txt"
if ((rc == 0)); then
  pass "a locale mismatch is classified without failing the script itself"
else
  fail "a locale mismatch is classified without failing the script ($rc)"
fi
expect_only "and the locale message is the one printed" locale
# It carries both gen-l10n's preamble and nothing about a lockfile, so the
# ordering of the branches is what decides this, not the text.
if [[ "$err" == *"check_arb_locales.sh"* ]] &&
  [[ "$err" == *"filename extension"* ]]; then
  pass "and it names the fixer and where the filename is to be found"
else
  fail "and it names the fixer and the filename: $err"
fi
if [[ "$out" == "" ]]; then
  pass "and the annotation goes to the run, not to stdout"
else
  fail "and the annotation goes to the run: $out"
fi

# A placeholder ICU cannot lex: gen-l10n fails and does name the file.
cat > "$work/genl10n.txt" <<'FIXTURE'
Resolving dependencies...
Got dependencies!
[app_ru.arb:commonCopyFailed] ICU Lexing Error: Unexpected character.
    Could not copy: {переменная}
                     ^
Generating synthetic localizations package failed with 1 error:
Error: Found syntax errors.
FIXTURE
run "$work/genl10n.txt"
expect_only "a translation that fails to compile gets the gen-l10n message" genl10n

# Both spellings of the line, because the synthetic package is what
# `generate: true` builds today and the word goes when it does.
cat > "$work/plain.txt" <<'FIXTURE'
Generating localizations package failed with 2 errors:
Error: Found syntax errors.
FIXTURE
run "$work/plain.txt"
expect_only "and the same without the word synthetic" genl10n

# pub's own sentence for the case --enforce-lockfile exists to catch.
cat > "$work/lockfile.txt" <<'FIXTURE'
Resolving dependencies...
The pubspec.yaml file has changed since the pubspec.lock file was generated, please run "flutter pub get" again.
FIXTURE
run "$work/lockfile.txt"
expect_only "a stale lockfile still gets the lockfile message" lockfile

# A second lockfile wording, for the branch rather than for the alternation:
# both reach one `grep -q 'pubspec.lock'`, and this is what would fail if that
# were ever narrowed to the one sentence above it.
cat > "$work/hash.txt" <<'FIXTURE'
Resolving dependencies...
The existing content-hash from pubspec.lock doesn't match contents for:
 * archive
FIXTURE
run "$work/hash.txt"
expect_only "and so does a content-hash that moved" lockfile

# The branch that used to be the lockfile message. A pub server nobody can
# reach is not a lockfile anybody has to regenerate.
cat > "$work/unreachable.txt" <<'FIXTURE'
Resolving dependencies...
Could not reach https://pub.dev. Check your network.
FIXTURE
run "$work/unreachable.txt"
expect_only "a failure with no lockfile and no translation in it says so" unknown
if [[ "$err" == *"not necessarily pubspec.lock"* ]]; then
  pass "and says what it is not, since that was the old answer"
else
  fail "and says what it is not: $err"
fi

# Called wrongly is its own status: sharing 0 with a classified failure would
# have the caller exit 1 having annotated nothing.
run
if ((rc == 2)) && [[ "$err" == *"usage:"* ]]; then
  pass "no argument is a usage error"
else
  fail "no argument is a usage error ($rc): $err"
fi

run "$work/absent.txt"
if ((rc == 2)) && [[ "$err" == *"No pub get output"* ]]; then
  pass "a missing file is a usage error"
else
  fail "a missing file is a usage error ($rc): $err"
fi

run one two
if ((rc == 2)); then
  pass "a second argument is a usage error"
else
  fail "a second argument is a usage error ($rc)"
fi

if ((failures > 0)); then
  printf '%d failure(s)\n' "$failures"
  exit 1
fi
echo "all passed"
