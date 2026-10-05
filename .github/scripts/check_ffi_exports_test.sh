#!/usr/bin/env bash
# Covers check_ffi_exports.sh. That guard runs only inside auto-release.yml's
# macOS job - once per tagged release, on the one platform nobody here can run -
# so without this its logic would first be trusted at the moment it matters.
#
# The failure that matters is the quiet one: a guard that reports "present" for a
# bundle it never really inspected. So the cases below pin the *negative* side as
# hard as the positive one - a missing symbol, a symbol present in only one
# architecture slice, and a symbol list that came back empty must each be red.
#
# nm and lipo are stubbed through NM/LIPO, so this runs on the Linux CI box. The
# stubs emit the exact shape of real Mach-O output, which was captured from
# `llvm-nm -gU` on an arm64-apple-ios object.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/check_ffi_exports.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/          /'
  failures=$((failures + 1))
}

echo "check_ffi_exports.sh"

# --- fixtures ---------------------------------------------------------------

# A C source in the shape the script greps, so the symbol list is derived the
# same way it is in the repo rather than injected.
CPP="$TMP/cpp/mfkey32"
mkdir -p "$CPP"
cat >"$CPP/bridge.c" <<'EOF'
#define QUNLEASHED_EXPORT __attribute__((visibility("default"), used))
QUNLEASHED_EXPORT uint64_t qunleashed_alpha(
    uint32_t uid) { return 0; }
QUNLEASHED_EXPORT void qunleashed_beta(uint32_t x) {}
static void not_exported(void) {}
EOF

BUNDLE="$TMP/Runner.app"
mkdir -p "$BUNDLE/Frameworks/other.framework"
BIN="$BUNDLE/Runner"
: >"$BIN"
: >"$BUNDLE/Frameworks/other.framework/other"
# A non-Mach-O file beside it: the script must step over this, not choke on it.
: >"$BUNDLE/Frameworks/other.framework/Info.plist"

STUBS="$TMP/stubs"
mkdir -p "$STUBS"
cat >"$STUBS/lipo" <<'EOF'
#!/usr/bin/env bash
# Only `-archs <file>` is used by the guard.
echo "$STUB_ARCHS"
EOF
cat >"$STUBS/nm" <<'EOF'
#!/usr/bin/env bash
# Args as the guard passes them: -gU -arch <arch> <image>
arch="$3"; image="$4"
case "$image" in
  *"/Frameworks/"*) key="FRAMEWORK" ;;
  *)                key="MAIN" ;;
esac
var="STUB_${key}_${arch}"
printf '%s\n' "${!var-}"
EOF
chmod +x "$STUBS/lipo" "$STUBS/nm"

run() {
  NM="$STUBS/nm" LIPO="$STUBS/lipo" QUNLEASHED_CPP_DIR="$TMP/cpp" \
    PATH="$STUBS:$PATH" bash "$SCRIPT" "$BIN" "$BUNDLE" 2>&1
}

present="0000000000000000 T _qunleashed_alpha
0000000000000008 T _qunleashed_beta"

# --- cases ------------------------------------------------------------------

export STUB_ARCHS="arm64"
export STUB_MAIN_arm64="$present"
export STUB_FRAMEWORK_arm64=""
if out="$(run)"; then pass "both symbols in the main binary"; else fail "both symbols in the main binary" "$out"; fi

# The symbol list is derived, so this also proves the sed found both names.
if grep -q "qunleashed_alpha qunleashed_beta" <<<"$out"; then
  pass "symbol list derived from the C sources"
else
  fail "symbol list derived from the C sources" "$out"
fi

# A symbol living in an embedded framework rather than the executable still
# satisfies dyld, and must satisfy the guard - this is the hardnested case.
export STUB_MAIN_arm64="0000000000000000 T _qunleashed_alpha"
export STUB_FRAMEWORK_arm64="0000000000000008 T _qunleashed_beta"
if out="$(run)"; then pass "symbol in an embedded framework counts"; else fail "symbol in an embedded framework counts" "$out"; fi

export STUB_MAIN_arm64="0000000000000000 T _qunleashed_alpha"
export STUB_FRAMEWORK_arm64=""
if out="$(run)"; then
  fail "a missing symbol is red" "$out"
elif grep -q "qunleashed_beta" <<<"$out"; then
  pass "a missing symbol is red"
else
  fail "a missing symbol is red, naming it" "$out"
fi

# The bug this guard had before review: a fat binary where one slice kept the
# symbol and the other dropped it passed a single combined grep.
export STUB_ARCHS="x86_64 arm64"
export STUB_MAIN_x86_64="$present"
export STUB_MAIN_arm64="0000000000000000 T _qunleashed_alpha"
export STUB_FRAMEWORK_x86_64=""
export STUB_FRAMEWORK_arm64=""
if out="$(run)"; then
  fail "a symbol dropped from one slice of a fat binary is red" "$out"
elif grep -q "arm64/qunleashed_beta" <<<"$out"; then
  pass "a symbol dropped from one slice of a fat binary is red"
else
  fail "a symbol dropped from one slice is red, naming the slice" "$out"
fi

# A substring must not satisfy the check: `_qunleashed_alpha_extra` is a
# different symbol, and matching it would be the rubber stamp this guard exists
# to avoid.
export STUB_ARCHS="arm64"
export STUB_MAIN_arm64="0000000000000000 T _qunleashed_alpha_extra
0000000000000008 T _qunleashed_beta"
export STUB_FRAMEWORK_arm64=""
if out="$(run)"; then
  fail "a longer symbol does not satisfy a shorter name" "$out"
else
  pass "a longer symbol does not satisfy a shorter name"
fi

# An empty derived list means the sed stopped matching. Reporting success there
# would be worse than failing, because nothing downstream would ever notice.
export STUB_MAIN_arm64="$present"
mkdir -p "$TMP/empty"
if out="$(NM="$STUBS/nm" LIPO="$STUBS/lipo" QUNLEASHED_CPP_DIR="$TMP/empty" \
  PATH="$STUBS:$PATH" bash "$SCRIPT" "$BIN" "$BUNDLE" 2>&1)"; then
  fail "an empty symbol list is red" "$out"
else
  pass "an empty symbol list is red"
fi

# Usage.
if out="$(NM="$STUBS/nm" LIPO="$STUBS/lipo" PATH="$STUBS:$PATH" bash "$SCRIPT" "$BIN" 2>&1)"; then
  fail "a missing bundle argument is red" "$out"
else
  pass "a missing bundle argument is red"
fi

# Every case above passes QUNLEASHED_CPP_DIR, which overrides the path the
# script works out from its own location - so none of them can see that
# computation being wrong. It was: the first release this guard ran in died on
# `.github/lib/modules/cpp`, one directory short of the repo root. This case
# takes the default.
#
# The stub answers with whatever the repo currently exports, derived the same
# way the guard derives it. Listing the names here instead would be a second
# copy of the export list that goes stale the day one is added - which it did,
# and this case is where it failed. A wrong root still fails: the derivation
# comes back empty and the guard refuses rather than passing.
export STUB_ARCHS="arm64"
STUB_MAIN_arm64="$(
  grep -rhoE '^QUNLEASHED_EXPORT[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+qunleashed_[A-Za-z0-9_]+' \
    --include='*.c' "$HERE/../../lib/modules/cpp" |
    awk '{print "0000000000000000 T _" $NF}' | sort -u
)"
# Explicit: the earlier cases happen to have marked it exported already, and
# this case must not depend on their order.
export STUB_MAIN_arm64
export STUB_FRAMEWORK_arm64=""
if out="$(NM="$STUBS/nm" LIPO="$STUBS/lipo" PATH="$STUBS:$PATH" \
  bash "$SCRIPT" "$BIN" "$BUNDLE" 2>&1)"; then
  pass "the default CPP dir resolves to the repo's own sources"
else
  fail "the default CPP dir resolves to the repo's own sources" "$out"
fi

# The guard runs on macOS, whose /usr/bin/bash is 3.2. There is no 3.2 here to
# run it under, so this reads the script for the builtins that release died on
# instead. A poor substitute for running it, and better than finding out from a
# blocked release twice.
bash4_only="$(grep -nE '(^|[^[:alnum:]_])(mapfile|readarray)[[:space:]]|declare[[:space:]]+-A|\$\{[A-Za-z_][A-Za-z0-9_]*\^\^|\$\{[A-Za-z_][A-Za-z0-9_]*,,' "$SCRIPT" || true)"
if [[ -z "$bash4_only" ]]; then
  pass "no bash 4+ builtins (macOS ships bash 3.2)"
else
  fail "no bash 4+ builtins (macOS ships bash 3.2)" "$bash4_only"
fi

if ((failures > 0)); then
  echo "::error::check_ffi_exports.sh: $failures case(s) failed."
  exit 1
fi
echo "check_ffi_exports.sh: all cases passed."
