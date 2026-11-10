"""Minimal ELF objects for test fixtures. No production script imports this.

`elf_page_align.py` decides whether a release is publishable from sixty bytes
of header, so its suites have to be able to write those sixty bytes in every
shape that matters - a 32-bit object, a big-endian one, several `PT_LOAD`s
disagreeing about alignment, a table past the bytes the parser reads.

THE BUG THIS MODULE EXISTS FOR, told here once because here is where the fix
lives; the other three places that need it point at this paragraph.
`verify_apks_test.sh` used to carry its own copy of the fixture builder with
ELFCLASS64 hardcoded, so a 64-bit library went into `lib/armeabi-v7a/` and a
case named "a 4 KB-aligned 32-bit library passes" passed with no 32-bit
library in it - over a gate that reported every real 32-bit library as a
fault and would have refused every release. Two copies of a fixture rule is
how that happens, so there is one, and `for_abi` holds the half of it that
says what a real library in a given directory looks like.

Validated against a real toolchain: `llvm-readelf -h/-l` reads what `so()`
writes as a well-formed ELF, and its 32-bit output carries the same class,
data, type and machine as the NDK's own `libc++_shared.so`.

These objects have no sections, no `PT_DYNAMIC` and no code. They are a header
and a program header table - enough for an alignment check and nothing else.
"""

import struct

PT_LOAD = 1
PT_DYNAMIC = 2

# Per ELF class: the offsets of e_phoff, e_phentsize and e_phnum, the header's
# own size, a full program header entry's size, and p_align's offset within an
# entry. One table, so nothing below recomputes a class-dependent number.
_LAYOUT = {
    32: (28, 42, 44, 52, 32, 28),
    64: (32, 54, 56, 64, 56, 48),
}

# EM_ARM and EM_AARCH64: the machine each class is normally seen with on
# Android, so a fixture looks like what its directory really carries.
_MACHINE = {32: 40, 64: 183}

# Which ABIs are 32-bit. `elf_page_align.ABI_BITS` is the same knowledge for
# the script under test and is deliberately a separate statement of it: if
# these two ever disagree, a fixture stops matching the thing it is testing,
# which is what `for_abi`'s assertion is there to catch.
_ABI_CLASS = {"armeabi-v7a": 32, "armeabi": 32, "x86": 32, "mips": 32}


def for_abi(abi, **kw):
    """A library shaped like a real one in `lib/<abi>/`.

    The class comes from the ABI and is asserted afterwards, so a fixture
    cannot disagree with the directory it is written into. Every other
    argument is `so`'s.
    """
    cls = _ABI_CLASS.get(abi, 64)
    body = so(cls=cls, **kw)
    assert body[4] == (2 if cls == 64 else 1), abi
    return body


def so(
    size=0,
    aligns=(16384,),
    cls=64,
    endian="little",
    p_type=PT_LOAD,
    phnum=None,
    phentsize=None,
    phoff=None,
):
    """An ELF object whose PT_LOAD entries ask for each of `aligns`.

    `size` pads the result, because a `libapp.so` fixture has to clear the
    snapshot floor in `verify_apks.sh`. The rest build one malformed shape
    each: `cls=32` a 32-bit object, `endian="big"` an ELFDATA2MSB one,
    `p_type=PT_DYNAMIC` a table with no PT_LOAD in it, `phnum=0` no table at
    all, `phentsize` an entry too small for the class, and `phoff` a table
    beyond where the parser reads. A file cut short is the caller's slice.

    `phnum` is for emptying the table, so it is 0 or left alone; a count
    above `len(aligns)` has no alignment to write and raises.
    """
    e_phoff_at, e_phentsize_at, e_phnum_at, ehdr_size, full_entry, align_at = _LAYOUT[cls]
    pack = "<" if endian == "little" else ">"
    wide = "Q" if cls == 64 else "I"

    entry_size = full_entry if phentsize is None else phentsize
    count = len(aligns) if phnum is None else phnum
    table_at = ehdr_size if phoff is None else phoff

    header = bytearray(ehdr_size)
    header[0:4] = b"\x7fELF"
    header[4] = 2 if cls == 64 else 1
    header[5] = 1 if endian == "little" else 2
    header[6] = 1                                            # EV_CURRENT
    struct.pack_into(pack + "HH", header, 16, 3, _MACHINE[cls])  # ET_DYN
    struct.pack_into(pack + "I", header, 20, 1)              # e_version
    struct.pack_into(pack + wide, header, e_phoff_at, table_at)
    struct.pack_into(pack + "HH", header, e_phentsize_at, entry_size, count)

    # A table `phoff` says is far away has to actually be far away, or the
    # parser's bounds check would pass on bytes that happen to be there.
    body = bytes(header) + b"\0" * max(0, table_at - ehdr_size)

    for i in range(count):
        entry = bytearray(entry_size)
        # An entry too small for the class has nowhere to put p_align, which
        # is the shape `phentsize` exists to build.
        if entry_size >= full_entry:
            struct.pack_into(pack + "I", entry, 0, p_type)
            struct.pack_into(pack + wide, entry, align_at, aligns[i])
        body += bytes(entry)

    return body + b"\0" * max(0, size - len(body))
