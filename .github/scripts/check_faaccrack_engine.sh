#!/usr/bin/env bash
# Compiles the committed SubGHz seed-recovery engine and runs its ABI probe.
#
# Why any of this exists is in the probe's own header
# (lib/modules/cpp/faaccrack/test/faaccrack_abi_probe.c). What is specific to
# running it here:
#
#   * -Dmain=, because the engine still carries its command-line entry point.
#     The library build renames it away the same way, and this is the first
#     evidence the trick works.
#   * The engine is machine-generated, so warnings about how it reads are noise;
#     it is checked by being run. The probe is hand-written and compiled
#     warnings-as-errors.
#   * -std=gnu11, which is what the CMake and the Apple podspec give the same
#     sources. Strict c11 defines __STRICT_ANSI__, and glibc then hides
#     clock_gettime, nanosleep and the pthread declarations behind it - so the
#     probe would fail to compile on a Linux runner for a reason that has
#     nothing to do with the engine.
#   * -O3 matches the shipped build. FAACCRACK_OPTS overrides it for a
#     maintainer bisecting a codegen-dependent failure across levels. It is not
#     a check of the progress channel's `volatile`: the header records a probe
#     with that qualifier stripped still stopping promptly at -O3.
#   * -DVBITS=128 and -DEXPECT_LANES to match. No -m flags are passed here, so
#     on x86 this compiles the SSE2 variant - and the shipped SSE2 object is
#     built at 128 lanes, its hardware width, which the CMake explains and
#     measures. The probe asserts the engine reports the width the build asked
#     for, so the two numbers have to move together: they are one edit, here.
#     On a non-x86 runner this is still the right pair, because 128 is also
#     NEON's width - what differs is that the shipped NEON object does not pass
#     the flag yet.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENGINE_DIR="$ROOT_DIR/lib/modules/cpp/faaccrack"
# pthread_shim.h lives with the hardnested lib; only the engine's Windows branch
# includes it, so this path goes unused on a Linux runner.
SHIM_DIR="$ROOT_DIR/lib/modules/cpp/hardnested"
CC="${CC:-cc}"

# A probe that asserted nothing would exit 0 and leave this green, so its own
# counts have to be checked - per group, not as one total. A single floor well
# below the total let the known-answer group, which is the only thing pinning
# the four mode numbers, be deleted while the count stayed comfortably above it.
# The repo already learned this: see the note in test/faaccrack_obfuscation_test.dart
# about why that file declines to add a count floor.
#
# Exact figures, so adding a check is one deliberate edit here.
EXPECTED_GROUPS="selftests=4 known-answers=32 gaps=31 refusals=17 stop=7"

if ! command -v "$CC" >/dev/null 2>&1; then
  echo "::error::$CC is required to build the faaccrack engine probe." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Windows toolchains have no libpthread: the engine takes its shim branch there.
THREAD_LIB=(-lpthread)
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW* | MSYS* | CYGWIN*) THREAD_LIB=() ;;
esac

for opt in ${FAACCRACK_OPTS:--O3}; do
  echo "--- faaccrack engine probe at $opt ---"

  "$CC" "$opt" -std=gnu11 -funroll-loops -w \
    -Dmain=faaccrack_cli_main -DVBITS=128 \
    -I "$ENGINE_DIR" -I "$SHIM_DIR" \
    -c "$ENGINE_DIR/faaccrack.c" -o "$WORK_DIR/engine.o"

  # The dispatcher and the bridge are hand-written and were compiled by nothing
  # until a tagged release: the busy gate that is the dispatcher's whole reason
  # to exist, its publication-order rule, and all five bridge exports. They are
  # built here, and the probe calls through the dispatcher so its gate is
  # covered rather than only the engine's per-variant one.
  #
  # Without FAACCRACK_MULTI_VARIANT, which is correct: one engine object is
  # built here, so the dispatcher takes its single-variant path - the same one
  # the Apple pod uses, and the only one of the two that is otherwise unbuilt
  # anywhere on a pull request.
  "$CC" "$opt" -std=gnu11 -Wall -Wextra -Werror \
    -I "$ENGINE_DIR" -I "$SHIM_DIR" \
    -c "$ENGINE_DIR/faaccrack_dispatch.c" -o "$WORK_DIR/dispatch.o"

  "$CC" "$opt" -std=gnu11 -Wall -Wextra -Werror \
    -I "$ENGINE_DIR" -I "$SHIM_DIR" \
    -c "$ENGINE_DIR/faaccrack_bridge.c" -o "$WORK_DIR/bridge.o"

  "$CC" "$opt" -std=gnu11 -Wall -Wextra -Werror -DEXPECT_LANES=128 \
    -I "$ENGINE_DIR" -I "$SHIM_DIR" \
    "$ENGINE_DIR/test/faaccrack_abi_probe.c" "$WORK_DIR/engine.o" \
    "$WORK_DIR/dispatch.o" "$WORK_DIR/bridge.o" \
    "${THREAD_LIB[@]}" -o "$WORK_DIR/probe"

  # Explicitly, so a failure carries an annotation rather than only aborting
  # the script under `set -e`.
  if ! "$WORK_DIR/probe" | tee "$WORK_DIR/probe.log"; then
    echo "::error::faaccrack engine probe failed at $opt" >&2
    exit 1
  fi

  for expected in $EXPECTED_GROUPS; do
    group="${expected%%=*}"
    want="${expected##*=}"
    got="$(sed -n "s/^PROBE GROUP $group //p" "$WORK_DIR/probe.log")"
    if [[ "$got" != "$want" ]]; then
      echo "::error::the probe ran ${got:-no} checks in the '$group' group," \
        "expected $want - it did not run what it claims to" >&2
      exit 1
    fi
  done
done
