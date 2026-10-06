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
#   * -O3 matches the shipped build. FAACCRACK_OPTS overrides it for a
#     maintainer bisecting a codegen-dependent failure across levels. It is not
#     a check of the progress channel's `volatile`: the header records a probe
#     with that qualifier stripped still stopping promptly at -O3.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENGINE_DIR="$ROOT_DIR/lib/modules/cpp/faaccrack"
# pthread_shim.h lives with the hardnested lib; only the engine's Windows branch
# includes it, so this path goes unused on a Linux runner.
SHIM_DIR="$ROOT_DIR/lib/modules/cpp/hardnested"
CC="${CC:-cc}"

# A probe that asserted nothing would exit 0 and leave this green, so its own
# count has to clear a floor. Below today's figure, so a check added or removed
# does not need this edited; far above zero, which is what it is guarding.
MINIMUM_CHECKS=20

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

  "$CC" "$opt" -std=c11 -funroll-loops -w \
    -Dmain=faaccrack_cli_main \
    -I "$ENGINE_DIR" -I "$SHIM_DIR" \
    -c "$ENGINE_DIR/faaccrack.c" -o "$WORK_DIR/engine.o"

  "$CC" "$opt" -std=c11 -Wall -Wextra -Werror \
    -I "$ENGINE_DIR" -I "$SHIM_DIR" \
    "$ENGINE_DIR/test/faaccrack_abi_probe.c" "$WORK_DIR/engine.o" \
    "${THREAD_LIB[@]}" -o "$WORK_DIR/probe"

  # Explicitly, so a failure carries an annotation rather than only aborting
  # the script under `set -e`.
  if ! "$WORK_DIR/probe" | tee "$WORK_DIR/probe.log"; then
    echo "::error::faaccrack engine probe failed at $opt" >&2
    exit 1
  fi

  ran="$(sed -n 's/^PROBE [A-Z]* (\([0-9]*\) checks.*/\1/p' "$WORK_DIR/probe.log")"
  if [[ -z "$ran" || "$ran" -lt "$MINIMUM_CHECKS" ]]; then
    echo "::error::the probe reported ${ran:-no} checks, expected at least" \
      "$MINIMUM_CHECKS - it did not run what it claims to" >&2
    exit 1
  fi
done
