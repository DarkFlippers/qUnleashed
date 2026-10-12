#!/usr/bin/env bash
# Covers check_linux_abi.sh. Two of its three modes run only in
# auto-release.yml's Linux job, which only ever builds on a push or a dispatch -
# so their logic would otherwise be first exercised on the run that matters.
#
# The failure worth pinning is the quiet one. #280 shipped because nothing was
# looking; a guard that looks and always says yes leaves the project exactly
# where it was while reading as covered. So the negative cases are the point,
# and each asserts the *message* as well as the exit code - four early cases did
# not, and each passed on a mechanism other than the one its name claimed.
#
# Four things this suite holds that reading the guard will not catch, each
# written after a mutation run found the suite green without it:
#
#  * every image is read, not just the first. The objdump stub answers per file,
#    and two cases put the offending symbol in one file only.
#  * the comparison is tight. Fixtures sit one notch above the floor -
#    GLIBC_2.36, GLIBCXX_3.4.30, CXXABI_1.3.14, GLib 2.74 - because a
#    comparison slack by two patch levels passed a suite whose only bad
#    versions were far above it.
#  * `--print-floor` agrees with what is enforced rather than merely being
#    well-shaped, and README.md's table agrees with both. The cases are derived
#    from the printed numbers, never restating them.
#  * the release path. auto-release.yml calls the guard with no bundle
#    argument, so the bundle is resolved from QU_REPO_ROOT; check_ffi_exports.sh
#    died on exactly that computation in its first release while every one of
#    its tests passed an explicit path.
#
# objdump and pkg-config are pointed at stubs through the guard's own OBJDUMP
# and PKG_CONFIG overrides rather than a PATH prefix, so the suite cannot
# accidentally exercise the real tools. The stubs emit the shape real
# `objdump -T` prints, tab included, and refuse arguments the guard should not
# pass. `env -i` for the reason derive_version_test.sh gives: the developer's
# own environment must not be able to change a result.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/check_linux_abi.sh"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/          /'
  failures=$((failures + 1))
}

echo "check_linux_abi.sh"

# --- fixtures ---------------------------------------------------------------

STUBS="$TMP/stubs"
mkdir -p "$STUBS"

# Answers --modversion glib-2.0 from STUB_GLIB. An empty value stands for a
# pkg-config that cannot find the module, a real failure mode on a runner
# missing libgtk-3-dev.
cat >"$STUBS/pkg-config" <<'EOF'
#!/usr/bin/env bash
if [[ -z "${STUB_GLIB:-}" ]]; then
  echo "Package glib-2.0 was not found" >&2
  exit 1
fi
printf '%s\n' "$STUB_GLIB"
EOF

# Keyed on the image, so a guard that reads only one file is caught.
# STUB_SYMBOLS_<sanitised basename> wins over STUB_SYMBOLS_DEFAULT, and
# STUB_FAIL_<sanitised basename> makes objdump fail for that one file.
#
# The argument check holds the guard to `objdump -T <image>`: without it
# nothing says the guard passes -T, or passes a file at all.
cat >"$STUBS/objdump" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" != "-T" || $# -ne 2 ]]; then
  echo "objdump stub: expected -T <image>, got: $*" >&2
  exit 2
fi
name="${2##*/}"
key="${name//[^A-Za-z0-9]/_}"
fail="STUB_FAIL_$key"
if [[ -n "${!fail-}" ]]; then
  echo "objdump: $2: file format not recognized" >&2
  exit 1
fi
symbols="STUB_SYMBOLS_$key"
if [[ -n "${!symbols-}" ]]; then
  printf '%s\n' "${!symbols}"
else
  printf '%s\n' "${STUB_SYMBOLS_DEFAULT-}"
fi
EOF
chmod +x "$STUBS/pkg-config" "$STUBS/objdump"

# A bundle in the shape `flutter build linux` leaves behind: the binary at the
# root, libraries under lib/.
make_bundle() {
  mkdir -p "$1/lib"
  : >"$1/qunleashed"
  : >"$1/lib/libflutter_linux_gtk.so"
  : >"$1/lib/libjni.so"
}

BUNDLE="$TMP/bundle"
make_bundle "$BUNDLE"

undef() { printf '0000000000000000      DF *UND*\t0000000000000000  %s %s\n' "$1" "${2:-a_symbol}"; }
defined() { printf '0000000000001139 g    DF .text\t000000000000001b  %s %s\n' "$1" "${2:-a_symbol}"; }

# What a bundle built on the floor image really carries: these are the five
# families the first Linux build on the pinned image reported, not a guess.
# GCC_3.0 is here on purpose: libgcc_s provides it, it is in UNRULED_FAMILIES,
# and it must not turn the run red. CURL_OPENSSL_4 arrives through
# sentry-native, which links libcurl as its Linux transport. The last line is a
# *defined* symbol, which must be ignored.
ON_FLOOR="$(
  undef GLIBC_2.35 memcpy
  undef GLIBC_2.2.5 printf
  undef GLIBCXX_3.4.29 _ZNSt8__detail
  undef CXXABI_1.3.13 __cxa_throw
  undef GCC_3.0 _Unwind_Resume
  undef CURL_OPENSSL_4 curl_easy_init
  defined Base qunleashed_main
)"

# What varies between invocations, as section-scoped defaults rather than four
# runner functions: the script to run, and the bundle argument ("" means pass
# none, which is the release path).
SUT="$SCRIPT"
SUT_BUNDLE="$BUNDLE"

# run <glib> <symbols> [VAR=VALUE ...] - trailing assignments reach the stub,
# and `env` applies them in order so one can override a default above.
run() {
  local glib="$1" symbols="$2"
  shift 2
  env -i PATH="$PATH" QU_REPO_ROOT="$REPO_ROOT" \
    OBJDUMP="$STUBS/objdump" PKG_CONFIG="$STUBS/pkg-config" \
    STUB_GLIB="$glib" STUB_SYMBOLS_DEFAULT="$symbols" "$@" \
    bash "$SUT" ${SUT_BUNDLE:+"$SUT_BUNDLE"} 2>&1
}

# expect_green <name> [needle...] -- <glib> <symbols> [VAR=VALUE ...]
expect_green() {
  local name="$1" needles=()
  shift
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    needles+=("$1")
    shift
  done
  shift
  local out needle
  if ! out="$(run "$@")"; then
    fail "$name" "$out"
    return
  fi
  for needle in "${needles[@]+"${needles[@]}"}"; do
    if ! grep -qF "$needle" <<<"$out"; then
      fail "$name" "passed, but did not say '$needle':"$'\n'"$out"
      return
    fi
  done
  pass "$name"
}

# expect_red <name> <needle...> -- <glib> <symbols> [VAR=VALUE ...]
expect_red() {
  local name="$1" needles=()
  shift
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    needles+=("$1")
    shift
  done
  shift
  local out needle
  if out="$(run "$@")"; then
    fail "$name" "expected a refusal, got:"$'\n'"$out"
    return
  fi
  for needle in "${needles[@]+"${needles[@]}"}"; do
    if ! grep -qF "$needle" <<<"$out"; then
      fail "$name" "refused, but not for '$needle':"$'\n'"$out"
      return
    fi
  done
  pass "$name"
}

# --- the happy path ---------------------------------------------------------

expect_green "a bundle built on the floor image is accepted" -- 2.72.4 "$ON_FLOOR"

# 2.9 is numerically below 2.72 and lexically above it. A string comparison
# gets this backwards, and the whole script is a version comparison.
expect_green "GLib 2.9 reads as older than 2.72, not newer" -- 2.9.0 "$ON_FLOOR"

# A leading zero is an invalid octal literal to bash arithmetic. Both cases are
# here because only the second can tell: an arithmetic error inside
# `((...)) && return` is swallowed by the `&&`, so the comparison falls through
# to "within" - right for 2.08 by accident, wrong for 2.080.
expect_green "a version component with a leading zero is read as decimal" \
  -- 2.08 "$ON_FLOOR"
expect_red "a leading zero above the floor is still above it" \
  "above the 2.72 floor" -- 2.080 "$ON_FLOOR"

# --- the build environment --------------------------------------------------

# The #280 case, and the only check that can see it: the symbol table says
# nothing about GLib, so the bundle here is the *same* bundle that passes above.
# Only the build machine differs.
expect_red "GLib 2.80 on the build machine is refused" \
  "above the 2.72 floor" -- 2.80.0 "$ON_FLOOR"

# One notch above, not four: Debian 12's GLib, which the guard's comment names
# as the next version up.
expect_red "GLib 2.74 is refused, not just 2.80" \
  "above the 2.72 floor" -- 2.74.0 "$ON_FLOOR"

expect_red "a GLib version that cannot be read is refused" \
  "Could not read the glib-2.0 version" -- "" "$ON_FLOOR"

expect_red "a GLib version that is not a version is refused" \
  "Unexpected glib-2.0 version string" -- "2.72-ubuntu3" "$ON_FLOOR"

# --- the finished artifact --------------------------------------------------

expect_red "a glibc symbol above the floor is refused" \
  "needs GLIBC_2.38" -- 2.72.4 "$ON_FLOOR$(undef GLIBC_2.38 strlcpy)"

# Ubuntu 22.10's glibc: the nearest miss, and the one a slack comparison lets
# through.
expect_red "a glibc symbol one version above the floor is refused" \
  "needs GLIBC_2.36" -- 2.72.4 "$ON_FLOOR$(undef GLIBC_2.36 arc4random)"

# GCC 12's libstdc++, i.e. Debian 12 and Ubuntu 22.10.
expect_red "a libstdc++ symbol one version above the floor is refused" \
  "needs GLIBCXX_3.4.30" -- 2.72.4 "$ON_FLOOR$(undef GLIBCXX_3.4.30 _ZNSt6chrono)"

# CXXABI had no reject-direction case at all, so its floor was only ever
# exercised by being satisfied.
expect_red "a C++ ABI symbol above the floor is refused" \
  "needs CXXABI_1.3.14" -- 2.72.4 "$ON_FLOOR$(undef CXXABI_1.3.14 __cxa_call_terminate)"

# 3.3 settles the comparison before 30 is reached, so this is *within* a 3.4.29
# floor. The only shape that tells "component by component" from "last
# component only", and GLIBCXX_3.3 is a real historical tag.
expect_green "a symbol below the floor in an earlier component is accepted" \
  -- 2.72.4 "$ON_FLOOR$(undef GLIBCXX_3.3.30 _ZNSt8ios_base)"

# --- every image is read ----------------------------------------------------

# A guard that reads only the binary, or only the libraries, passes everything
# above - the stub used to answer the same thing for every file, so nothing
# could tell.
# The needle is the image and not just the symbol, because naming the bundle
# is what the first real run did and it left the question open: a reference can
# come from something built in this job or from a prebuilt library carried in,
# and which one it is decides the answer. Relative to the bundle, so the
# fixture's absolute temp path cannot make this pass by accident.
expect_red "a too-new symbol in a library only is refused, and names it" \
  "lib/libjni.so needs GLIBC_2.38" -- 2.72.4 "$ON_FLOOR" \
  "STUB_SYMBOLS_libjni_so=$ON_FLOOR$(undef GLIBC_2.38 strlcpy)"

expect_red "a too-new symbol in the app binary only is refused, and names it" \
  "qunleashed needs GLIBC_2.38" -- 2.72.4 "$ON_FLOOR" \
  "STUB_SYMBOLS_qunleashed=$ON_FLOOR$(undef GLIBC_2.38 strlcpy)"

# And on a green run, where no fault names anything, the summary is the only
# thing that can say where a family came from. Each family here lives in one
# image only, so the needles hold whichever image the guard happens to pick
# when several ask for the same family.
expect_green "the summary names an image for each family" \
  "CXXABI via qunleashed" "CURL_OPENSSL via lib/libflutter_linux_gtk.so" \
  -- 2.72.4 "$(
    undef GLIBC_2.2.5 printf
    undef CURL_OPENSSL_4 curl_easy_init
  )" "STUB_SYMBOLS_qunleashed=$(
    undef GLIBC_2.35 memcpy
    undef CXXABI_1.3.13 __cxa_throw
  )"

# objdump failing on one image is the same hole from the other side: the
# aggregate "found no references" check is satisfied by any one readable file.
expect_red "objdump failing on the app binary is refused" \
  "could not read" -- 2.72.4 "$ON_FLOOR" "STUB_FAIL_qunleashed=1"

expect_red "objdump failing on a library is refused" \
  "could not read" -- 2.72.4 "$ON_FLOOR" "STUB_FAIL_libflutter_linux_gtk_so=1"

# --- what is and is not a requirement ---------------------------------------

# A *defined* versioned symbol is the bundle's own export, not something it
# needs from the host. The on-floor fixture's `Base` line cannot prove this is
# filtered, because `Base` carries no version to misread.
expect_green "a defined symbol above the floor is not a requirement" \
  -- 2.72.4 "$ON_FLOOR$(defined GLIBC_2.38 _ZN9qunleashed)"

# The symbol name is the last field, so a mangled name carrying an
# uppercase-and-digits run must not be read as a version requirement.
expect_green "a mangled symbol name is not read as a version" \
  -- 2.72.4 "$ON_FLOOR$(undef GLIBC_2.35 _ZN4Dart12NATIVE_2_38Ev)"

# --- unruled families -------------------------------------------------------

# The default for a family nobody recorded is an error, not a warning. This job
# installs libcurl4-openssl-dev and sentry-native links libcurl, so this is
# reachable rather than hypothetical: OpenSSL 3.2 wanted on a machine with
# 3.0.2 is #280 again.
expect_red "an unrecorded family is refused, not warned about" \
  "no floor is recorded for OPENSSL" -- 2.72.4 "$ON_FLOOR$(undef OPENSSL_3.2.0 SSL_new)"

# A family carrying an underscore of its own must survive whole. The floor it
# is now checked against is what makes this provable: read as `OPENSSL` at
# version 4, the lookup misses, and the message would be the unruled-family one
# above instead of this.
expect_red "a family name with an underscore is not truncated" \
  "above the CURL_OPENSSL" \
  -- 2.72.4 "$ON_FLOOR$(undef CURL_OPENSSL_5 curl_easy_init)"

# And the one exemption still passes, and still says so.
expect_green "a family named as unruled passes and is reported" \
  "Not ruled on, by name: GCC_12.0.0" \
  -- 2.72.4 "$(undef GLIBC_2.35 memcpy)$(undef GCC_12.0.0 _Unwind_Resume)"

# --- both halves in one run -------------------------------------------------

# The failure counter exists so a build learns about the image *and* the
# symbols at once rather than over two runs.
expect_red "one run reports both halves" \
  "above the 2.72 floor" "needs GLIBC_2.38" \
  -- 2.80.0 "$ON_FLOOR$(undef GLIBC_2.38 strlcpy)"

# --- the guard cannot pass vacuously ----------------------------------------

# objdump output this parser does not understand looks exactly like a clean
# bundle. The failure that would have left #280 shipping green.
expect_red "unparseable objdump output is refused" \
  "not being parsed" -- 2.72.4 "no versioned symbols here at all"

BARE="$TMP/bare"
mkdir -p "$BARE"
: >"$BARE/qunleashed"
SUT_BUNDLE="$BARE"
expect_red "a bundle with no shared libraries is refused" \
  "Found no shared libraries" -- 2.72.4 "$ON_FLOOR"

SUT_BUNDLE="$TMP/nope"
expect_red "a bundle directory that does not exist is refused" \
  "Bundle directory not found" -- 2.72.4 "$ON_FLOOR"

MISSING_BIN="$TMP/nobinary"
mkdir -p "$MISSING_BIN/lib"
: >"$MISSING_BIN/lib/libflutter_linux_gtk.so"
SUT_BUNDLE="$MISSING_BIN"
expect_red "a bundle with no app binary is refused" \
  "App binary not found" -- 2.72.4 "$ON_FLOOR"

SUT_BUNDLE="$BUNDLE"

# --- the tools it needs -----------------------------------------------------

for tool in OBJDUMP PKG_CONFIG; do
  expect_red "a missing $tool is refused" "is required" \
    -- 2.72.4 "$ON_FLOOR" "$tool=$TMP/not-a-tool"
done

# --- the release path, which passes no bundle -------------------------------

ROOT="$TMP/root"
mkdir -p "$ROOT"
SUT_BUNDLE=""

root_run() {
  env -i PATH="$PATH" QU_REPO_ROOT="$ROOT" \
    OBJDUMP="$STUBS/objdump" PKG_CONFIG="$STUBS/pkg-config" \
    STUB_GLIB=2.72.4 STUB_SYMBOLS_DEFAULT="$ON_FLOOR" \
    bash "$SCRIPT" 2>&1
}

if out="$(root_run)"; then
  fail "no bundle at all is refused" "expected a refusal, got:"$'\n'"$out"
elif grep -qF "found 0" <<<"$out"; then
  pass "no bundle at all is refused"
else
  fail "no bundle at all is refused" "$out"
fi

make_bundle "$ROOT/build/linux/x64/release/bundle"
if out="$(root_run)"; then
  pass "the bundle is found from the repository root"
else
  fail "the bundle is found from the repository root" "$out"
fi

make_bundle "$ROOT/build/linux/arm64/release/bundle"
if out="$(root_run)"; then
  fail "two bundles are refused rather than one picked" "expected a refusal, got:"$'\n'"$out"
elif grep -qF "found 2" <<<"$out"; then
  pass "two bundles are refused rather than one picked"
else
  fail "two bundles are refused rather than one picked" "$out"
fi

SUT_BUNDLE="$BUNDLE"

# --- --check-environment ----------------------------------------------------

# The mode that runs before the build. It must not need a bundle, which is the
# whole reason it exists, and it must still refuse a too-new image.
env_run() {
  env -i PATH="$PATH" QU_REPO_ROOT="$TMP/empty" \
    OBJDUMP="$STUBS/objdump" PKG_CONFIG="$STUBS/pkg-config" \
    STUB_GLIB="$1" \
    bash "$SCRIPT" --check-environment 2>&1
}

if out="$(env_run 2.72.4)"; then
  pass "--check-environment passes with no bundle on disk"
else
  fail "--check-environment passes with no bundle on disk" "$out"
fi

if out="$(env_run 2.80.0)"; then
  fail "--check-environment refuses a too-new image" "expected a refusal, got:"$'\n'"$out"
elif grep -qF "above the 2.72 floor" <<<"$out"; then
  pass "--check-environment refuses a too-new image"
else
  fail "--check-environment refuses a too-new image" "$out"
fi

# It must not read the bundle: the stub would fail on every image if it did.
if out="$(env -i PATH="$PATH" QU_REPO_ROOT="$TMP/empty" \
  OBJDUMP="$TMP/not-a-tool" PKG_CONFIG="$STUBS/pkg-config" STUB_GLIB=2.72.4 \
  bash "$SCRIPT" --check-environment 2>&1)"; then
  pass "--check-environment does not need objdump"
else
  fail "--check-environment does not need objdump" "$out"
fi

# --- --check-runner ---------------------------------------------------------

# The pin is the fix, and this is the only thing that sees it on a pull
# request. The fixtures are workflow fragments rather than the real file, so the
# cases say what shape is being judged.
runner_workflow() {
  local path="$TMP/wf-$2.yml"
  {
    echo "jobs:"
    echo "  build-android:"
    echo "    runs-on: ubuntu-latest"
    echo "  $1:"
    echo "    name: Build Linux release"
    echo "    runs-on: $3"
    echo "  build-windows:"
    echo "    runs-on: windows-latest"
  } >"$path"
  echo "$path"
}

runner_run() {
  env -i PATH="$PATH" bash "$SCRIPT" --check-runner "$1" 2>&1
}

if out="$(runner_run "$(runner_workflow build-linux pinned ubuntu-22.04)")"; then
  pass "a pinned Ubuntu image is accepted"
else
  fail "a pinned Ubuntu image is accepted" "$out"
fi

if out="$(runner_run "$(runner_workflow build-linux floating ubuntu-latest)")"; then
  fail "ubuntu-latest is refused" "expected a refusal, got:"$'\n'"$out"
elif grep -qF "not a numbered Ubuntu image" <<<"$out"; then
  pass "ubuntu-latest is refused"
else
  fail "ubuntu-latest is refused" "$out"
fi

# A job renamed out from under the guard must be an error, not a pass - a
# missing job otherwise reads as a satisfied one.
if out="$(runner_run "$(runner_workflow build-penguin renamed ubuntu-22.04)")"; then
  fail "the job going missing is refused" "expected a refusal, got:"$'\n'"$out"
elif grep -qF "No runs-on found" <<<"$out"; then
  pass "the job going missing is refused"
else
  fail "the job going missing is refused" "$out"
fi

if out="$(runner_run "$TMP/no-such-workflow.yml")"; then
  fail "a missing workflow file is refused" "expected a refusal, got:"$'\n'"$out"
elif grep -qF "Workflow not found" <<<"$out"; then
  pass "a missing workflow file is refused"
else
  fail "a missing workflow file is refused" "$out"
fi

# And the real file, so the repository's own pin is asserted here and not only
# in a fixture.
if out="$(env -i PATH="$PATH" QU_REPO_ROOT="$REPO_ROOT" \
  bash "$SCRIPT" --check-runner 2>&1)"; then
  pass "this repository's Linux job is pinned"
else
  fail "this repository's Linux job is pinned" "$out"
fi

# --- --print-floor, and the README that quotes it ---------------------------

if ! FLOOR_OUT="$(bash "$SCRIPT" --print-floor 2>&1)"; then
  fail "--print-floor exits zero" "$FLOOR_OUT"
  FLOOR_OUT=""
fi

floor_of() { awk -v f="$1" '$1 == f { print $2 }' <<<"$FLOOR_OUT"; }

# One on the last component: the smallest step above a floor.
bump() {
  local head="${1%.*}" last="${1##*.}"
  if [[ "$head" == "$1" ]]; then
    echo $((last + 1))
  else
    echo "$head.$((last + 1))"
  fi
}

missing=()
for expected in glib-2.0 GLIBC GLIBCXX CXXABI CURL_OPENSSL; do
  [[ -n "$(floor_of "$expected")" ]] || missing+=("$expected")
done
if ((${#missing[@]} == 0)); then
  pass "--print-floor states every floor enforced"
else
  fail "--print-floor states every floor enforced" "missing: ${missing[*]}"
fi

printed_glib="$(floor_of glib-2.0)"
if [[ -n "$printed_glib" ]]; then
  expect_green "the printed GLib floor is itself accepted" -- "$printed_glib" "$ON_FLOOR"
  expect_red "one above the printed GLib floor is refused" \
    "above the $printed_glib floor" -- "$(bump "$printed_glib")" "$ON_FLOOR"
fi

for family in GLIBC GLIBCXX CXXABI CURL_OPENSSL; do
  printed="$(floor_of "$family")"
  [[ -n "$printed" ]] || continue
  expect_green "the printed $family floor is itself accepted" \
    -- 2.72.4 "$(undef "${family}_${printed}")$(undef GLIBC_2.2.5 printf)"
  over="${family}_$(bump "$printed")"
  expect_red "one above the printed $family floor is refused" \
    "needs $over" -- 2.72.4 "$ON_FLOOR$(undef "$over")"
done

# README.md promises these numbers to users, and docs/releasing.md used to say
# in prose that nothing checked the promise against the guard. This is that
# check: the floor may be raised, but not without moving the table.
README="$REPO_ROOT/README.md"
if [[ -z "$FLOOR_OUT" ]]; then
  : # already reported above
elif [[ ! -f "$README" ]]; then
  fail "README.md quotes the enforced floor" "not found: $README"
else
  linux_row="$(grep -F '| Linux |' "$README" || true)"
  if [[ -z "$linux_row" ]]; then
    fail "README.md quotes the enforced floor" \
      "no '| Linux |' row in the supported-systems table"
  else
    unquoted=()
    for pair in "glib-2.0:GLib" "GLIBC:glibc"; do
      number="$(floor_of "${pair%%:*}")"
      grep -qF "${pair##*:} $number" <<<"$linux_row" || unquoted+=("${pair##*:} $number")
    done
    if ((${#unquoted[@]} == 0)); then
      pass "README.md quotes the enforced floor"
    else
      fail "README.md quotes the enforced floor" \
        "the Linux row does not say: ${unquoted[*]}"$'\n'"row: $linux_row"
    fi
  fi
fi

if out="$(bash "$SCRIPT" --nonsense 2>&1)"; then
  fail "an unknown option is refused" "expected a refusal, got:"$'\n'"$out"
elif grep -qF "Usage:" <<<"$out"; then
  pass "an unknown option is refused"
else
  fail "an unknown option is refused" "$out"
fi

echo
if ((failures > 0)); then
  echo "::error::check_linux_abi.sh: $failures case(s) failed."
  exit 1
fi
echo "All checks passed."
