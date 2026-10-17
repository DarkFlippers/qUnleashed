#!/usr/bin/env bash
# Sends R8's mapping to Sentry, so an Android Java or Kotlin frame reads as a
# class and a method instead of `w2.r.k`.
#
#   upload_r8_mapping.sh [dist-dir] [mapping-path] [pubspec-path]
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
mapping="${2:-$ROOT/build/app/outputs/mapping/release/mapping.txt}"
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
# and it works, its own help
# blesses this use ("you must ensure the UUID is generated deterministically
# based on the ProGuard mapping", which is what the plugin's
# `nameUUIDFromBytes` over R8's map hash does) - but the day it goes, the
# symptom is an unrecognised argument. And a mapping path that does not exist
# is only a `warning:` to sentry-cli, which then uploads an empty set and exits
# 0, which is what `--require-one` below is for.
SENTRY_CLI_VERSION="${SENTRY_CLI_VERSION:-3.8.0}"
SENTRY_CLI_SHA256="${SENTRY_CLI_SHA256:-13f8cb34ae01a6a272d7d7c22e277a105286615b4020de900ea95a8de47cdbb6}"
SENTRY_CLI_URL="https://github.com/getsentry/sentry-cli/releases/download/${SENTRY_CLI_VERSION}/sentry-cli-Linux-x86_64"

SENTRY_UUID_ASSET='assets/sentry-debug-meta.properties'
SENTRY_UUID_RE='[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'

summary() { cat >> "${GITHUB_STEP_SUMMARY:-/dev/stderr}"; }

# Every outcome but a good upload and a job that never minified ends here, and
# says so twice: an annotation, and a line in the job summary. `::warning::` is
# the quietest thing GitHub has and a collapsed step inside a green job is not
# read; the summary is what somebody looks at after a release. Three things
# produced an empty summary before this existed - a good upload, a step that
# never ran, and a swallowed failure - and only one of them is fine. #310.
not_uploaded() { # not_uploaded <annotation> <summary-line>
  echo "::warning::$1"
  {
    echo "### The R8 mapping was not uploaded"
    echo "$2"
  } | summary
}

# No silent exit path at all. The caller is `continue-on-error`, so a non-zero
# exit leaves the job green, writes nothing to the summary, and leaves only a
# red marker inside a collapsed log - while the step beside this one has
# already written "Debug symbols uploaded". Absence of a second heading is not
# a signal anybody reads.
unplanned_failure() {
  not_uploaded \
    "The R8 mapping step failed (exit $1) before the upload. Android Java and Kotlin frames from this build will NOT deobfuscate." \
    "The step failed with exit \`$1\` on the Android build of \`${SENTRY_RELEASE:-unknown}\`, before the mapping was sent. The job log has the failing command."
}
trap 'unplanned_failure "$?"; exit 0' ERR

# Whether R8 ran, not which platform this is - so a job that never minified
# leaves without fetching anything. But "no mapping" means two different things
# and only one of them is fine: a job that built no APK never ran R8, while an
# Android job with no mapping is #343 again, and a quiet exit there leaves a
# summary identical to a correct macOS run's.
#
# The variant name is in that path, so a flavour added later moves it and this
# is what notices. `android/app/build.gradle.kts` derives the same fact rather
# than naming `release`; this cannot, so it checks.
if [[ ! -f "$mapping" ]]; then
  shopt -s nullglob
  android_apks=("$dist"/*_android_*.apk)
  shopt -u nullglob
  if (( ${#android_apks[@]} > 0 )); then
    not_uploaded \
      "This job built Android APKs but no R8 mapping was found at ${mapping}. Their Java and Kotlin frames will NOT deobfuscate." \
      "Android APKs were built for \`${SENTRY_RELEASE:-unknown}\`, but there is no mapping at \`${mapping}\`. Either R8 did not run, or its output moved - the variant name is in that path."
  fi
  exit 0
fi

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  # The debug-files step in the same action already said this, for the same
  # missing secret. It always runs and always reports, so this stays quiet
  # rather than saying it twice.
  exit 0
fi

# Read from a built APK, which is the only copy that matters: an event carries
# the UUID its APK shipped with, so a mapping filed under any other is a
# mapping nothing points at. `verify_apks.sh` has already refused the build if
# this is absent or inconsistent, so a miss here is a miss in whatever changed
# between the two.
apk=""
shopt -s nullglob
for candidate in "$dist"/*_android_universal.apk; do
  apk="$candidate"
  break
done
shopt -u nullglob

if [[ -z "$apk" ]]; then
  not_uploaded \
    "No universal APK in ${dist}, so the R8 mapping's UUID could not be read. Android Java frames from this build will NOT deobfuscate." \
    "R8 wrote a mapping for \`${SENTRY_RELEASE:-unknown}\` but no universal APK was found to read its UUID from, so the mapping was not sent."
  exit 0
fi

# `|| true` on the read, so a missing entry reaches the branch below instead of
# the trap: absent and present-but-unusable are one problem with one fix, and
# both want this message. The pattern is verify_apks.sh's, so a malformed value
# - or the comma-separated pair the key's plural name allows - is named here
# rather than inside sentry-cli.
props="$(unzip -p "$apk" "$SENTRY_UUID_ASSET" 2>/dev/null || true)"
uuid="$(sed -nE "s/^io\.sentry\.ProguardUuids=($SENTRY_UUID_RE)\$/\1/p" <<<"$props" | head -n 1)"
if [[ -z "$uuid" ]]; then
  not_uploaded \
    "$(basename "$apk") carries no usable io.sentry.ProguardUuids, so the R8 mapping has nothing to be filed under. Android Java frames from this build will NOT deobfuscate." \
    "\`$(basename "$apk")\` carries no usable \`io.sentry.ProguardUuids\`, so the mapping could not be addressed. \`verify_apks.sh\` refuses that, so reaching this means the two disagree."
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
  echo "::error::Could not read both slugs out of ${pubspec}'s sentry: block (org '${org}', project '${project}')."
  {
    echo "### The R8 mapping was not uploaded"
    echo "\`$(basename "$pubspec")\`'s \`sentry:\` block did not yield both slugs - org \`${org:-<empty>}\`, project \`${project:-<empty>}\`. \`sentry_dart_plugin\` reads the same two lines, so this breaks every upload, not only the mapping."
  } | summary
  exit 1
fi

# SENTRY_CLI lets the test substitute a stub and keeps the suite offline. CI
# sets nothing and gets the pinned download.
cli="${SENTRY_CLI:-}"
if [[ -z "$cli" ]]; then
  cli="${RUNNER_TEMP:-/tmp}/sentry-cli"
  curl -fsSL -o "$cli" "$SENTRY_CLI_URL"
  # Its own annotation rather than the trap's: a checksum that does not match
  # is not a flaky download and should not read like one.
  if ! echo "${SENTRY_CLI_SHA256}  ${cli}" | sha256sum --check --quiet; then
    echo "::error::sentry-cli ${SENTRY_CLI_VERSION} did not match its pinned SHA256. Nothing was run and the R8 mapping was not uploaded."
    {
      echo "### The R8 mapping was not uploaded"
      echo "The pinned \`sentry-cli ${SENTRY_CLI_VERSION}\` download did not match \`${SENTRY_CLI_SHA256}\`. It was not executed. Check the release asset before changing the pin."
    } | summary
    exit 0
  fi
  chmod +x "$cli"
fi

# `exit 0` on failure, and loudly, for the reason the whole file gives: the
# release is built and must not be thrown away over Sentry. Unlike the Dart
# plugin, sentry-cli's own exit code is the whole signal - the swallowing #310
# turned on was the plugin's, one layer up from here.
if ! "$cli" proguard upload --require-one \
  --uuid "$uuid" --org "$org" --project "$project" "$mapping"; then
  not_uploaded \
    "Uploading the R8 mapping failed. Android Java and Kotlin frames from this build will NOT deobfuscate until it is re-uploaded." \
    "The Android build of \`${SENTRY_RELEASE:-unknown}\` published **without** it, so its Java and Kotlin frames will not deobfuscate. Dart and native frames are unaffected."
  {
    echo ""
    echo "Re-upload the mapping this build produced, from a machine that still has it:"
    echo '```'
    echo "sentry-cli proguard upload --uuid $uuid --org $org --project $project $mapping"
    echo '```'
  } | summary
  exit 0
fi

{
  echo "### R8 mapping uploaded"
  echo "\`$uuid\`, for the Android build of \`${SENTRY_RELEASE:-unknown}\`."
} | summary
