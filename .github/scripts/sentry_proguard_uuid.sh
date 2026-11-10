#!/usr/bin/env bash
# Where an Android artifact carries the identifier that ties it to an R8
# mapping, and how to read it out.
#
# Sourced, not run. Two scripts need the same facts and must not drift apart:
# `verify_apks.sh` refuses a build whose artifacts do not carry a usable one,
# and `upload_r8_mapping.sh` files each mapping under the one its artifact has.
# If those two ever disagree about the asset path, the key name or what counts
# as usable, the gate passes a build the uploader cannot address - and the only
# symptom is a Java frame that stops deobfuscating, months later.
#
# Two paths, because a release ships two artifact kinds (ADR 0017). Only the
# UUID lives here; what the artifacts are called and where their other
# contents sit is `android_artifacts.sh`.
#
# Same argument as `android_abis.sh`, which exists so that the ABI names
# `android.sh` writes and the ones `verify_apks.sh` checks cannot drift.
#
# The Sentry Gradle Plugin injects this during the build; nothing here writes
# it. #343.

# `assets/` because the plugin cannot hook manifest merging: a value derived
# from minification does not exist yet when the manifest is merged, so it
# transforms the finished assets artifact instead.
SENTRY_UUID_ASSET='assets/sentry-debug-meta.properties'

# Canonical 8-4-4-4-12 and nothing else. The key is plural -
# `io.sentry.ProguardUuids` - and the Android SDK reads it as a comma-separated
# list, so a pair matches nothing here on purpose: both readers assume exactly
# one, and a value they cannot agree on has to be refused rather than silently
# truncated to the first.
SENTRY_UUID_RE='[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'

# An App Bundle holds the same asset inside its base module, so the entry it
# is read from is not the same string in both artifacts. Named here beside the
# APK path rather than built by its callers, for the reason the whole file
# exists: the gate and the uploader must not disagree about where it lives.
SENTRY_UUID_ASSET_BUNDLE="base/$SENTRY_UUID_ASSET"

# sentry_proguard_uuid <archive> <entry> -> the UUID, or nothing
#
# `entry` is required. It used to default to the APK path, which was safe
# while an APK was the only thing anybody read; now that a bundle holds the
# same asset one level in, a caller that forgot the argument would read an
# APK's path out of a bundle, find nothing, and be told the artifact carries
# no UUID - blaming the artifact for a caller's bug. Both callers pass it.
#
# Prints nothing rather than failing, for either shape of absence - no asset,
# or an asset with no usable value - because both are one problem with one fix
# and each caller has its own way of saying so.
#
# `|| true` because `head` closing the pipe early SIGPIPEs `unzip`, which
# `pipefail` turns into a failed command and `errexit` into the caller
# abandoning its work with no message at all. Today's properties file is a few
# hundred bytes and cannot reach that; a gate and an uploader are the last two
# places to leave it standing.
sentry_proguard_uuid() {
  # Its own statement, before the pipeline, because the `|| true` below would
  # otherwise swallow it: under `set -u` an unbound `$2` inside the pipeline
  # fails that command, `|| true` makes the pipeline succeed, and the caller
  # gets an empty string - which it reports as "the artifact carries no usable
  # UUID". That is the misleading message removing the default was meant to
  # prevent, so the arity is checked where nothing can catch it.
  local archive="${1?sentry_proguard_uuid needs an archive}"
  local entry="${2?sentry_proguard_uuid needs the entry to read, and it differs between an APK and a bundle}"
  unzip -p "$archive" "$entry" 2>/dev/null \
    | sed -nE "s/^io\.sentry\.ProguardUuids=($SENTRY_UUID_RE)\$/\1/p" \
    | head -n 1 || true
}
