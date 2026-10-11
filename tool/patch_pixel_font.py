#!/usr/bin/env python3
"""Build Born2bSportyV3, the font qUnleashed draws its buttons in.

V3 is our derivative of JapanYoshi's public-domain Born2bSportyV2 (see
`assets/font/README.md`). V2 is the face on every `ProgressButton`, and it
shipped without the letters Ukrainian needs, without typographic punctuation
the ARB files already use, and with a solidus drawn as a zig-zag rather than a
diagonal. Flutter papers over a missing glyph by substituting the system face
for that one character, so a Ukrainian button read `НЕМА З'<serif Є>ДНАННЯ`.

The build always starts from the vendored pristine V2 beside this script,
never from its own output. That is what makes `--check` mean something: a
rebuild from V3 would only ask whether the file is a fixed point of `build()`,
and since `build()` only ever adds glyphs and cmap entries, deleting a
declaration below would leave the committed font unchanged and `--check`
green. From V2, a deleted declaration is a byte difference.

    python tool/patch_pixel_font.py            # write assets/font/born2b-sporty-v3.ttf
    python tool/patch_pixel_font.py --check    # fail if that file is out of date
    python tool/patch_pixel_font.py --output /tmp/try.ttf   # build somewhere else

Needs `pip install fonttools`, and must run from the repository root. It is not
part of the app build; the built .ttf is committed. CI runs `--check`, and
`test/font_glyph_coverage_test.dart` holds the coverage of the committed file.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

PX = 64  # one logical pixel, in font units

FONT = Path("assets/font/born2b-sporty-v3.ttf")

# The pristine upstream, vendored so a rebuild needs no network and so a
# deleted declaration shows up as a byte difference. Identical to
# https://github.com/olikraus/u8g2/blob/master/tools/font/ttf/Born2bSportyV2.ttf
UPSTREAM = Path("tool/born2b-sporty-v2-upstream.ttf")
UPSTREAM_MD5 = "cdd8a53b6e378484bf5003d54fe35c7b"

FAMILY = "Born2bSportyV3"
VERSION = "Version 003.000"
FONT_REVISION = 3.0
COPYRIGHT = (
    "Born2bSportyV3 is a derivative of Born2bSportyV2 by JapanYoshi, which is "
    "public domain. V3 is public domain too."
)
LICENSE = "Public domain. No rights reserved."
LICENSE_URL = "https://creativecommons.org/publicdomain/zero/1.0/"
DESCRIPTION = (
    "Born2bSportyV2 by JapanYoshi with the letters Ukrainian, Belarusian and "
    "Macedonian need, Romanian comma-below letters, typographic punctuation, "
    "and a solidus and reverse solidus redrawn as diagonals rather than "
    "zig-zags. Built for the qUnleashed Flipper Zero companion app."
)

# --------------------------------------------------------------------------
# Bitmaps. '#' is ink, '.' is paper, row 0 is the top row. Every row of one
# bitmap must be the same width; `parse` rejects a ragged block rather than
# padding it, because a short row is a typo and not a design.
# --------------------------------------------------------------------------

# The shipped solidus is a Z: two vertical bars joined by a horizontal jog, one
# step across ten rows. These are proper staircases, one column per two rows.
SOLIDUS = """
....##
....##
...##.
...##.
..##..
..##..
.##...
.##...
##....
##....
"""

REVERSE_SOLIDUS = """
##....
##....
.##...
.##...
..##..
..##..
...##.
...##.
....##
....##
"""

# И/и/Й/й. V2 drew the middle stroke as a full-height vertical bar between the
# two stems, with a wedge glued to the top of it on the right and to the bottom
# on the left. That is three heavy verticals in an eight pixel box, and it is
# the one letter in the Cyrillic set that reads as a blob. Redrawn as a stepped
# diagonal, three rows per step, so it merges with the left stem at the bottom
# and the right stem at the top.
#
# The face does mostly avoid diagonals - N, М, Ж and Х are stems plus a bridge -
# so this is not a free choice. The precedent is К, which steps a column per
# row; this is the same idea at a shallower cadence, which is what eight
# columns and nine rows allow. It is not a cadence the face already uses.
I_CAP = """
##..####
##..####
##..####
##.##.##
##.##.##
##.##.##
####..##
####..##
####..##
"""

I_SMALL = """
##..####
##..####
##..####
##.##.##
##.##.##
##.##.##
####..##
####..##
"""

I_SHORT_CAP = """
..####..
..####..
........
##..####
##..####
##..####
##.##.##
##.##.##
##.##.##
####..##
####..##
####..##
"""

I_SHORT_SMALL = """
..####..
..####..
........
##..####
##..####
##..####
##.##.##
##.##.##
##.##.##
####..##
####..##
"""

# Ґ/ґ: Г with the upstroke on the right end of the bar, in the two rows above
# cap height. É puts its acute in those rows too but keeps a blank row between
# mark and letter; the hook is part of the letter, so it sits flush and Ґ ends
# up one row shorter than É.
GHE_UPTURN_CAP = """
....##
....##
######
######
##....
##....
##....
##....
##....
##....
##....
"""

GHE_UPTURN_SMALL = """
....##
....##
######
######
##....
##....
##....
##....
##....
##....
"""

# → : a shaft centred on the x-height with a chevron head.
ARROW_RIGHT = """
...##..
....##.
#######
#######
....##.
...##..
"""

# ✓ : short arm down-right meeting a long arm up-right, both two pixels wide,
# six of the x-height's eight rows, starting one row above the baseline.
CHECK_MARK = """
......##
.....##.
##...##.
.##.##..
..####..
...##...
"""

BULLET = """
###
###
###
"""

ELLIPSIS = """
##.##.##
##.##.##
"""

# Two rows deep like the hyphen, and progressively wider than it: the hyphen is
# five columns, these are six and eight.
EN_DASH = """
######
######
"""

EM_DASH = """
########
########
"""

# Accents, lifted pixel for pixel off É, È and Й. `stack` places them.
ACUTE = """
.##
##.
"""

GRAVE = """
##.
.##
"""

BREVE = """
####
####
"""


def parse(art: str) -> list[list[bool]]:
    """Turn an art block into a grid. Rows must all be the same width."""
    rows = art.strip("\n").splitlines()
    if not rows:
        raise ValueError("empty bitmap")
    widths = {len(r) for r in rows}
    if len(widths) != 1:
        raise ValueError(f"ragged bitmap: row widths {sorted(widths)}")
    for row in rows:
        bad = set(row) - {"#", "."}
        if bad:
            raise ValueError(f"bitmap uses {sorted(bad)}; only '#' and '.'")
    grid = [[c == "#" for c in row] for row in rows]
    if not any(any(row) for row in grid):
        raise ValueError("bitmap has no ink")
    return grid


# --------------------------------------------------------------------------
# Reading and writing pixel glyphs
# --------------------------------------------------------------------------


def read_bitmap(font: TTFont, glyph_name: str):
    """(grid, x0, y_bottom) for a glyph whose outline sits on the pixel grid."""
    pen = RecordingPen()
    font.getGlyphSet()[glyph_name].draw(pen)
    contours: list[list[tuple[int, int]]] = []
    current: list[tuple[int, int]] = []
    for op, args in pen.value:
        if op == "moveTo":
            current = [args[0]]
        elif op == "lineTo":
            current.append(args[0])
        elif op == "closePath":
            if current:
                contours.append(current)
            current = []
        else:
            raise AssertionError(f"{glyph_name} is not a pixel glyph ({op})")
    if current:
        contours.append(current)
    if not contours:
        raise AssertionError(f"{glyph_name} is empty")

    points = [p for c in contours for p in c]
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    assert all(v % PX == 0 for v in xs + ys), f"{glyph_name} is off the pixel grid"
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)

    def inked(px: int, py: int) -> bool:
        winding = 0
        for contour in contours:
            for i, (ax, ay) in enumerate(contour):
                bx, by = contour[(i + 1) % len(contour)]
                cross = (bx - ax) * (py - ay) - (px - ax) * (by - ay)
                if ay <= py < by and cross > 0:
                    winding += 1
                elif by <= py < ay and cross < 0:
                    winding -= 1
        return winding != 0

    grid = [
        [
            inked(x0 + c * PX + PX // 2, y1 - r * PX - PX // 2)
            for c in range((x1 - x0) // PX)
        ]
        for r in range((y1 - y0) // PX)
    ]
    return grid, x0, y0


def rectangles(grid: list[list[bool]]):
    """Cover the ink with disjoint rectangles.

    Greedy, in scan order: from the first inked cell, take the whole run to its
    right, then extend that run downward while every cell of it is inked.
    """
    remaining = [row[:] for row in grid]
    rows, cols = len(grid), len(grid[0])
    out = []
    for r in range(rows):
        for c in range(cols):
            if not remaining[r][c]:
                continue
            right = c
            while right + 1 < cols and remaining[r][right + 1]:
                right += 1
            bottom = r
            while bottom + 1 < rows and all(
                remaining[bottom + 1][cc] for cc in range(c, right + 1)
            ):
                bottom += 1
            for rr in range(r, bottom + 1):
                for cc in range(c, right + 1):
                    remaining[rr][cc] = False
            out.append((c, r, right - c + 1, bottom - r + 1))
    return out


def write_bitmap(
    font: TTFont,
    glyph_name: str,
    grid,
    x0: int,
    y_bottom: int,
    *,
    create: bool,
) -> None:
    """Install `grid` as `glyph_name`.

    `create` says whether the glyph is expected to be new. A redraw that
    creates would be a typo in the glyph name silently leaving the old shape in
    place and adding an orphan alongside it; an addition that does not create
    would be overwriting a letter that is already there.
    """
    exists = glyph_name in font.getGlyphOrder()
    if create and exists:
        raise AssertionError(f"{glyph_name} already exists; it is not new")
    if not create and not exists:
        raise AssertionError(f"{glyph_name} is not in the font; check the name")

    if not any(any(row) for row in grid):
        raise AssertionError(f"{glyph_name} would have no ink")

    y_top = y_bottom + len(grid) * PX
    pen = TTGlyphPen(None)
    for col, row, width, height in rectangles(grid):
        left = x0 + col * PX
        right = left + width * PX
        top = y_top - row * PX
        bottom = top - height * PX
        # Clockwise, so every contour fills under the nonzero rule.
        pen.moveTo((left, top))
        pen.lineTo((right, top))
        pen.lineTo((right, bottom))
        pen.lineTo((left, bottom))
        pen.closePath()

    if create:
        font.setGlyphOrder(font.getGlyphOrder() + [glyph_name])
    font["glyf"][glyph_name] = pen.glyph()
    # The face's own convention, which every untouched glyph follows: the
    # advance is the drawing plus one pixel of left side bearing and nothing on
    # the right. Measure the bearing from the leftmost ink rather than assuming
    # the drawing starts at x0, so an indented bitmap cannot shift silently.
    left_ink = min(c for row in grid for c, on in enumerate(row) if on)
    font["hmtx"][glyph_name] = (x0 + len(grid[0]) * PX, x0 + left_ink * PX)


def mirrored(grid):
    return [row[::-1] for row in grid]


def stack(accent, base, *, nudge: int = 0):
    """Put `accent` above `base` with the font's one-row gap, roughly centred."""
    width = max(len(base[0]), len(accent[0]))
    offset = (width - len(accent[0])) // 2 + nudge
    top = [[False] * width for _ in range(len(accent) + 1)]
    for r, row in enumerate(accent):
        for c, ink in enumerate(row):
            if ink:
                top[r][c + offset] = True
    body = [row + [False] * (width - len(row)) for row in base]
    return top + body


# --------------------------------------------------------------------------
# What we add
# --------------------------------------------------------------------------

# Codepoints that reuse an existing glyph outright, with no new drawing.
# Cyrillic І/і/Ѕ/ѕ are the same shapes as Latin I/i/S/s. The Romanian four get
# the font's Ş/ş/Ţ/ţ, whose mark is the same artwork as Ç's cedilla - at six by
# nine there is one mark for cedilla and comma-below, so this is the usual
# approximation at this resolution rather than the correct Romanian form. The
# curly quotes and the minus get their straight ASCII equivalents; no ARB uses
# one today, and they are here so that a translator who types one does not get
# the system face for that character alone.
ALIASES = {
    0x0406: "I",  # Ukrainian І
    0x0456: "i",  # Ukrainian і
    0x0407: "Idieresis",  # Ukrainian Ї
    0x0457: "idieresis",  # Ukrainian ї
    0x0405: "S",  # Macedonian Ѕ
    0x0455: "s",  # Macedonian ѕ
    0x0218: "Scedilla",  # Romanian Ș
    0x0219: "scedilla",  # Romanian ș
    0x021A: "Tcommaaccent",  # Romanian Ț
    0x021B: "tcommaaccent",  # Romanian ț
    0x2212: "hyphen",  # minus
    0x2018: "quotesingle",
    0x2019: "quotesingle",
    0x02BC: "quotesingle",  # the apostrophe some Ukrainian keyboards produce
    0x201C: "quotedbl",
    0x201D: "quotedbl",
}

# Codepoint -> (glyph name, how to build the bitmap, source, x0, y_bottom).
# A derivation reads the source glyph as it stands at that moment, and REDRAWN
# runs first - so Ѝ and ѝ are built on the redrawn И and и, deliberately.
DERIVED = [
    # Ukrainian ------------------------------------------------------------
    (0x0404, "uni0404", "mirror", "afii10047", 64, 0),  # Є
    (0x0454, "uni0454", "mirror", "afii10095", 64, 0),  # є
    (0x0490, "uni0490", "literal", GHE_UPTURN_CAP, 64, 0),  # Ґ
    (0x0491, "uni0491", "literal", GHE_UPTURN_SMALL, 64, 0),  # ґ
    # Belarusian -----------------------------------------------------------
    (0x040E, "uni040E", "breve", "afii10037", 64, 0),  # Ў
    (0x045E, "uni045E", "breve", "afii10085", 64, -192),  # ў
    # Macedonian, and the accented forms Macedonian and Bulgarian use -------
    (0x0403, "uni0403", "acute", "afii10020", 64, 0),  # Ѓ
    (0x0453, "uni0453", "acute", "afii10068", 64, 0),  # ѓ
    (0x040C, "uni040C", "acute", "afii10028", 64, 0),  # Ќ
    (0x045C, "uni045C", "acute", "afii10076", 64, 0),  # ќ
    (0x0400, "uni0400", "grave", "afii10022", 64, 0),  # Ѐ
    (0x0450, "uni0450", "grave", "afii10070", 64, 0),  # ѐ
    (0x040D, "uni040D", "grave", "afii10026", 64, 0),  # Ѝ
    (0x045D, "uni045D", "grave", "afii10074", 64, 0),  # ѝ
    # Punctuation the ARB files already use --------------------------------
    (0x2013, "endash", "literal", EN_DASH, 64, 192),
    (0x2014, "emdash", "literal", EM_DASH, 64, 192),
    (0x2026, "ellipsis", "literal", ELLIPSIS, 64, 0),
    (0x2022, "bullet", "literal", BULLET, 64, 192),
    (0x2192, "arrowright", "literal", ARROW_RIGHT, 64, 64),
    (0x2713, "checkmark", "literal", CHECK_MARK, 64, 64),
]

# Glyphs that replace what the font already had. These run before DERIVED.
REDRAWN = [
    ("slash", SOLIDUS, 64, 0),
    ("backslash", REVERSE_SOLIDUS, 64, 0),
    ("afii10026", I_CAP, 64, 0),  # И
    ("afii10074", I_SMALL, 64, 0),  # и
    ("afii10027", I_SHORT_CAP, 64, 0),  # Й
    ("afii10075", I_SHORT_SMALL, 64, 0),  # й
]

#: Every codepoint this tool is responsible for. The Dart coverage test reads
#: this back, so a glyph added below cannot go unmonitored.
ADDED_CODEPOINTS = sorted(list(ALIASES) + [row[0] for row in DERIVED])


def build(font: TTFont) -> None:
    for glyph_name, art, x0, y_bottom in REDRAWN:
        write_bitmap(font, glyph_name, parse(art), x0, y_bottom, create=False)

    accents = {"acute": ACUTE, "grave": GRAVE, "breve": BREVE}
    for codepoint, glyph_name, how, source, x0, y_bottom in DERIVED:
        if how == "literal":
            grid = parse(source)
        elif how == "mirror":
            base, _, _ = read_bitmap(font, source)
            grid = mirrored(base)
        elif how in accents:
            base, _, _ = read_bitmap(font, source)
            # The acute hangs right of centre in É; match it.
            grid = stack(parse(accents[how]), base, nudge=1 if how == "acute" else 0)
        else:
            raise AssertionError(how)
        write_bitmap(font, glyph_name, grid, x0, y_bottom, create=True)

    for codepoint, glyph_name in ALIASES.items():
        if glyph_name not in font.getGlyphOrder():
            raise AssertionError(f"alias target {glyph_name} is not in the font")

    cmaps = [t for t in font["cmap"].tables if t.format == 4]
    assert cmaps, "expected a format 4 cmap subtable"
    for table in cmaps:
        for codepoint, glyph_name in ALIASES.items():
            table.cmap[codepoint] = glyph_name
        for codepoint, glyph_name, *_ in DERIVED:
            table.cmap[codepoint] = glyph_name
    # The third subtable is an 8 bit Macintosh one (format 6, 195 entries).
    # None of the codepoints above is representable in it, and the only glyphs
    # it names that we touch are slash and backslash, which are redrawn in
    # place - so it picks the new shapes up through the same glyph.

    name = font["name"]
    for name_id, value in (
        (0, COPYRIGHT),
        (1, FAMILY),
        (3, f"qUnleashed:{FAMILY}:{VERSION}"),
        (4, FAMILY),
        (5, VERSION),
        (6, FAMILY),
        (10, DESCRIPTION),
        (13, LICENSE),
        (14, LICENSE_URL),
    ):
        name.setName(value, name_id, 1, 0, 0)
        name.setName(value, name_id, 3, 1, 0x409)
    font["head"].fontRevision = FONT_REVISION

    os2 = font["OS/2"]
    covered = sorted(cmaps[0].cmap)
    os2.usFirstCharIndex = covered[0]
    os2.usLastCharIndex = min(covered[-1], 0xFFFF)
    os2.recalcUnicodeRanges(font)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero if the committed font differs from what this would write",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=FONT,
        help=f"where to write the built font (default {FONT})",
    )
    args = parser.parse_args()

    if not UPSTREAM.exists():
        print(
            f"{UPSTREAM} not found; run this from the repository root",
            file=sys.stderr,
        )
        return 2
    source_bytes = UPSTREAM.read_bytes()
    digest = hashlib.md5(source_bytes).hexdigest()
    if digest != UPSTREAM_MD5:
        print(
            f"{UPSTREAM} is md5 {digest}, expected {UPSTREAM_MD5}. "
            "That file is the pristine upstream and should never change.",
            file=sys.stderr,
        )
        return 2

    # recalcTimestamp off, so the same input always produces the same bytes.
    font = TTFont(UPSTREAM, recalcTimestamp=False)
    build(font)
    scratch = args.output.with_suffix(".ttf.tmp")
    font.save(scratch)
    built = scratch.read_bytes()
    scratch.unlink()

    before = args.output.read_bytes() if args.output.exists() else b""
    if built == before:
        print(f"{args.output} is up to date ({len(built)} bytes)")
        return 0
    if args.check:
        print(
            f"{args.output} is out of date. Run `python tool/patch_pixel_font.py`.",
            file=sys.stderr,
        )
        return 1
    args.output.write_bytes(built)
    print(
        f"wrote {args.output}: {len(before)} -> {len(built)} bytes, "
        f"md5 {hashlib.md5(built).hexdigest()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
