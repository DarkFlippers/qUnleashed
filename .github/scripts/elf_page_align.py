#!/usr/bin/env python3
"""Reports native libraries in an APK that cannot load on a 16 KB page device.

    elf_page_align.py <apk> <abi> [<abi>...]

Prints one `lib/<abi>/<name>.so: <reason>` line per offending entry and exits
0 when it managed to inspect every one of them, whether or not any failed -
the caller decides what a failure means. Anything that stopped it inspecting
them is exit 2 with the reason on stderr, so a broken check cannot read as a
passing one. Nothing is written to stderr on a zero exit: `verify_apks.sh`
treats a byte there as a check it cannot trust.

WHAT IS CHECKED. Play requires an app that targets Android 15 or later to
support 16 KB memory pages, and what decides that for a shared library is the
alignment its loadable segments ask for: `p_align` on its `PT_LOAD` entries.
Built with a 4 KB `max-page-size`, the segments cannot be placed on a 16 KB
page boundary and the library does not load - the process dies at `dlopen`,
which for `libapp.so` is launch.

WHAT THIS REACHES THAT THE BUILD CANNOT. `android/build.gradle.kts` already
forces the app's `ndkVersion` onto every Android subproject, so every library
compiled from source in this build - `libserialport`, the modules under
`lib/modules/cpp` - is linked by an NDK that aligns to 16 KB by default. What
no build setting can touch is a library a dependency ships already compiled:
`sentry-native-ndk` delivers prebuilt `.so` files in an AAR, and no
`max-page-size`, linker flag or NDK pin realigns a binary nobody here linked.
For those, reading the shipped program headers is the only check there is.
It covers the source-compiled ones too, which is how the Gradle pin above
gets noticed if it is ever removed - though late, on a dev build, which is
why that pin deserves a guard of its own.

The ELF segment alignment, not the zip's. Those are two different things: an
uncompressed `.so` can also be *stored* 16 KB-aligned inside the APK so the
loader maps it in place, which is AGP's `useLegacyPackaging` business and is
not what Play's requirement is about. This reads the library's own header, so
it answers the question for a compressed entry too.

THE SMALLEST `p_align`, not the largest. bionic reserves the address space by
the maximum over the `PT_LOAD`s, so the maximum is the loader's own number;
this asks the stricter question on purpose, because the segment asking for
*less* is the one that cannot be placed. The two differ only for a library
whose `PT_LOAD`s disagree, which no linker emits - measured over the 64-bit
libraries in `sentry-native-ndk` 0.16.6, every one of which asks the same
alignment on all of its two or three segments, and over the NDK's own
`libc++_shared.so`, four segments all at 0x4000. So the choice is between two
theoretical failures, and they are not symmetric: the strict reading costs a
red CI run and a message a human reads, the permissive one ships a launch
crash.

Why this exists rather than `check_elf_alignment.sh` from the NDK: that script
is not vendored here, it answers the zip-alignment question as well and so
cannot be pointed at this one, and a Python module can be driven straight from
blobs by `elf_page_align_test.sh` - which is how the shapes below are covered
at all. Nothing here needs a toolchain on PATH.

WHICH ABIs ARE JUDGED. Only the 64-bit ones, because every device with 16 KB
pages is 64-bit and `armeabi-v7a` cannot run on one at all. `ABI_BITS` names
every ABI this script knows, and one it does not is exit 2: a name nobody has
pointed it at must not be quietly left unjudged, which is what inferring
64-bitness from a single list would have done the day `android_abis.sh` gained
an ABI.

A 32-bit library is therefore fine under a 32-bit ABI and a finding under a
64-bit one, where it could not load whatever its alignment. A `.so` that is
not an ELF at all is a finding anywhere: in this repository that has a real
shape behind it, since `verify_apks.sh` already guards a `libapp.so` that is
present but a stub, and a stub is what would otherwise sail through a check
that skipped whatever it could not parse. The reverse is not claimed - a stub
that *begins* with a valid header and is padded with zeroes clears both this
and the snapshot floor.
"""

import struct
import sys
import zipfile

# The page size Play requires support for, and so the floor every PT_LOAD's
# p_align has to meet. A library may ask for more (65536 is common on arm64
# toolchains that target several page sizes at once) and that is fine: every
# 64 KB boundary is also a 16 KB one.
REQUIRED_ALIGN = 16384

PT_LOAD = 1
ELF_MAGIC = b"\x7fELF"

# Every Android ABI this script knows, and its word size. A superset of what
# `android_abis.sh` builds, because that file holds a build choice and this
# holds a platform fact - coupling them is what would let a Flutter upgrade
# add an ABI and pass quietly. `mips` and `armeabi` are long dead and cost one
# line each.
ABI_BITS = {
    "arm64-v8a": 64,
    "x86_64": 64,
    "riscv64": 64,
    "armeabi-v7a": 32,
    "armeabi": 32,
    "x86": 32,
    "mips": 32,
}

# A cap, so a multi-megabyte entry is not read into memory whole. 64 KiB is
# far past where a program header table can be: `PT_PHDR` has to lie inside
# the first `PT_LOAD`, so every linker puts the table at offset 64.
HEADER_READ = 65536


class NotAnElf(Exception):
    """Nothing in this entry says what alignment its segments need."""


class Elf32(NotAnElf):
    """A valid 32-bit ELF - legitimate on a 32-bit ABI, unloadable on a 64."""


def min_load_align(blob: bytes) -> int:
    """The smallest `p_align` over the PT_LOAD segments of a 64-bit ELF.

    `Elf32` for a 32-bit object, which the caller judges by where it sits
    rather than by a number; `NotAnElf` for anything else this cannot read a
    load alignment out of. See the module docstring for why the smallest.
    """
    if len(blob) < 64 or blob[:4] != ELF_MAGIC:
        raise NotAnElf("not an ELF file")
    if blob[4] == 1:
        raise Elf32("a 32-bit library")
    if blob[4] != 2:
        raise NotAnElf("neither a 32-bit nor a 64-bit ELF")
    if blob[5] != 1:
        # Every Android ABI is little-endian. Refusing rather than swapping
        # byte order keeps this to the one layout it is tested against.
        raise NotAnElf("not a little-endian ELF")

    phoff, = struct.unpack_from("<Q", blob, 32)
    phentsize, phnum = struct.unpack_from("<HH", blob, 54)
    if phentsize < 56:
        raise NotAnElf(f"program header entries are {phentsize} bytes, under the 56 an ELF64 needs")
    if phnum == 0:
        raise NotAnElf("no program header table")
    if phoff + phentsize * phnum > len(blob):
        raise NotAnElf(f"program header table at offset {phoff} is past the {len(blob)} bytes read")

    loads = []
    for i in range(phnum):
        base = phoff + i * phentsize
        p_type, = struct.unpack_from("<I", blob, base)
        if p_type != PT_LOAD:
            continue
        p_align, = struct.unpack_from("<Q", blob, base + 48)
        # 0 and 1 both mean "no alignment requirement", which on a 16 KB page
        # device is the misaligned case rather than a missing segment.
        loads.append(max(p_align, 1))
    if not loads:
        raise NotAnElf("no PT_LOAD segment")
    return min(loads)


def library_entries(names, abis: set) -> list:
    """The native libraries of `abis`, as `(entry, abi)` sorted by entry.

    Two shapes, because this is pointed at both artifacts a release builds. An
    APK carries `lib/<abi>/<name>.so`; an App Bundle puts the same tree inside
    its base module, `base/lib/<abi>/<name>.so`.

    Exactly those depths, which is the set bionic can load: Android extracts
    and `dlopen`s only the per-ABI directory itself, so a `.so` nested deeper
    cannot fail at runtime and is not this script's business. `base` and not
    any module name, because a bundle's other modules are not installed with
    the base - this app has none, and if it ever does, the day it gains one is
    the day to decide what a dynamic feature's libraries mean here rather than
    to have guessed now.
    """
    out = []
    for n in names:
        if not n.endswith(".so"):
            continue
        parts = n.split("/")
        if len(parts) == 3 and parts[0] == "lib":
            abi = parts[1]
        elif len(parts) == 4 and parts[0] == "base" and parts[1] == "lib":
            abi = parts[2]
        else:
            continue
        if abi in abis:
            out.append((n, abi))
    return sorted(out)


def main(argv: list) -> int:
    if len(argv) < 3:
        print("usage: elf_page_align.py <apk|aab> <abi> [<abi>...]", file=sys.stderr)
        return 2

    apk, abis = argv[1], argv[2:]
    unknown = [a for a in abis if a not in ABI_BITS]
    if unknown:
        print(
            f"could not check {apk}: unknown ABI {', '.join(sorted(set(unknown)))} - "
            "this script does not know whether a 16 KB page device can run it, so it "
            "cannot say whether its libraries' alignment matters. Add it to ABI_BITS.",
            file=sys.stderr,
        )
        return 2

    wanted = set(abis)
    try:
        with zipfile.ZipFile(apk) as z:
            seen = set()
            for name, abi in library_entries(z.namelist(), wanted):
                seen.add(abi)
                is_64 = ABI_BITS[abi] == 64
                with z.open(name) as f:
                    blob = f.read(HEADER_READ)
                try:
                    align = min_load_align(blob)
                except Elf32 as why:
                    if is_64:
                        print(f"{name}: {why} under a 64-bit ABI, which cannot load it")
                    continue
                except NotAnElf as why:
                    print(f"{name}: {why}")
                    continue
                if is_64 and align < REQUIRED_ALIGN:
                    print(
                        f"{name}: segments ask for {align}-byte alignment, "
                        f"which cannot load on a {REQUIRED_ALIGN}-byte page device"
                    )

            # A gate that found no subject has not passed; it has not run. The
            # 64-bit ABIs only: a `--split-per-abi` armeabi-v7a artifact
            # legitimately carries no 64-bit library at all.
            empty = sorted({a for a in wanted if ABI_BITS[a] == 64} - seen)
            if empty:
                print(
                    f"could not check {apk}: no native libraries for "
                    f"{', '.join(empty)}, so nothing was inspected for it",
                    file=sys.stderr,
                )
                return 2
    except (OSError, zipfile.BadZipFile) as why:
        print(f"could not read {apk}: {why}", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
