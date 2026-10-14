#!/usr/bin/env bash
# Checks that every translation's `@@locale` agrees with the filename it
# arrived under, and with --write makes it so.
#
#   check_arb_locales.sh [--write] [dir]
#
# `dir` defaults to `translations`, which is where l10n.yaml points `arb-dir`.
# Checking by default and writing on a flag is check_format.sh's shape, and for
# the same reason: everything under `translations/` except the English source
# is Crowdin's, check_translation_sources.sh blocks a hand edit to it, and a
# script that rewrote those files because somebody ran it to see what it said
# would be handing them a commit that guard then refuses. The sync passes
# --write; CI calls it bare.
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
# Renaming the file does not settle it either. `gen-l10n` parses the filename
# and then writes the result with underscores (gen_l10n_types.dart, in
# `AppResourceBundle.fromFile`), so the comparison is `es-ES` against `es_ES` -
# a dash on one side and an underscore on the other, and no filename spells it
# with a dash. Every country-coded entry in `crowdin.yml`'s table arrives the
# same way: `pt-PT`, `pt-BR`, `zh-CN`, `zh-TW`, `zh-HK`, `es-MX`, `fr-CA`,
# `sr-CS`, `sr-Latn`. Spanish is simply the first one anybody enabled.
#
# ## What it costs when it reaches CI
#
# `flutter pub get` generates the localizations, so the failure arrives from
# `pub get` - and until #320 everything that ran it called that a stale
# `pubspec.lock`, which is what that command fails for every other time. One
# wrong key, six jobs, and every reader sent to the wrong file. The setup-flutter
# action now picks its message from the output, and the sync's summariser knows
# this shape; this runs before either of them, where it needs nothing but the
# checkout.
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
# `app_en.arb` is left alone whatever it says. It is the source, written here
# rather than by the sync, and nothing may quietly rewrite a key in it.
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
      [[ -n "$dir" ]] && usage
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
files=("$dir"/app_*.arb)

# A directory that stopped matching would otherwise pass in silence, which is
# how a guard becomes decoration.
if ((${#files[@]} == 0)); then
  echo "::error::No app_*.arb files in $dir" >&2
  exit 2
fi

# One extractor, called by both the read and the rewrite below. Written twice
# it would drift, and the half that drifted is the one that decides whether the
# rewrite worked.
declared_locale() {
  sed -n 's/^[[:space:]]*"@@locale"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" |
    head -n 1
}

tmp="$(mktemp "${TMPDIR:-/tmp}/arb-locale-XXXXXX")"
trap 'rm -f "$tmp"' EXIT

# The locale `gen-l10n` reads out of a filename. Anything else is a name it
# ignores, trusting `@@locale` instead - so it is a failure here rather than a
# guess at what the file meant.
locale_pattern='^[a-z]{2,3}(_[A-Z][a-z]{3})?(_([A-Z]{2}|[0-9]{3}))?$'

offenders=()
for file in "${files[@]}"; do
  name="$(basename "$file" .arb)"
  [[ "$name" == "app_en" ]] && continue

  expected="${name#app_}"
  expected="${expected//-/_}"
  if [[ ! "$expected" =~ $locale_pattern ]]; then
    echo "::error file=$file::$file is not named for a locale gen-l10n can read." >&2
    exit 2
  fi

  # A file that declares no locale is left as it is: `gen-l10n` takes the
  # filename's then, which is the same answer this would have written.
  declared="$(declared_locale "$file")"
  [[ -z "$declared" ]] && continue
  [[ "$declared" == "$expected" ]] && continue

  if ((write == 0)); then
    offenders+=("$name.arb declares $declared")
    echo "::error file=$file::$file declares @@locale \"$declared\", but its filename says \"$expected\"." >&2
    continue
  fi

  # Through a temporary file rather than `sed -i`, which takes an argument on
  # BSD and none on GNU, and back with `cat` rather than `mv`, which would
  # leave the file at mktemp's 0600. open_next_cycle.sh rewrites pubspec the
  # same way.
  sed "s/^\([[:space:]]*\"@@locale\"[[:space:]]*:[[:space:]]*\"\)[^\"]*\"/\1$expected\"/" \
    "$file" > "$tmp"
  # The anchored substitution and the extractor above have to agree about what
  # declares the key. If they ever stop agreeing, this is a rewrite that
  # matched nothing and would otherwise be reported as a fix.
  if cmp -s "$file" "$tmp"; then
    echo "::error file=$file::Rewriting @@locale in $file changed nothing." >&2
    exit 2
  fi
  cat "$tmp" > "$file"
  echo "$name.arb: @@locale $declared -> $expected"
done

if ((${#offenders[@]} > 0)); then
  printf 'A translation declares a locale its filename contradicts:\n'
  printf '  %s\n' "${offenders[@]}"
  cat <<'MESSAGE' >&2

gen-l10n refuses the pair, and it refuses it from `flutter pub get` - which is
also where a stale pubspec.lock turns up, so the two used to be reported as
each other.

The sync normalises this on the Crowdin branch. A file that reached here
without it means that step did not run; `check_arb_locales.sh --write` is the
fix, and `crowdin.yml` is where the filename was decided.
MESSAGE
  exit 1
fi

echo "Every translation declares the locale its filename says."
