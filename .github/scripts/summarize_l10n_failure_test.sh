#!/usr/bin/env bash
# Covers summarize_l10n_failure.sh.
#
# Every fixture is real output, captured by breaking a translation in this
# repository and running the command. Invented output would only prove the
# parser matches what the parser expects.
#
# Each case asserts the exit code and the prose, because the prose is what a
# reader of the pull request acts on - it says which file to open, or that no
# translation was to blame at all.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/summarize_l10n_failure.sh"
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A truncated app_ru.arb: valid until it stops mid-file.
cat > "$work/truncated.txt" <<'FIXTURE'
Because l10n.yaml exists, the options defined there will be used instead.
To use the command line arguments, delete the l10n.yaml file in the Flutter project.

The arb file /home/runner/work/qUnleashed/qUnleashed/translations/app_ru.arb has the following formatting issue:
FormatException: Unexpected end of input (at line 2967, character 29)
  "paintStop": "Остановить",
                            ^
FIXTURE

# {error} renamed to {переменная}: valid JSON, so anything that only parses
# the file lets it through. Captured from flutter pub get, which is what runs.
cat > "$work/icu.txt" <<'FIXTURE'
Resolving dependencies...
Got dependencies!
[app_ru.arb:commonCopyFailed] ICU Lexing Error: Unexpected character.
    Could not copy: {переменная}
                     ^
Generating synthetic localizations package failed with 1 error:
Error: Found syntax errors.
FIXTURE

# {area} renamed to {zona}. gen-l10n and pub get both exit 0; the analyzer is
# the only thing that sees it. This is the case a gen-l10n-only check misses,
# and the most likely shape of all - a Latin-alphabet typo.
cat > "$work/analyzer.txt" <<'FIXTURE'
Analyzing qUnleashed...

  error - 2 positional arguments expected by 'storageClearTitle', but 1 found. Try adding the missing arguments - lib/pages/option/pages/storage.dart:161:76 - not_enough_positional_arguments

1 issue found.
FIXTURE

cat > "$work/unrelated.txt" <<'FIXTURE'
Resolving dependencies...
Could not reach https://pub.dev. Check your network.
FIXTURE

# Only the two preamble lines. grep -v selects nothing here, and a pipeline
# under pipefail then aborts the script part-way through its own output.
cat > "$work/clean.txt" <<'FIXTURE'
Because l10n.yaml exists, the options defined there will be used instead.
To use the command line arguments, delete the l10n.yaml file in the Flutter project.
FIXTURE

# The phase is the caller's, not a guess: the tree under test is main with
# only the branch's translations laid over it, so once dependencies resolve,
# whatever the analyzer rejects was caused by a translation.
run() {
  local status="$1" phase="$2" file="$3"
  local root=/home/runner/work/qUnleashed/qUnleashed
  set +e
  out="$(bash "$SCRIPT" "$status" "$phase" "$file" "$root" 2>/dev/null)"
  rc=$?
  err="$(bash "$SCRIPT" "$status" "$phase" "$file" "$root" 2>&1 >/dev/null)"
  set -e
}

# A clean run decides whether the sync marks the pull request good, so a false
# positive here stops translations landing at all.
run 0 deps "$work/clean.txt"
if ((rc == 0)) && [[ "$out" == *"Translations build."* ]]; then
  pass "a successful run is reported as one"
else
  fail "a successful run is reported as one (exit $rc): $out"
fi

# The status decides, not the text: the preamble is printed on every run, so a
# summariser hunting for failure words in clean output would be guessing.
run 1 deps "$work/clean.txt"
if ((rc == 1)) && [[ "$out" == *"nothing blamed a translation"* ]]; then
  pass "a failing status with unremarkable output blames no translation"
else
  fail "a failing status with unremarkable output blames no translation ($rc)"
fi

run 1 deps "$work/truncated.txt"
if ((rc == 1)) && [[ "$out" == *"app_ru.arb"* ]]; then
  pass "a truncated file is named, and blamed"
else
  fail "a truncated file is named, and blamed (exit $rc): $out"
fi
if [[ "$out" == *"FormatException"* ]]; then
  pass "and the reason survives"
else
  fail "and the reason survives: $out"
fi
if [[ "$out" != *"/home/runner/work"* ]]; then
  pass "without the runner's absolute path"
else
  fail "without the runner's absolute path: $out"
fi

run 1 deps "$work/icu.txt"
if ((rc == 1)) && [[ "$out" == *"app_ru.arb:commonCopyFailed"* ]]; then
  pass "a placeholder ICU cannot lex names the file and the key"
else
  fail "a placeholder ICU cannot lex names the file and the key ($rc): $out"
fi

# The case that made this an analyze check rather than a gen-l10n one.
run 1 analyze "$work/analyzer.txt"
if ((rc == 1)); then
  pass "a placeholder ICU accepts is still blamed on the translation"
else
  fail "a placeholder ICU accepts is still blamed on the translation ($rc)"
fi
if [[ "$out" == *"no longer matches the code"* ]]; then
  pass "and says what kind of breakage it is"
else
  fail "and says what kind of breakage it is: $out"
fi

# A pub server that cannot be reached is not a translator's mistake, and the
# body is where that has to be said - it is what sends a reader to a file.
run 1 deps "$work/unrelated.txt"
if ((rc == 1)) && [[ "$out" == *"nothing blamed a translation"* ]]; then
  pass "a failure nothing blamed on a translation says so"
else
  fail "a failure nothing blamed on a translation says so ($rc): $out"
fi

# The annotation belongs on the run. Sent to stdout it would be captured into
# the pull request body as literal ::error:: text, which is the caller's whole
# use of this script's output.
run 1 deps "$work/icu.txt"
if [[ "$err" == *"::error::"* ]] && [[ "$out" != *"::error::"* ]]; then
  pass "the annotation goes to the run, not into the body"
else
  fail "the annotation goes to the run, not into the body: out=$out err=$err"
fi

# grep -v selects nothing from a preamble-only file, and a pipeline under
# pipefail then kills the script before it closes its own code fence.
run 1 deps "$work/clean.txt"
opens=$(grep -c '^```$' <<< "$out" || true)
if ((opens > 0)) && ((opens % 2 == 0)); then
  pass "the code fence is closed even when every line is filtered out"
else
  fail "the code fence is closed even when every line is filtered out ($opens)"
fi

# A submodule bump changing a signature produces the same words the old
# heuristic matched on - `positional argument`, `L10n` - while no translation
# is at fault. In the deps phase nothing has been analyzed, so nothing may be
# blamed on a translator.
cat > "$work/submodule.txt" <<'FIXTURE'
Resolving dependencies...
Got dependencies!
  error - Too many positional arguments: 0 expected, but 1 found. - lib/modules/flipperlib/lib/src/transport.dart:88:30 - extra_positional_arguments
  info - Unused import: 'gen/l10n_generated.dart'. - lib/services/localization/l10n.dart:4:8 - unused_import
FIXTURE
run 1 deps "$work/submodule.txt"
if ((rc == 1)) && [[ "$out" == *"nothing blamed a translation"* ]]; then
  pass "words that look like a translation failure are not blamed on one"
else
  fail "words that look like a translation failure are not blamed on one: $out"
fi

# A translation containing a fence would otherwise close this block early, and
# an unbounded excerpt can push the body past the API's limit.
{
  echo "Analyzing qUnleashed..."
  printf 'error - broken ```fence``` here - lib/x.dart:1:1\n'
  for i in $(seq 1 200); do echo "  error - filler $i - lib/x.dart:$i:1"; done
} > "$work/huge.txt"
run 1 analyze "$work/huge.txt"
fences=$(grep -c '^```$' <<< "$out" || true)
if ((fences == 2)) && (($(wc -l <<< "$out") < 90)); then
  pass "the excerpt is bounded and its fence survives translated backticks"
else
  fail "the excerpt is bounded and its fence survives ($fences fences, $(wc -l <<< "$out") lines)"
fi

# Called wrongly is its own verdict: sharing an exit code with a broken
# translation would report one to the pull request.
set +e
bash "$SCRIPT" 1 deps "$work/absent.txt" >/dev/null 2>&1
missing=$?
bash "$SCRIPT" >/dev/null 2>&1
noargs=$?
set -e
if ((missing == 2)) && ((noargs == 2)); then
  pass "a missing file and a missing argument are usage errors, not verdicts"
else
  fail "a missing file and a missing argument are usage errors ($missing,$noargs)"
fi

if ((failures > 0)); then
  printf '%d failure(s)\n' "$failures"
  exit 1
fi
echo "all passed"
