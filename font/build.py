#!/usr/bin/env python3
"""Build Born2bSportyV3 from its text source.

`src/born2b-sporty-v3.pixelfont` is the font. Every glyph in it is a block of
`#` and `.` on the face's own 64-unit pixel grid, so a change to a letter is a
one-character diff in a pull request rather than 58 KB of opaque binary, and
the shapes can be reviewed by reading them.

    python font/build.py                 # write the .ttf the app bundles
    python font/build.py --check         # fail if that .ttf is out of date
    python font/build.py --output /tmp/x.ttf
    python font/build.py --dump cur.ttf  # regenerate the source from a .ttf

`--dump` is how the source was first made, from the font this project built by
patching JapanYoshi's public-domain Born2bSportyV2. It is kept so that path is
auditable rather than a thing that happened once; nothing in the build uses it.

Needs `pip install fonttools`. Run from the repository root. See README.md for
provenance and licence.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "src" / "born2b-sporty-v3.pixelfont"
OUTPUT = Path("assets/font/born2b-sporty-v3.ttf")

PX = 64  # one logical pixel, in font units

Grid = list[list[bool]]


# --------------------------------------------------------------------------
# The source format
# --------------------------------------------------------------------------
#
# Line-oriented, because every tool a person has reaches for lines.
#
#   upem 1024            a font-wide setting
#   name 1 Born2bSportyV3
#   glyph A 7 1 0        name, advance, origin x, origin y - all in pixels
#                        an advance that is not a whole number of pixels is
#                        written in font units with a `u`, as in `374u`
#     .####.             the drawing, indented
#   blank space 3        a glyph that is deliberately empty
#   raw .notdef 7 ...    the one glyph that is not on the pixel grid
#   map 0041 A           a codepoint
#
# Pixels rather than font units throughout: the grid is the unit the face is
# designed in, and `7` is checkable against the drawing in a way `448` is not.


def _advance(text: str) -> int:
    """`7` is seven pixels; `374u` is 374 font units, for the few that do not
    land on the grid."""
    return int(text[:-1]) if text.endswith("u") else int(text) * PX


def _advance_text(units: int) -> str:
    return str(units // PX) if units % PX == 0 else f"{units}u"


class Source:
    def __init__(self) -> None:
        self.settings: dict[str, str] = {}
        self.names: dict[int, str] = {}
        self.order: list[str] = []
        self.grids: dict[str, Grid] = {}
        self.origins: dict[str, tuple[int, int]] = {}
        self.advances: dict[str, int] = {}
        self.raw: dict[str, list[list[tuple[int, int]]]] = {}
        self.cmap: dict[int, str] = {}

    def setting(self, key: str) -> int:
        return int(self.settings[key])


def read_source(path: Path) -> Source:
    src = Source()
    current: str | None = None
    rows: list[str] = []

    def finish() -> None:
        nonlocal current, rows
        if current is None:
            return
        if not rows:
            raise ValueError(f"{current} has no drawing; use `blank` for that")
        widths = {len(r) for r in rows}
        if len(widths) != 1:
            raise ValueError(f"{current} is ragged: row widths {sorted(widths)}")
        bad = set("".join(rows)) - {"#", "."}
        if bad:
            raise ValueError(f"{current} uses {sorted(bad)}; only '#' and '.'")
        grid = [[c == "#" for c in row] for row in rows]
        if not any(any(row) for row in grid):
            raise ValueError(f"{current} has no ink; use `blank` for that")
        src.grids[current] = grid
        current, rows = None, []

    for number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.rstrip()
        if not line or line.lstrip().startswith("#") and not line.startswith(" "):
            if not line:
                finish()
            continue
        if line.startswith(" "):
            if current is None:
                raise ValueError(f"line {number}: drawing outside a glyph")
            rows.append(line.strip())
            continue
        finish()
        head, _, rest = line.partition(" ")
        try:
            if head == "glyph":
                name, advance, x0, y0 = rest.split()
                src.order.append(name)
                src.advances[name] = _advance(advance)
                src.origins[name] = (int(x0), int(y0))
                current = name
            elif head == "blank":
                name, advance = rest.split()
                src.order.append(name)
                src.advances[name] = _advance(advance)
            elif head == "raw":
                parts = rest.split()
                name, advance = parts[0], _advance(parts[1])
                numbers = [int(v) for v in parts[2:]]
                contours, point = [], []
                for i in range(0, len(numbers), 2):
                    if numbers[i] == 99999:  # contour separator
                        contours.append(point)
                        point = []
                        continue
                    point.append((numbers[i], numbers[i + 1]))
                if point:
                    contours.append(point)
                src.order.append(name)
                src.advances[name] = advance
                src.raw[name] = contours
            elif head == "map":
                codepoint, name = rest.split()
                src.cmap[int(codepoint, 16)] = name
            elif head == "name":
                name_id, _, value = rest.partition(" ")
                src.names[int(name_id)] = value
            else:
                src.settings[head] = rest
        except ValueError as error:
            raise ValueError(f"line {number}: {raw_line!r}: {error}") from error
    finish()

    missing = {n for n in src.cmap.values()} - set(src.order)
    if missing:
        raise ValueError(f"cmap names glyphs the source has not got: {sorted(missing)}")
    return src


# --------------------------------------------------------------------------
# Drawing
# --------------------------------------------------------------------------


def rectangles(grid: Grid) -> list[tuple[int, int, int, int]]:
    """Cover the ink with disjoint rectangles.

    Greedy, in scan order: from the first inked cell take the whole run to its
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


def draw(grid: Grid, x0: int, y_bottom: int):
    """A TrueType glyph for `grid`, placed with its lower left at (x0, y_bottom)."""
    pen = TTGlyphPen(None)
    top = (y_bottom + len(grid)) * PX
    for col, row, width, height in rectangles(grid):
        left = (x0 + col) * PX
        right = left + width * PX
        upper = top - row * PX
        lower = upper - height * PX
        # Clockwise, so every contour fills under the nonzero rule.
        pen.moveTo((left, upper))
        pen.lineTo((right, upper))
        pen.lineTo((right, lower))
        pen.lineTo((left, lower))
        pen.closePath()
    return pen.glyph()


def _verify_drawings(glyphs, src: Source) -> None:
    """Read every glyph back and check it is the drawing it came from.

    `rectangles` covers the ink with boxes, and a bug there would produce a
    letter that is subtly wrong rather than an error. Checking here rather than
    in a test file keeps it on the one path that matters: nobody can build a
    font without it running.
    """
    from fontTools.pens.recordingPen import RecordingPen  # noqa: PLC0415

    class _Glyphs:
        def __init__(self, table):
            self.table = table

        def __getitem__(self, name):
            return self.table[name]

    for name, grid in src.grids.items():
        pen = RecordingPen()
        glyphs[name].draw(pen, _Glyphs(glyphs))
        got = _grid_from(pen, src.origins[name], len(grid), len(grid[0]))
        if got != grid:
            drawn = "\n".join(
                "".join("#" if c else "." for c in row) for row in got
            )
            raise AssertionError(f"{name} did not survive being drawn:\n{drawn}")


def _grid_from(pen, origin, rows: int, cols: int) -> Grid:
    x0, y0 = origin
    filled = [[False] * cols for _ in range(rows)]
    current = []
    for op, args in pen.value:
        if op == "moveTo":
            current = [args[0]]
        elif op == "lineTo":
            current.append(args[0])
        elif op == "closePath":
            xs = [p[0] for p in current]
            ys = [p[1] for p in current]
            left = min(xs) // PX - x0
            right = max(xs) // PX - x0
            bottom = min(ys) // PX - y0
            top = max(ys) // PX - y0
            for row in range(rows - top, rows - bottom):
                for col in range(left, right):
                    filled[row][col] = True
            current = []
    return filled


def build(src: Source) -> TTFont:
    fb = FontBuilder(src.setting("upem"), isTTF=True)
    fb.setupGlyphOrder(src.order)
    fb.setupCharacterMap(src.cmap)

    glyphs, metrics = {}, {}
    for name in src.order:
        if name in src.grids:
            grid = src.grids[name]
            x0, y0 = src.origins[name]
            glyphs[name] = draw(grid, x0, y0)
            left_ink = min(c for row in grid for c, on in enumerate(row) if on)
            lsb = (x0 + left_ink) * PX
        elif name in src.raw:
            pen = TTGlyphPen(None)
            for contour in src.raw[name]:
                pen.moveTo(contour[0])
                for point in contour[1:]:
                    pen.lineTo(point)
                pen.closePath()
            glyphs[name] = pen.glyph()
            lsb = min(x for contour in src.raw[name] for x, _ in contour)
        else:
            glyphs[name] = TTGlyphPen(None).glyph()
            lsb = 0
        metrics[name] = (src.advances[name], lsb)

    _verify_drawings(glyphs, src)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(
        ascent=src.setting("ascender"),
        descent=src.setting("descender"),
        lineGap=src.setting("line-gap"),
    )
    fb.setupNameTable({_NAME_KEYS[k]: v for k, v in src.names.items() if k in _NAME_KEYS})
    fb.setupOS2(
        version=1,
        usWeightClass=src.setting("weight-class"),
        usWidthClass=src.setting("width-class"),
        fsType=0,
        sTypoAscender=src.setting("ascender"),
        sTypoDescender=src.setting("descender"),
        sTypoLineGap=src.setting("line-gap"),
        usWinAscent=src.setting("ascender"),
        usWinDescent=-src.setting("descender"),
    )
    fb.setupPost(
        italicAngle=0,
        underlinePosition=src.setting("underline-position"),
        underlineThickness=src.setting("underline-thickness"),
    )
    head = fb.font["head"]
    head.fontRevision = float(src.settings["revision"])
    # Pinned, and the timestamp left alone on save, so the same source always
    # produces the same bytes - which is the whole basis of `--check`.
    head.created = head.modified = int(src.settings["timestamp"])
    fb.font.recalcTimestamp = False
    fb.font["OS/2"].recalcUnicodeRanges(fb.font)
    return fb.font


# fontTools' own keys for the name ids this font sets.
_NAME_KEYS = {
    0: "copyright",
    1: "familyName",
    2: "styleName",
    3: "uniqueFontIdentifier",
    4: "fullName",
    5: "version",
    6: "psName",
    10: "description",
    13: "licenseDescription",
    14: "licenseInfoURL",
}


# --------------------------------------------------------------------------
# Dumping an existing font back to source
# --------------------------------------------------------------------------


def read_bitmap(font: TTFont, name: str):
    """(grid, x0, y_bottom) in pixels, for a rectilinear on-grid glyph."""
    pen = RecordingPen()
    font.getGlyphSet()[name].draw(pen)
    contours, current = [], []
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
            raise AssertionError(f"{name} is not rectilinear ({op})")
    if current:
        contours.append(current)
    if not contours:
        return None, 0, 0

    points = [p for c in contours for p in c]
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    if any(v % PX for v in xs + ys):
        return False, 0, 0
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
        [inked(x0 + c * PX + PX // 2, y1 - r * PX - PX // 2) for c in range((x1 - x0) // PX)]
        for r in range((y1 - y0) // PX)
    ]
    return grid, x0 // PX, y0 // PX


def dump(font: TTFont, out: Path) -> None:
    head, hhea, os2, post = font["head"], font["hhea"], font["OS/2"], font["post"]
    names = font["name"]
    lines = [
        "# Born2bSportyV3 - the source. See ../README.md for provenance and licence.",
        "#",
        "# Every drawing below is on the face's 64-unit pixel grid: one character is",
        "# one pixel. `glyph <name> <advance> <origin x> <origin y>` is in pixels too,",
        "# with the origin measured from the baseline at the left sidebearing point.",
        "#",
        "# Regenerate the .ttf with `python font/build.py`.",
        "",
        f"upem {head.unitsPerEm}",
        f"ascender {hhea.ascent}",
        f"descender {hhea.descent}",
        f"line-gap {hhea.lineGap}",
        f"weight-class {os2.usWeightClass}",
        f"width-class {os2.usWidthClass}",
        f"underline-position {post.underlinePosition}",
        f"underline-thickness {post.underlineThickness}",
        f"revision {head.fontRevision:.3f}",
        f"timestamp {head.created}",
        "",
    ]
    for name_id in sorted(_NAME_KEYS):
        value = names.getDebugName(name_id)
        if value:
            lines.append(f"name {name_id} {value}")
    lines.append("")

    hmtx = font["hmtx"]
    for name in font.getGlyphOrder():
        advance = _advance_text(hmtx[name][0])
        grid, x0, y0 = read_bitmap(font, name)
        if grid is None:
            lines += [f"blank {name} {advance}", ""]
        elif grid is False:
            pen = RecordingPen()
            font.getGlyphSet()[name].draw(pen)
            flat, contours, current = [], [], []
            for op, args in pen.value:
                if op == "moveTo":
                    current = [args[0]]
                elif op == "lineTo":
                    current.append(args[0])
                elif op == "closePath":
                    contours.append(current)
                    current = []
            for i, contour in enumerate(contours):
                if i:
                    flat += [99999, 99999]
                for x, y in contour:
                    flat += [x, y]
            lines += [f"raw {name} {advance} " + " ".join(str(v) for v in flat), ""]
        else:
            lines.append(f"glyph {name} {advance} {x0} {y0}")
            lines += ["  " + "".join("#" if c else "." for c in row) for row in grid]
            lines.append("")

    for codepoint, name in sorted(font.getBestCmap().items()):
        lines.append(f"map {codepoint:04X} {name}")
    lines.append("")

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="exit non-zero if the built font is out of date")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--dump", type=Path,
                        help="regenerate the source from this .ttf and exit")
    args = parser.parse_args()

    if args.dump:
        dump(TTFont(args.dump, recalcTimestamp=False), SOURCE)
        print(f"wrote {SOURCE} from {args.dump}")
        return 0

    if not SOURCE.exists():
        print(f"{SOURCE} not found; run this from the repository root", file=sys.stderr)
        return 2

    font = build(read_source(SOURCE))
    scratch = args.output.with_suffix(".ttf.tmp")
    scratch.parent.mkdir(parents=True, exist_ok=True)
    font.save(scratch)
    built = scratch.read_bytes()
    scratch.unlink()

    before = args.output.read_bytes() if args.output.exists() else b""
    if built == before:
        print(f"{args.output} is up to date ({len(built)} bytes)")
        return 0
    if args.check:
        print(f"{args.output} is out of date. Run `python font/build.py`.",
              file=sys.stderr)
        return 1
    args.output.write_bytes(built)
    print(f"wrote {args.output}: {len(before)} -> {len(built)} bytes, "
          f"md5 {hashlib.md5(built).hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
