# The Android ABIs every release builds, in one place.
#
# android.sh names an artifact per ABI and verify_apks.sh checks the artifacts
# against these names, so the two must agree. Adding an ABI to one and not the
# other turns the next release red.
#
# This list mirrors Flutter's own `PLATFORM_ABI_LIST`, which
# `android/app/build.gradle.kts` hands to `ndk.abiFilters` - so what the APKs
# contain and what is checked here come from two places that have to say the
# same thing. Nothing couples them, but a Flutter upgrade that moves that list
# cannot pass quietly: if it gains an ABI the universal APK carries one these
# names do not cover and verify_apks.sh refuses it, and if it loses one
# android.sh cannot find the per-ABI APK it was told to copy. Both are red on
# the dev build the upgrade merges, which is early enough.
# shellcheck disable=SC2034
ANDROID_ABIS=(
  "armeabi-v7a"
  "arm64-v8a"
  "x86_64"
)
