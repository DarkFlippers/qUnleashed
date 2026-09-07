# The Android ABIs every release builds, in one place.
#
# android.sh names an artifact per ABI and verify_apks.sh checks the artifacts
# against these names, so the two must agree. Adding an ABI to one and not the
# other turns the next release red.
# shellcheck disable=SC2034
ANDROID_ABIS=(
  "armeabi-v7a"
  "arm64-v8a"
  "x86_64"
)
