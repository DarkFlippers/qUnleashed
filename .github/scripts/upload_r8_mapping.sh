#!/usr/bin/env bash
# Sends R8's mapping to Sentry, so an Android Java or Kotlin frame reads as a
# class and a method instead of `w2.r.k`.
#
#   upload_r8_mapping.sh [dist-dir] [mapping-dir] [pubspec-path]
#
# All three default to the repository's own, so CI calls it with no arguments
# and the test calls it with fixtures - the same arrangement check_changelog.sh
# uses and for the same reason.
#
# This is the one debug file `sentry_dart_plugin` cannot upload, and not for
# want of looking: `build/app/outputs` is the first directory it hands to
# sentry-cli, and the mapping is in it. The command is what excludes it -
# `debug-files upload` builds its type list as
# `DifType::all_names().filter(|name| name != "proguard")` - so a mapping moves
# through `proguard upload`, under a UUID, or not at all. #343.
#
# Why here and not in the build: the Sentry Gradle Plugin's own upload throws
# from inside `asSentryCliExec` and is a finalizer of `assembleRelease`, so an
# unreachable Sentry fails the Android build and `set -e` in `build/android.sh`
# then skips the copy into `dist/` - a release discarded over symbolication.
# `android/app/build.gradle.kts` records that at length. Here the same fault
# costs a warning.
#
# The two addresses come from the artifacts rather than from a second copy of
# anything. The UUID is read back out of a built APK, so the mapping is filed
# under the identifier events will actually carry - not one re-derived from a
# mapping a later R8 run might have changed. The org and project come from
# `pubspec.yaml`'s `sentry:` block, the same two lines `sentry_dart_plugin`
# reads, so there is one place to change them and no way for the two uploads to
# disagree about where they are going.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

dist="${1:-$ROOT/dist}"
mapping_dir="${2:-$ROOT/build/app/outputs/mapping/release}"
pubspec="${3:-$ROOT/pubspec.yaml}"

# Pinned and verified for the reason lint_workflows.sh gives about actionlint:
# this runs in the same repository whose release job holds the signing key, so
# a tool it fetches is not something to take on trust from a moving tag.
#
# 3.8.0 is also what the Sentry Gradle Plugin bundles, so this is the upload
# protocol that plugin was tested against - incidentally, not by construction.
# Nothing checks the two pins against each other, and they can move
# independently.
#
# Two things to re-check when this pin moves. `--uuid` is hidden and marked
# `[DEPRECATED]` in 3.8.0's `proguard upload` - which is itself the modern
# spelling, `upload-proguard` surviving only as a hidden legacy alias for it -
# and it works, its own help blessing this use ("you must ensure the UUID is
# generated deterministically based on the ProGuard mapping", which is what the
# plugin's `nameUUIDFromBytes` over R8's map hash does); but the day it goes,
# the symptom is an unrecognised argument. And a mapping path that does not
# exist is only a `warning:` to sentry-cli, which then uploads an empty set and
# exits 0, which is what `--require-one` below is for.
#
# `readonly`, and read from nothing: an environment variable that lowered
# either of these would be a pin silently weakened from outside, in the one job
# that holds the signing key.
readonly SENTRY_CLI_VERSION="3.8.0"
readonly SENTRY_CLI_SHA256="13f8cb34ae01a6a272d7d7c22e277a105286615b4020de900ea95a8de47cdbb6"

# The URL is the exception, and safe to override because the checksum above is
# not: anything else served here fails verification. That is what lets the
# suite point it at a stub and cover the download and the mismatch branch.
SENTRY_CLI_URL="${SENTRY_CLI_URL:-https://github.com/getsentry/sentry-cli/releases/download/${SENTRY_CLI_VERSION}/sentry-cli-Linux-x86_64}"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=sentry_proguard_uuid.sh
. "$HERE/sentry_proguard_uuid.sh"
# The artifact names and the mapping filenames, shared with the build and the
# gate so the three cannot disagree about what a release produced. ADR 0017.
# shellcheck source=android_artifacts.sh
. "$HERE/android_artifacts.sh"

summary() { cat >> "${GITHUB_STEP_SUMMARY:-/dev/stderr}"; }

# Every outcome but a good upload and a job that never minified ends here, and
# says so twice: an annotation, and a line in the job summary. `::warning::` is
# the quietest thing GitHub has and a collapsed step inside a green job is not
# read; the summary is what somebody looks at after a release. Three things
# produced an empty summary before this existed - a good upload, a step that
# never ran, and a swallowed failure - and only one of them is fine. #310.
# `error` rather than `warning` for the two that are misconfiguration rather
# than an outage: an unreadable slug, and a checksum that does not match.
not_uploaded() { # not_uploaded <warning|error> <annotation> <summary-line>
  echo "::$1::$2"
  {
    echo "### The R8 mapping was not uploaded"
    echo "$3"
  } | summary
}

# No silent exit path at all. The caller is `continue-on-error`, so a non-zero
# exit leaves the job green, writes nothing to the summary, and leaves only a
# red marker inside a collapsed log - while the step beside this one has
# already written "Debug symbols uploaded". Absence of a second heading is not
# a signal anybody reads.
# It cannot say nothing was sent, because by the time this can fire one half
# may already have gone: a release uploads two mappings and the inventory
# below is written per half as each finishes. Saying "before the mapping was
# sent" was true while there was one upload and would now discard the record
# of which UUID had already been filed.
unplanned_failure() {
  not_uploaded warning \
    "The R8 mapping step failed (exit $1) partway through. Any half not listed as uploaded above will NOT deobfuscate." \
    "The step failed with exit \`$1\` on the Android build of \`${SENTRY_RELEASE:-unknown}\`, partway through. The lines above say which halves were sent before it stopped; the job log has the failing command."
}
trap 'unplanned_failure "$?"; exit 0' ERR

# Set once and never restored: every glob below wants to expand to nothing
# rather than to itself, and this script does nothing after them.
shopt -s nullglob

# Two halves, because a release runs R8 twice and each run's UUID is embedded
# in what it built: each mapping has to be filed under the UUID of the
# artifact it describes. ADR 0017 §2 is the decision and the measurement.
apk_mapping="$mapping_dir/$R8_MAPPING_APK"
bundle_mapping="$mapping_dir/$R8_MAPPING_BUNDLE"

# Whether this is an Android job at all, and the only wholly quiet exit in the
# file. Every other platform's job reaches here with nothing Android in
# `dist/` and leaves without fetching anything.
#
# Keyed on ANY Android artifact rather than on the two the halves name,
# because keying it on those lost the #343 shape: a job holding the three
# per-ABI APKs but no universal one and no mapping matched nothing and exited
# 0 in silence, where the code this replaced had warned.
android_artifacts=("$dist"/$ANDROID_APK_GLOB "$dist"/$ANDROID_BUNDLE_GLOB)
if (( ${#android_artifacts[@]} == 0 )); then
  exit 0
fi

# The inventory. A reader has to be told how many halves to expect, or a half
# that is never mentioned reads exactly like a half that went fine - so the
# heading says two and every half gets a line.
#
# Emitted with the first line rather than up front, because a job with no
# token records nothing: a lone heading promising two outcomes and delivering
# none is worse than the silence the missing-token path exists to keep.
heading_written=0
record() { # record <label> <outcome>  -> one inventory line
  if (( ! heading_written )); then
    heading_written=1
    {
      echo "### R8 mappings, 2 to send"
      echo "For the Android build of \`${SENTRY_RELEASE:-unknown}\`:"
    } | summary
  fi
  printf -- '- %s: %s\n' "$1" "$2" | summary
}

# half_failed <label> <annotation> <inventory-detail>
#
# What a half's failure uses instead of `not_uploaded`, which emits its own
# `### The R8 mapping was not uploaded` heading - fine when there was one
# upload and one outcome, but inside the inventory it lands between the
# heading and the lines it belongs to. The annotation still fires, because
# that is the half of `not_uploaded` worth keeping here.
half_failed() {
  echo "::warning::$2"
  record "$1" "**NOT uploaded** - $3"
}

# PASS ONE: what each half has, before anything that needs a secret.
#
# Deliberately above the token gate. These checks need no credentials, and an
# earlier draft had them below it - so a job with no token said nothing about
# a missing mapping, while `too_many` two lines up still spoke. A gate's
# loudness should not depend on a secret any more than on another gate having
# run.
#
# Sets `half_artifact` rather than printing it, because `half_failed` writes
# to stdout and a command substitution would swallow the warning with it.
half_artifact=""
check_half() { # check_half <label> <mapping> <glob>
  local label="$1" mapping="$2" glob="$3"
  half_artifact=""

  # The variant name is in that path, so a flavour added later moves it and
  # this is what notices. Both mappings exist by construction after a
  # successful `android.sh`, which checks for them itself.
  if [[ ! -f "$mapping" ]]; then
    half_failed "$label" \
      "No R8 mapping for $label at ${mapping}. Their Java and Kotlin frames will NOT deobfuscate. Either R8 did not run for it, or its output moved - the variant name is in that path." \
      "no mapping at \`${mapping}\`"
    return 0
  fi

  # Exactly one, because `[0]` on a glob that matched several picks by
  # collation order - so a leftover from an earlier version wins
  # systematically, not randomly, and its UUID would be what a fresh mapping
  # got filed under. `verify_apks.sh` refuses that too; this is independent
  # because the uploader is also run by hand, where no gate went first.
  local matched=("$dist"/$glob)
  if (( ${#matched[@]} == 0 )); then
    half_failed "$label" \
      "R8 wrote a mapping for $label but no such artifact is in ${dist}, so its UUID could not be read. Those Java frames will NOT deobfuscate." \
      "no artifact in \`${dist}\` to read a UUID from"
    return 0
  fi
  if (( ${#matched[@]} > 1 )); then
    half_failed "$label" \
      "$dist holds ${#matched[@]} artifacts matching $glob, so there is no one artifact to read a UUID from. That mapping will NOT be uploaded." \
      "\`${dist}\` holds ${#matched[@]} artifacts matching \`$glob\` (${matched[*]##*/}). A release produces exactly one, so the rest are leftovers from another build"
    return 0
  fi

  half_artifact="${matched[0]}"
}

check_half "the APKs" "$apk_mapping" "$ANDROID_UNIVERSAL_GLOB"
apk_artifact="$half_artifact"
check_half "the App Bundle" "$bundle_mapping" "$ANDROID_BUNDLE_GLOB"
bundle_artifact="$half_artifact"

# Nothing left to send, and pass one has already said why for each half.
if [[ -z "$apk_artifact" && -z "$bundle_artifact" ]]; then
  exit 0
fi

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  # The debug-files step in the same action already said this, for the same
  # missing secret. It always runs and always reports, so this stays quiet
  # rather than saying it twice.
  exit 0
fi

# One source for both slugs. `sentry:` is a top-level block of flat scalars,
# two of which are `org` and `project`, so the keys are read from inside that
# block rather than from anywhere in the file that happens to say `project:`.
#
# The value is matched as a slug rather than as "the rest of the line", which
# is what makes `org: "dark-flippers"` and a trailing comment both read
# correctly. Quoting is a plausible edit to a YAML file and `sentry_dart_plugin`
# reads the same lines through a real parser, so it would be unaffected - and a
# quoted slug passed through to `--org` uploads to an organisation that does
# not exist, green, with a warning nobody connects to the quotes.
sentry_block="$(sed -n '/^sentry:$/,/^[^[:space:]]/p' "$pubspec")"
read_slug() {
  sed -nE "s/^[[:space:]]+$1:[[:space:]]*[\"']?([A-Za-z0-9._-]+)[\"']?[[:space:]]*(#.*)?\$/\1/p" \
    <<<"$sentry_block" | head -n 1
}
org="$(read_slug org)"
project="$(read_slug project)"
if [[ -z "$org" || -z "$project" ]]; then
  not_uploaded error \
    "Could not read both slugs out of ${pubspec}'s sentry: block (org '${org}', project '${project}'). They must be bare scalars." \
    "\`${pubspec##*/}\`'s \`sentry:\` block did not yield both slugs - org \`${org:-<empty>}\`, project \`${project:-<empty>}\`. \`sentry_dart_plugin\` reads the same two lines, so this breaks every upload, not only the mapping."
  exit 1
fi

# SENTRY_CLI lets the test substitute a stub and keeps the suite offline. CI
# sets nothing and gets the pinned download. Fetched once for both uploads.
cli="${SENTRY_CLI:-}"
if [[ -z "$cli" ]]; then
  cli="${RUNNER_TEMP:-/tmp}/sentry-cli"
  curl -fsSL -o "$cli" "$SENTRY_CLI_URL"
  # Its own annotation rather than the trap's: a checksum that does not match
  # is not a flaky download and should not read like one.
  if ! echo "${SENTRY_CLI_SHA256}  ${cli}" | sha256sum --check --quiet; then
    not_uploaded error \
      "sentry-cli ${SENTRY_CLI_VERSION} did not match its pinned SHA256. Nothing was run and no R8 mapping was uploaded." \
      "The pinned \`sentry-cli ${SENTRY_CLI_VERSION}\` download did not match \`${SENTRY_CLI_SHA256}\`. It was not executed. Check the release asset before changing the pin."
    exit 0
  fi
  chmod +x "$cli"
fi

# PASS TWO: the uploads. Each half is reported on its own, because they fail
# independently - the APKs' mapping can go while the bundle's does not, and a
# summary saying only "uploaded" would hide which half of the release is
# unreadable. The bundle is the half that matters more, since it is what Play
# installs.
#
# `exit 0` on any failure, and loudly, for the reason the whole file gives:
# the release is built and must not be thrown away over Sentry. Unlike the
# Dart plugin, sentry-cli's own exit code is the whole signal - the swallowing
# #310 turned on was the plugin's, one layer up from here.
upload_half() { # upload_half <label> <mapping> <artifact> <uuid-entry>
  local label="$1" mapping="$2" artifact="$3" asset="$4"
  # Pass one already said why, in the inventory and in an annotation.
  [[ -n "$artifact" ]] || return 0

  # Read from the built artifact, which is the only copy that matters: an
  # event carries the UUID its own artifact shipped with, so a mapping filed
  # under any other is a mapping nothing points at.
  #
  # Absent and present-but-unusable are one problem with one fix, so the
  # shared reader prints nothing for either and this is the single message for
  # both. A malformed value - or the comma-separated pair the key's plural
  # name allows - is therefore named here rather than inside sentry-cli.
  local artifact_name="${artifact##*/}"
  local uuid
  uuid="$(sentry_proguard_uuid "$artifact" "$asset")"
  if [[ -z "$uuid" ]]; then
    half_failed "$label" \
      "$artifact_name carries no usable io.sentry.ProguardUuids, so the R8 mapping for $label has nothing to be filed under. Those Java frames will NOT deobfuscate. \`verify_apks.sh\` refuses that, so reaching this means the two disagree." \
      "\`$artifact_name\` carries no usable UUID"
    return 0
  fi

  if ! "$cli" proguard upload --require-one \
    --uuid "$uuid" --org "$org" --project "$project" "$mapping"; then
    half_failed "$label" \
      "Uploading the R8 mapping for $label failed. Their Java and Kotlin frames will NOT deobfuscate until it is re-uploaded." \
      "\`$uuid\`, the upload itself failed - re-upload with \`sentry-cli proguard upload --uuid $uuid --org $org --project $project $mapping\`"
    return 0
  fi

  record "$label" "uploaded under \`$uuid\`"
}

upload_half "the APKs" "$apk_mapping" "$apk_artifact" "$SENTRY_UUID_ASSET"
upload_half "the App Bundle" "$bundle_mapping" "$bundle_artifact" "$SENTRY_UUID_ASSET_BUNDLE"
