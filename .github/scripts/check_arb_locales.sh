#!/usr/bin/env bash
# Checks that every translation's `@@locale` agrees with the filename it
# arrived under, and with --write makes it so.
#
#   check_arb_locales.sh [--write] [dir]
#
# `dir` defaults to `translations`, which is where l10n.yaml points `arb-dir`.
# Checking by default and writing only on the flag is check_format.sh's shape.
# The reason here is this directory's own: everything in it except the English
# source is Crowdin's, check_translation_sources.sh blocks a hand edit to one,
# and a script that rewrote those files because somebody ran it to see what it
# said would be handing them a commit that guard then refuses. Nothing in CI
# passes --write any more; what it is still for is below, and so is why it
# stopped being the sync's job.
#
# ## Why anything has to be normalised
#
# Crowdin writes `@@locale` from its own language code and `crowdin.yml`'s
# `languages_mapping` decides the filename, and the two are different
# mechanisms: the mapping renames the file and never touches what is inside it.
# Spanish is where that first showed. Crowdin has no plain `es` to choose - its
# "Spanish" *is* `es-ES` - so `app_es.arb` comes back saying
# `"@@locale": "es-ES"` and `gen-l10n` refuses the pair:
#
#   The locale specified in @@locale and the arb filename do not match.
#   Current @@locale value: es-ES
#   Current filename extension: es
#
# Renaming the file does not settle it. `gen-l10n` parses the filename with
# `package:intl`'s `Locale.tryParse` and then writes the result back with
# underscores - `parserResult.toString().replaceAll('-', '_')`, in the
# `AppResourceBundle(File)` factory in gen_l10n_types.dart, which is also where
# the throw lives. So the comparison is `es-ES` against `es_ES`, and no
# filename can produce a dashed left-hand side. Every hyphenated entry in
# `crowdin.yml`'s `languages_mapping` is the same shape, the script subtag
# `sr-Latn` among them - that file is the one place the list lives, and
# Spanish is simply the first entry anybody enabled.
#
# ## Where this runs
#
# Inside the setup-flutter action, immediately before `flutter pub get` - which
# is the command that compiles the translations, and which reports this failure
# as something else. pub_get_failure_message.sh's header has that story. This
# is the preflight for it: it names the file, which gen-l10n for this one shape
# does not, and it needs nothing but the checkout.
#
# In the action rather than in ci.yml, because five jobs call that action and
# only one of them is ci.yml's. The four release builds had no guard at all
# while this sat in the analyze job. It therefore runs on macOS and Windows
# runners too, which is what keeps it to bash 3.2 and portable `sed` - the same
# constraint check_ffi_exports.sh carries, and for the same reason.
#
# The Crowdin sync passes `pub-get: false` and runs its own `pub get`, so it
# does not get that preflight. crowdin-rx.yml calls this script itself instead,
# after it has laid the pull request's translations over main.
#
# It used to call it with --write. That repaired the file on the Crowdin branch
# *after* the action had already committed, which left the branch one value
# apart from what Crowdin exports for good: every sync then had a diff whether
# a translation had changed or not, and #323 is the pull request that produces -
# two commits that cancel each other, nothing else in it. The rewrite moved to
# Crowdin, to a Custom Post-Export Processor app that applies this same rule to
# the export before the download - the rule above in JavaScript, kept in this
# repository at `.github/crowdin/normalise_locale.js`. The mapping cannot do it
# for the reason given there, and docs/adr/0016-the-translation-branch-has-one-owner.md
# is why the export is where it is fixed.
#
# --write stays as a hand lever: check_translation_sources.sh refuses a hand
# edit to a Crowdin-owned ARB on any branch but `CROWDIN_BRANCH`, so that
# branch is the only place its output may be committed - once, to unblock a
# release, which is not the every-sync repair #323 was.
#
# ## Why the filename wins, and why the key is kept
#
# The filename is already the decision: `crowdin.yml` chose it deliberately,
# and its note explains that `gen-l10n` refuses a country-coded ARB unless the
# base file for that language sits beside it - which is why the main variant of
# every family keeps the bare code. So `app_es.arb` holding Crowdin's `es-ES`
# Spanish is intended, and `@@locale` is the side that is wrong.
#
# Dropping the key would also build - `gen-l10n` falls back to the filename -
# but it would retire the one mistake that check does catch, a file renamed by
# hand, and leave a translation that no longer says what it is. Rewriting keeps
# both.
#
# `app_en.arb` is checked like the rest and never rewritten. gen-l10n builds a
# bundle for every file in `arb-dir`, the template included, so a mismatch
# there fails just as hard - and it is the one ARB a person edits by hand, so
# it is the one where this mistake can be made rather than imported. What it is
# not is the sync's to correct.
set -Eeuo pipefail

usage() {
  echo "::error::usage: check_arb_locales.sh [--write] [dir]" >&2
  exit 2
}

write=0
dir=""
for arg in "$@"; do
  case "$arg" in
    --write) write=1 ;;
    -*) usage ;;
    *)
      # An empty argument would otherwise fall through to the default below
      # and write to the repository's own translations/ instead of saying so.
      [[ -z "$arg" || -n "$dir" ]] && usage
      dir="$arg"
      ;;
  esac
done
dir="${dir:-translations}"

if [[ ! -d "$dir" ]]; then
  echo "::error::No ARB directory at $dir" >&2
  exit 2
fi

shopt -s nullglob
# Every `*.arb`, not `app_*.arb`: gen-l10n enumerates `arb-dir` with
# `(\w+)\.arb$` and locale-checks whatever it finds, so a stray `es.arb` or a
# one-character slip in crowdin.yml's mapping is a file it reads and this would
# not have looked at.
files=("$dir"/*.arb)

# A directory that stopped matching would otherwise pass in silence, which is
# how a guard becomes decoration.
if ((${#files[@]} == 0)); then
  echo "::error::No .arb files in $dir" >&2
  exit 2
fi

# Every locale the file declares, one per line. One extractor, called by the
# read and by the rewrite's own check below: written twice it would drift, and
# the half that drifted is the one that decides whether the rewrite worked.
#
# Anchored, which is safe because .gitattributes checks every ARB out as LF, so
# the key is either the first thing on its line or in a shape this cannot read
# - and the caller below tells those two apart rather than folding them
# together. No `| head -n 1` on the end of it: that construct SIGPIPEs its
# producer, which under `pipefail` is a 141 the caller reports as its own, and
# summarize_l10n_failure.sh's header is this repository's write-up of the day
# that cost.
declared_locales() {
  sed -n 's/^[[:space:]]*"@@locale"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1"
}

# Only --write needs one, and the only thing that passes it is this script's
# own test suite, in a fixture - so the default path leaves nothing behind on
# any job that checks the repository's translations.
if ((write)); then
  tmp="$(mktemp "${TMPDIR:-/tmp}/arb-locale-XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
fi

# The locale this derives from a filename. Deliberately stricter than gen-l10n,
# which accepts a lowercase region and ignores a name it cannot parse at all: a
# name this cannot reason about is a failure here rather than a guess at what
# the file meant.
locale_pattern='^[a-z]{2,3}(_[A-Z][a-z]{3})?(_([A-Z]{2}|[0-9]{3}))?$'

# Collected rather than reported one at a time, so a reader fixes everything
# wrong in one pass. check_changelog.sh makes the same argument.
offenders=()
unreadable=()
for file in "${files[@]}"; do
  name="$(basename "$file" .arb)"

  expected="${name#app_}"
  # A dashed filename is not one crowdin.yml produces, but gen-l10n would read
  # it, so it is read the same way here rather than rejected for its spelling.
  expected="${expected//-/_}"
  if [[ ! "$expected" =~ $locale_pattern ]]; then
    echo "::error file=$file::$file is not named for a locale this can derive." >&2
    unreadable+=("$name.arb is not named for a locale")
    continue
  fi

  declared="$(declared_locales "$file")"
  # Counted rather than collected with `mapfile`, which macOS's bash 3.2 does
  # not have and this now runs there. `wc -l` on the captured value, because
  # the capture has already stripped the trailing newline.
  count=0
  [[ -n "$declared" ]] && count="$(printf '%s\n' "$declared" | wc -l | tr -d '[:space:]')"

  if ((count > 1)); then
    # Dart's decoder is last-wins, so gen-l10n reads the other one. Which of
    # them was meant is not this script's guess to make.
    echo "::error file=$file::$file declares @@locale more than once." >&2
    unreadable+=("$name.arb declares @@locale $count times")
    continue
  fi

  if ((count == 0)); then
    # Absent and unreadable are different answers and used to share this
    # branch. gen-l10n takes the filename's locale when the key is absent,
    # which is the same answer this would have written - but when the key is
    # there in a shape the extractor cannot see, saying "fine" is the guard
    # approving the exact failure it exists to catch.
    if grep -q '@@locale' "$file"; then
      echo "::error file=$file::$file declares @@locale in a shape this cannot read - is it on its own line?" >&2
      unreadable+=("$name.arb declares @@locale unreadably")
    fi
    continue
  fi

  [[ "$declared" == "$expected" ]] && continue

  # The template is checked and not rewritten: see the header.
  if ((write == 0)) || [[ "$name" == "app_en" ]]; then
    offenders+=("$name.arb declares $declared, its filename says $expected")
    echo "::error file=$file::$file declares @@locale \"$declared\", but its filename says \"$expected\"." >&2
    continue
  fi

  # Through a temporary file rather than `sed -i`, which takes an argument on
  # BSD and none on GNU, and back with `cat` rather than `mv`, which would
  # leave the file at mktemp's 0600. open_next_cycle.sh rewrites pubspec the
  # same way.
  sed "s/^\([[:space:]]*\"@@locale\"[[:space:]]*:[[:space:]]*\"\)[^\"]*\"/\1$expected\"/" \
    "$file" > "$tmp"
  # The rewrite's own check, against the postcondition rather than against the
  # bytes: a substitution that matched nothing, or an anchor that drifted from
  # the extractor's, would otherwise be reported as a fix.
  if [[ "$(declared_locales "$tmp")" != "$expected" ]]; then
    echo "::error file=$file::Rewriting @@locale in $file did not take." >&2
    exit 2
  fi
  cat "$tmp" > "$file"
  echo "$name.arb: @@locale $declared -> $expected"
done

if ((${#offenders[@]} + ${#unreadable[@]} == 0)); then
  echo "${#files[@]} translations declare the locale their filename says."
  exit 0
fi

if ((${#offenders[@]} > 0)); then
  printf 'A translation declares a locale its filename contradicts:\n'
  printf '  %s\n' "${offenders[@]}"
fi

# Printed as well as the list above, not instead of it: a file this cannot read
# used to abort the loop where it was found, which hid every genuine mismatch
# behind it.
if ((${#unreadable[@]} > 0)); then
  printf 'A translation is not in a shape this can check:\n'
  printf '  %s\n' "${unreadable[@]}"
fi

cat <<'MESSAGE' >&2

gen-l10n refuses the pair from inside `flutter pub get`. This script's header
has why Crowdin sends it that way and why the filename is the side that wins.

Crowdin normalises its own export now, so a translation that arrived wrong
means the post-export app did not run, is not configured for this project, or
does not cover this language's filename. Fixing it there rather than here is
what keeps the next sync from reopening it.

`check_arb_locales.sh --write` settles every file but `translations/app_en.arb`,
which is this repository's own and is corrected by hand. Use it to see what the
value should be; see the header for the one branch it may be committed on.
MESSAGE

# 2 outranks 1: a file this cannot read is a different problem from one it can,
# and this directory's other guards all keep "called wrongly" and "found
# something" apart.
((${#unreadable[@]} > 0)) && exit 2
exit 1
