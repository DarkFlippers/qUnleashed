# What a release's Android artifacts are called, and where things live inside
# each kind.
#
# Sourced, not run. Three scripts have to agree about these names and none of
# them can derive them: `build/android.sh` writes the files, `verify_apks.sh`
# refuses a set that is wrong, and `upload_r8_mapping.sh` reads a UUID out of
# one of each kind. A glob that drifts in one of the three does not fail
# loudly - it matches nothing, and a check or an upload is quietly skipped.
#
# Same argument as `android_abis.sh`, which exists so the ABI names the build
# writes and the ones the gate checks cannot drift apart. ADR 0017 is the
# decision that produced two kinds in the first place.
#
# `auto-release.yml` spells three of these literally and cannot help it: a
# workflow cannot source a shell file. So the globs there are a fourth copy by
# necessity, which is worth knowing before concluding this file failed at its
# job.

# The dist filenames, as globs. `_android.aab` deliberately has no second
# underscore, which is the whole reason `*_android_*` cannot reach the bundle -
# in this repository, in the release-asset upload, and in
# `action-gh-release`'s file list. ADR 0017 §3.
# shellcheck disable=SC2034
ANDROID_APK_GLOB='*_android_*.apk'
# shellcheck disable=SC2034
ANDROID_UNIVERSAL_GLOB='*_android_universal.apk'
# shellcheck disable=SC2034
ANDROID_BUNDLE_GLOB='*_android.aab'

# Where the same things sit inside each kind. An APK carries them at its root;
# an App Bundle carries them inside its base module, and only `base/` is
# checked because this app has no feature modules - `elf_page_align.py` holds
# what to decide on the day it gains one.
# shellcheck disable=SC2034
ANDROID_BUNDLE_MODULE='base'
# shellcheck disable=SC2034
APK_MANIFEST_ENTRY='AndroidManifest.xml'
# shellcheck disable=SC2034
APK_DEX_ENTRY='classes.dex'
# shellcheck disable=SC2034
BUNDLE_MANIFEST_ENTRY="$ANDROID_BUNDLE_MODULE/manifest/AndroidManifest.xml"
# shellcheck disable=SC2034
BUNDLE_DEX_ENTRY="$ANDROID_BUNDLE_MODULE/dex/classes.dex"

# R8 writes its mapping under one name, so a release that runs it twice has to
# give each run's output a name of its own. Both are basenames: the directory
# carries the variant (`.../release/...`) and each caller builds its own path.
#
# `mapping.txt` is R8's own output name and belongs to whichever invocation
# wrote it last, which is why neither of these is called that: `android.sh`
# copies each run's output to one of these two before anything reads it, so a
# reader of either name knows which artifact it describes. ADR 0017 §2.
# shellcheck disable=SC2034
R8_MAPPING_OUTPUT="mapping.txt"
# shellcheck disable=SC2034
R8_MAPPING_APK="mapping-apk.txt"
# shellcheck disable=SC2034
R8_MAPPING_BUNDLE="mapping-aab.txt"
