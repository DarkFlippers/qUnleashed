#!/usr/bin/env bash
# Fails the build when a Dart FFI entry point is missing from an Apple app
# bundle.
#
# This is the backstop, not the first line of defence: test/ffi_export_test.dart
# catches on every PR, on Linux, the two regressions that are visible in source
# text. What only a linked bundle can answer is whether ld64 kept the symbols -
# see the note on QUNLEASHED_EXPORT in lib/modules/cpp/mfkey32/nested_bridge.c
# for why that is in doubt on Apple and nowhere else. Dart resolves these by
# name through DynamicLibrary.process(), which nothing in `flutter test` can
# exercise: that suite never links a Mach-O.
#
# The rule it enforces is the one dyld will apply: for every architecture the
# main executable is built for, each symbol must be exported by some image the
# bundle ships for that architecture. Deliberately not "which binary" - the two
# libs are wired differently on Apple (qunleashed_mfkey32 compiles into Runner
# via the pbxproj, qunleashed_hardnested ships as a pod) and the repo disagrees
# with itself about where the pod's code ends up. A guard that does not need the
# answer cannot be wrong about it.
#
# `nm` reads the symbol table, while DynamicLibrary.process() resolves through
# dyld's export trie. They agree for the artifact checked here, which is the
# pre-strip `flutter build` product; they would not for a stripped archive, so
# do not repoint this at one without revisiting the tool.
#
# NM and LIPO are overridable so check_ffi_exports_test.sh can drive the
# comparison with stubs on a Linux runner.
set -Eeuo pipefail

NM="${NM:-nm}"
LIPO="${LIPO:-lipo}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CPP_DIR="${QUNLEASHED_CPP_DIR:-$ROOT_DIR/lib/modules/cpp}"

BINARY="${1:-}"
BUNDLE="${2:-}"
if [[ -z "$BINARY" || -z "$BUNDLE" ]]; then
  echo "::error::Usage: ${BASH_SOURCE[0]} <main-executable> <app-bundle-dir>" >&2
  exit 1
fi
if [[ ! -f "$BINARY" ]]; then
  echo "::error::Main executable not found: $BINARY" >&2
  exit 1
fi
if [[ ! -d "$BUNDLE" ]]; then
  echo "::error::App bundle not found: $BUNDLE" >&2
  exit 1
fi

for command_name in "$NM" "$LIPO"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "::error::$command_name is required." >&2
    exit 1
  fi
done

# Read the expected names off the definitions rather than restating them, so an
# entry point added to either lib is covered the day it is added.
#
# Read in a loop rather than with `mapfile`: this is the only script here that
# runs on macOS, where /usr/bin/bash is still 3.2 and has no such builtin.
SYMBOLS=()
while IFS= read -r symbol; do
  SYMBOLS+=("$symbol")
done < <(
  # `.*[^A-Za-z0-9_]` for the return type rather than one identifier: an
  # export returning a pointer spells it `const char *name(`, which is two
  # tokens and a star. The single-token version missed exactly those, and
  # the count check below is what would have caught it.
  find "$CPP_DIR" -name '*.c' -exec sed -nE \
    's/^QUNLEASHED_EXPORT[[:space:]]+.*[^A-Za-z0-9_](qunleashed_[A-Za-z0-9_]+)\(.*/\1/p' {} + |
    sort -u
)

# A regex that silently matched nothing would turn this guard into a rubber
# stamp - the exact failure it exists to prevent.
if ((${#SYMBOLS[@]} == 0)); then
  echo "::error::No QUNLEASHED_EXPORT definitions found under $CPP_DIR." >&2
  echo "::error::The guard can check nothing; fix its sed before trusting a green build." >&2
  exit 1
fi

# And one that matched *some* of them would be worse, because it looks like it
# worked. Counting the definitions a different way and comparing is the only
# thing that notices: the extraction above missed a pointer-returning export
# for as long as one existed, and the zero check above could not see it.
DEFINED=$(find "$CPP_DIR" -name '*.c' -exec grep -chE '^QUNLEASHED_EXPORT[[:space:]]' {} + |
  awk '{ total += $1 } END { print total + 0 }')
if ((${#SYMBOLS[@]} != DEFINED)); then
  echo "::error::Found $DEFINED QUNLEASHED_EXPORT definitions but extracted" \
    "${#SYMBOLS[@]} symbol names. The guard would check only some of them;" \
    "fix its sed before trusting a green build." >&2
  printf '::error::extracted: %s\n' "${SYMBOLS[*]}" >&2
  exit 1
fi

# The main executable plus every Mach-O the bundle embeds. Non-Mach-O files in
# the framework directories (Info.plist, resources) make `nm` fail and are
# skipped by the `|| true` below rather than filtered up front.
IMAGES=("$BINARY")
while IFS= read -r candidate; do
  IMAGES+=("$candidate")
done < <(find "$BUNDLE" -path '*.framework/*' -type f -print 2>/dev/null)

missing=()
for arch in $("$LIPO" -archs "$BINARY"); do
  # -g external, -U defined only: exactly what dlsym can resolve. An image
  # without this slice, or that is not Mach-O at all, contributes nothing.
  exported=""
  for image in "${IMAGES[@]}"; do
    exported+="$("$NM" -gU -arch "$arch" "$image" 2>/dev/null || true)"$'\n'
  done
  for symbol in "${SYMBOLS[@]}"; do
    # The leading underscore is Mach-O's C symbol mangling.
    if ! grep -q "[[:space:]]_${symbol}\$" <<<"$exported"; then
      missing+=("$arch/$symbol")
    fi
  done
done

if ((${#missing[@]} > 0)); then
  echo "::error::Dart FFI entry points missing from $BUNDLE: ${missing[*]}" >&2
  echo "::error::The linker dropped them, so the MIFARE recovery tools will fail" >&2
  echo "::error::at runtime. Check QUNLEASHED_EXPORT in lib/modules/cpp/*/*.c, the" >&2
  echo "::error::source entries in ios|macos/Runner.xcodeproj/project.pbxproj, and" >&2
  echo "::error::that the hardnested pod is still embedded." >&2
  exit 1
fi

echo "FFI entry points present in $BUNDLE: ${SYMBOLS[*]}"
