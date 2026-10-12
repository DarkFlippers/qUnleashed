#!/usr/bin/env bash
# Holds the Linux runtime floor: the oldest system a release can start on.
#
# #280 is why this exists. GLib 2.80 added `g_once_init_enter_pointer`, for
# pointer-sized statics, beside the `g_once_init_enter` that was already there;
# GObject's type machinery picks the new one when it is compiled against 2.80
# or newer headers, behind GLib's own version-macro gate. `G_DEFINE_TYPE` goes
# through that machinery, and `linux/runner/my_application.cc:15` uses it - as
# does every GTK plugin compiled from `linux/flutter/generated_plugins.cmake`.
# So a binary built against 2.80 needs a symbol GLib 2.72 has never had, and
# the loader refuses the executable before any of our code runs. GLib is
# forward compatible, not backward. The release was built on `ubuntu-latest`,
# which GitHub had moved to 24.04, and nothing stated a floor - so the floor
# was whatever that label last pointed at.
#
# ## Three modes, because the floor is three statements that have to agree
#
# `--check-runner` asserts the Linux job pins a numbered image. That pin *is*
# the fix, and it is the one part of it nothing else watches: ci.yml never
# builds Linux, so a pull request setting `runs-on` back to `ubuntu-latest`
# would go green and be caught only by the run that publishes. Cheap, needs no
# build, runs on every pull request.
#
# `--check-environment` asserts the build machine's GLib. This is the check
# that catches #280, and the only one that can: GLib carries no symbol
# versioning, so a finished binary cannot be asked. It runs *before* the build,
# because it already knows the answer then and a 30-minute build should not
# stand between a wrong image and saying so.
#
# With no mode, the bundle's versioned symbol references are checked too, after
# the build - glibc, libstdc++ and the C++ ABI do version their symbols, so for
# those the artifact states its own requirement. Different evidence from the
# GLib check, and neither substitutes for the other.
#
# Every refusal here fails the build. The modes that run in auto-release.yml
# never run on a pull request, so a `::warning::` would be an annotation on an
# otherwise green run that is about to publish - the shell version of
# CLAUDE.md's `LogService.info` as the last word on a failure.
#
# ## Raising the floor
#
# The numbers below are one decision in one place. `README.md` quotes them and
# this script's test suite checks that quote against `--print-floor`, so the
# promise a user reads cannot drift from what is enforced. Raising them drops
# distributions, so it belongs in a commit of its own that moves the README
# table too. `docs/releasing.md` holds what will force the question and the
# options for answering it; this comment deliberately does not restate them.
#
# Linux only, so bash 4 features are fine here - `declare -A` below needs it,
# unlike check_ffi_exports.sh, which also runs on macOS's bash 3.2. OBJDUMP,
# PKG_CONFIG and QU_REPO_ROOT are overridable so check_linux_abi_test.sh can
# drive every mode against fixtures, the last of them spelled as
# derive_version.sh spells it.
set -Eeuo pipefail

OBJDUMP="${OBJDUMP:-objdump}"
PKG_CONFIG="${PKG_CONFIG:-pkg-config}"

# --- the floor --------------------------------------------------------------

# These are the newest versions a binary may *require*, because they are what
# the oldest supported system provides. Hence `MAX_` for a thing the prose
# calls a floor: the floor is the system, the maximum is what it can satisfy.
#
# Ubuntu 22.04 LTS: GLib 2.72, glibc 2.35, and GCC 11's libstdc++
# (GLIBCXX_3.4.29, CXXABI_1.3.13). The libstdc++ numbers are the default
# *compiler's* on jammy, which is what bounds what a binary built there can
# reference; jammy's shipped runtime is newer, so `strings libstdc++.so.6` on a
# 22.04 box shows 3.4.30 and that is not a contradiction.
#
# Debian 12 is at or above all four - GLib 2.74, glibc 2.36, GCC 12's 3.4.30,
# and the same CXXABI_1.3.13 - so promising 22.04 covers it too.
#
# CURL_OPENSSL is the odd one and is not a release number at all: Debian and
# Ubuntu version libcurl's symbols by SSL backend, so the 4 is
# `libcurl.so.4`'s and not curl 7.81's. It is in the bundle because
# sentry-native links libcurl as its Linux transport. The number is read off
# the floor image rather than chosen: the first build on the pinned image
# references CURL_OPENSSL_4, and `ld` cannot emit a version reference that no
# library on the machine it linked against defined - so 22.04 provides it. A 5
# would mean a different soname, which jammy would not have at all, so this
# floor does carry signal despite the family not ratcheting with releases.
MAX_GLIB=2.72
declare -A MAX_SYMBOL_VERSION=(
  [GLIBC]=2.35
  [GLIBCXX]=3.4.29
  [CXXABI]=1.3.13
  [CURL_OPENSSL]=4
)

# Families this guard does not rule on.
#
# `GCC` is here for an honest but unsatisfying reason: nobody has read the
# floor image's `libgcc_s.so.1` maximum tag off a 22.04 box, and inventing a
# number to silence it would be a worse lie than saying nothing. One
# `objdump -T /lib/x86_64-linux-gnu/libgcc_s.so.1` there retires this list - it
# is an exemption by omission, not by principle, and the name says which. What
# a real bundle asks for today is GCC_3.0, GCC_3.3 and GCC_4.2.0, so the
# number being looked for is only an upper bound on those.
#
# Anything listed in neither table is an error, and that default matters more
# than it looks. The extraction below is one broad pattern on purpose, so a
# family nobody thought of still arrives; the first draft of this script warned
# about those and published anyway. That default has already earned itself:
# `CURL_OPENSSL_4` was named here as the reachable case while this was still
# hypothetical, and the first Linux build on the pinned image stopped on
# exactly it. `OPENSSL_*` is the same shape still waiting - wanting OpenSSL 3.2
# on a machine with 3.0.2 is #280 again, exactly.
declare -A UNRULED_FAMILIES=([GCC]=1)

# The build image must be a numbered Ubuntu, and this is the file that says so.
# Here rather than in lint_workflows.sh because the pin and MAX_GLIB are two
# statements of one decision; apart, each can go slack without the other
# noticing.
RUNNER_JOB=build-linux
RUNNER_PATTERN='^ubuntu-[0-9]{2}\.[0-9]{2}$'

usage() {
  echo "Usage: ${BASH_SOURCE[0]} [bundle-dir]         both checks, after a build" >&2
  echo "   or: ${BASH_SOURCE[0]} --check-environment  the build image, before one" >&2
  echo "   or: ${BASH_SOURCE[0]} --check-runner [workflow]" >&2
  echo "   or: ${BASH_SOURCE[0]} --print-floor" >&2
}

ROOT_DIR="${QU_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Not configurable. build/linux.sh and linux/CMakeLists.txt both hardcode the
# same name, so an override could only ever name a bundle that does not exist.
APP_NAME=qunleashed

failures=0

# Both take the message, so a refusal cannot be reported without also being
# counted - printing `::error::` and exiting 0 is the vacuous pass this whole
# file is organised against. `fault` is what verify_apks.sh calls its own.
die() {
  printf '::error::%s\n' "$@" >&2
  exit 1
}
fault() {
  printf '::error::%s\n' "$@" >&2
  failures=$((failures + 1))
}

is_version() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]]; }

# Is CANDIDATE within FLOOR. Components are compared numerically, so 2.9 is
# below 2.72 - which a string comparison gets backwards, and which is the whole
# question this script asks.
#
# Only as many components as the floor names are compared, because a floor
# names a *series*: `2.72` means any 2.72.x, so the runner's 2.72.4 is within
# it. Padding the floor with zeros instead would refuse the very image this is
# pinned to, which is how this function was first written.
#
# It validates its own arguments: an unparseable component makes the arithmetic
# error out, and an error inside `((...)) && return` is swallowed by the `&&`,
# so the function would answer "within". A comparison that fails *open* is the
# one shape this file cannot afford.
within_floor() {
  is_version "$1" && is_version "$2" ||
    die "Cannot compare version '$1' with floor '$2'."
  local -a candidate floor
  IFS=. read -r -a candidate <<<"$1"
  IFS=. read -r -a floor <<<"$2"
  local i c f
  for ((i = 0; i < ${#floor[@]}; i++)); do
    c="${candidate[i]:-0}"
    f="${floor[i]}"
    # 10# so a component like 08 is eight rather than an invalid octal.
    #
    # Both arms are needed, and the second is not the interesting one: the
    # early `return 0` is what makes this component-by-component rather than
    # last-component-only. GLIBCXX_3.3.30 against a 3.4.29 floor is within it,
    # because 3.3 settles the question before 30 is reached.
    ((10#$c < 10#$f)) && return 0
    ((10#$c > 10#$f)) && return 1
  done
  return 0
}

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required."
  done
}

# --- the pin ----------------------------------------------------------------

check_runner() {
  local workflow="${1:-$ROOT_DIR/.github/workflows/auto-release.yml}"
  [[ -f "$workflow" ]] || die "Workflow not found: $workflow"
  local runner
  runner="$(
    awk -v job="  $RUNNER_JOB:" '
      $0 == job { inside = 1; next }
      inside && /^  [A-Za-z]/ { inside = 0 }
      inside && $1 == "runs-on:" { print $2; exit }
    ' "$workflow"
  )"
  # The job being renamed away is not a pass: without this, a missing job reads
  # as a satisfied one, which is the failure class this file exists for.
  [[ -n "$runner" ]] || die \
    "No runs-on found for the $RUNNER_JOB job in $workflow." \
    "If that job was renamed, rename RUNNER_JOB with it."
  [[ "$runner" =~ $RUNNER_PATTERN ]] || die \
    "$RUNNER_JOB runs on '$runner', which is not a numbered Ubuntu image." \
    "A Linux binary can only start on systems at least as new as the image it" \
    "was built on, so a floating label means the floor moves when GitHub" \
    "moves it - which is #280. Pin ubuntu-NN.NN, and read docs/releasing.md" \
    "before changing which NN."
  echo "$RUNNER_JOB is pinned to $runner."
}

# --- the build environment --------------------------------------------------

check_environment() {
  require_tools "$PKG_CONFIG"
  # stderr is kept rather than discarded: whoever debugs this is better served
  # by pkg-config's own message - a broken .pc file, a PKG_CONFIG_PATH that
  # misses it - than by the guess below.
  local glib_version
  glib_version="$("$PKG_CONFIG" --modversion glib-2.0 || true)"
  # An unreadable version is indistinguishable from the version that shipped
  # #280, and this is the only check that can see either.
  [[ -n "$glib_version" ]] || die \
    "Could not read the glib-2.0 version from $PKG_CONFIG." \
    "Install libgtk-3-dev, or the floor cannot be checked at all."
  is_version "$glib_version" ||
    die "Unexpected glib-2.0 version string: '$glib_version'."

  # Counted rather than exited on, so a full run reports both halves. A build
  # that is wrong about the image and wrong about a symbol should say both once.
  if within_floor "$glib_version" "$MAX_GLIB"; then
    echo "glib-2.0 $glib_version is within the $MAX_GLIB floor."
  else
    fault \
      "This machine has glib-2.0 $glib_version, above the $MAX_GLIB floor." \
      "A binary built here needs symbols older GLib has not got - #280 is" \
      "that failure, and it reaches users as an app that will not start at" \
      "all. Build on an older image, or raise the floor in this script," \
      "README.md and docs/releasing.md deliberately."
  fi
}

# --- the finished artifact --------------------------------------------------

check_artifact() {
  local bundle="$1"
  require_tools "$OBJDUMP"

  # `if ! var="$(...)"` and not a process substitution: `find` prints what it
  # saw before erroring on an unreadable directory, and a process
  # substitution's exit status is invisible to both `set -e` and `pipefail` -
  # so the list would be silently short and the guard green over a subset of
  # the bundle. Command substitution under `pipefail` sees the whole pipeline.
  local listed
  if ! listed="$(find "$bundle" -name '*.so*' -type f | sort)"; then
    die "Could not list the shared libraries under $bundle."
  fi
  local -a libraries=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && libraries+=("$line")
  done <<<"$listed"

  # The bundle always ships libflutter_linux_gtk.so beside the plugin
  # libraries, so none at all means the layout changed and this guard is
  # reading the wrong directory - not that the bundle is clean.
  ((${#libraries[@]} > 0)) || die \
    "Found no shared libraries under $bundle, only the binary." \
    "The bundle layout changed; this guard would check almost nothing." \
    "Fix its find before trusting a green build."

  local -a images=("$bundle/$APP_NAME" "${libraries[@]}")
  # Which image asked for each reference, first one wins. A refusal that names
  # only the bundle leaves the next person reading 14 images to find out
  # whether it came from something built in this job or from a prebuilt
  # library carried in - and that decides the answer completely. The first run
  # of this guard stopped on CURL_OPENSSL_4 and could not say which.
  local -A needed_by=()
  local dump image parsed ref
  for image in "${images[@]}"; do
    # Per image, and fatal. The aggregate "did I find any references" check
    # below cannot see one image being skipped: a single readable library
    # satisfies it while the app binary - which is where my_application.cc's
    # G_DEFINE_TYPE ends up, and so where #280 lived - went unexamined.
    if ! dump="$("$OBJDUMP" -T "$image")"; then
      die "$OBJDUMP could not read $image, so this guard would check less of" \
        "the bundle than it reports. Refusing to pass."
    fi
    # The version *field*, not the whole line. objdump prints it second from
    # the end on a dynamic symbol line and the symbol name last, so reading the
    # line lets a mangled C++ name that happens to contain NAME_12 be taken for
    # a version requirement. Parens appear around the version in some objdump
    # output and carry no meaning here.
    parsed="$(
      awk '
        index($0, "*UND*") == 0 { next }
        NF < 2 { next }
        {
          field = $(NF - 1)
          gsub(/[()]/, "", field)
          print field
        }
      ' <<<"$dump"
    )"
    while IFS= read -r ref; do
      # What separates a version reference from objdump's other second-to-last
      # fields - `Base`, a section name, a symbol carrying no version. Narrow
      # on the family side and broad on the version side, so a family nobody
      # recorded still reaches the error below. GLIBC_PRIVATE is deliberately
      # out: it names no version, so there is nothing to compare.
      [[ "$ref" =~ ^[A-Z][A-Z0-9_]*_[0-9]+(\.[0-9]+)*$ ]] || continue
      [[ -n "${needed_by[$ref]:-}" ]] || needed_by[$ref]="$image"
    done <<<"$parsed"
  done

  local -a found=()
  if ((${#needed_by[@]} > 0)); then
    while IFS= read -r ref; do
      found+=("$ref")
    done < <(printf '%s\n' "${!needed_by[@]}" | sort)
  fi

  # Every real ELF references versioned glibc symbols. None at all means
  # objdump said something this parser does not understand, which looks exactly
  # like a clean bundle and is the one failure a guard must not have.
  ((${#found[@]} > 0)) || die \
    "No versioned symbol references found in $bundle." \
    "Every ELF has some, so $OBJDUMP's output is not being parsed." \
    "Fix this guard before trusting a green build."

  local -a tolerated=()
  local -A family_image=()
  local reference family version floor culprit
  for reference in "${found[@]}"; do
    # From the last underscore, so a family carrying one of its own keeps it.
    # Allowing `[A-Z0-9]*` only read `CURL_OPENSSL_4` as the family `OPENSSL`
    # at version 4 - a family that does not exist, which both misnames the
    # report and would make a floor added later under the real name silently
    # never match.
    family="${reference%_*}"
    version="${reference##*_}"
    # Not a filter but an assertion that the pattern and this split still
    # agree. Silently skipping a reference it could not read is how a guard
    # goes quiet.
    is_version "$version" || die \
      "Could not read a version out of '$reference'." \
      "The extraction and the split disagree; fix this guard."
    # Relative to the bundle, which is where the interesting part of the path
    # is: `qunleashed` is this project's own code, `lib/something.so` is a
    # plugin's, and the absolute prefix is the same for all of them.
    culprit="${needed_by[$reference]#"$bundle"/}"
    [[ -n "${family_image[$family]:-}" ]] || family_image[$family]="$culprit"
    floor="${MAX_SYMBOL_VERSION[$family]:-}"
    if [[ -n "$floor" ]]; then
      within_floor "$version" "$floor" ||
        fault "$culprit needs $reference, above the ${family}_$floor floor."
    elif [[ -n "${UNRULED_FAMILIES[$family]:-}" ]]; then
      tolerated+=("$reference")
    else
      fault \
        "$culprit needs $reference and no floor is recorded for $family, so" \
        "whether it resolves on the floor image is unknown. Record a floor" \
        "for $family in this script, or add it to UNRULED_FAMILIES if its" \
        "tags cannot go backwards. Do not leave it unruled."
    fi
  done

  ((${#tolerated[@]} == 0)) || echo "Not ruled on, by name: ${tolerated[*]}."
  # Every family seen, each with one image that asks for it - not necessarily
  # the only one. On a red run the fault above names the image; this line is
  # for the green ones, which is when nobody can otherwise find out that -
  # say - the libcurl reference comes from sentry-native rather than from
  # anything this project calls.
  local summary=""
  while IFS= read -r family; do
    summary+="${summary:+, }$family via ${family_image[$family]}"
  done < <(printf '%s\n' "${!family_image[@]}" | sort)
  echo "Families seen: $summary."
  echo "Read ${#images[@]} images, ${#found[@]} versioned references."
}

# --- modes ------------------------------------------------------------------

case "${1:-}" in
  --print-floor)
    # So README.md, docs/releasing.md and release notes can quote this script
    # rather than keeping a second copy of the numbers.
    {
      echo "glib-2.0 $MAX_GLIB"
      for family in "${!MAX_SYMBOL_VERSION[@]}"; do
        echo "$family ${MAX_SYMBOL_VERSION[$family]}"
      done
    } | sort
    exit 0
    ;;
  --check-runner)
    check_runner "${2:-}"
    exit 0
    ;;
  --check-environment)
    check_environment
    ;;
  -*)
    usage
    exit 1
    ;;
  *)
    # Resolved rather than taken as `build/linux/x64/...`: the architecture is
    # in that path, build/linux.sh derives it from `uname -m`, and #45 is
    # already about a hardcoded x64 drifting away from a build that computes
    # it. Zero matches and two matches are both errors - "the bundle" has to
    # mean one thing. This is the path every release takes, because
    # auto-release.yml calls this with no argument.
    bundle="${1:-}"
    if [[ -z "$bundle" ]]; then
      candidates=()
      for candidate in "$ROOT_DIR"/build/linux/*/release/bundle; do
        [[ -d "$candidate" ]] && candidates+=("$candidate")
      done
      if ((${#candidates[@]} != 1)); then
        fault "Expected exactly one build/linux/*/release/bundle under $ROOT_DIR, found ${#candidates[@]}."
        usage
        exit 1
      fi
      bundle="${candidates[0]}"
    fi
    [[ -d "$bundle" ]] || die "Bundle directory not found: $bundle"
    [[ -f "$bundle/$APP_NAME" ]] || die "App binary not found: $bundle/$APP_NAME"
    check_environment
    check_artifact "$bundle"
    ;;
esac

((failures == 0)) || die \
  "The Linux build would not start on the floor this project supports." \
  "See the header of this script and #280."

echo "Linux ABI floor holds."
