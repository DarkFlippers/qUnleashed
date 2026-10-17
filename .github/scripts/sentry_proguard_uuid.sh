#!/usr/bin/env bash
# Where an APK carries the identifier that ties it to an R8 mapping, and how to
# read it out.
#
# Sourced, not run. Two scripts need the same three facts and must not drift
# apart: `verify_apks.sh` refuses a build whose APKs do not carry a usable one,
# and `upload_r8_mapping.sh` files the mapping under the one the shipped APK
# has. If those two ever disagree about the asset path, the key name or what
# counts as usable, the gate passes a build the uploader cannot address - and
# the only symptom is a Java frame that stops deobfuscating, months later.
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

# sentry_proguard_uuid <apk> -> the UUID, or nothing
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
  unzip -p "$1" "$SENTRY_UUID_ASSET" 2>/dev/null \
    | sed -nE "s/^io\.sentry\.ProguardUuids=($SENTRY_UUID_RE)\$/\1/p" \
    | head -n 1 || true
}
