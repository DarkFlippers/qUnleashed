#!/usr/bin/env python3
"""Tests for `patch_pixel_font.py`, run from the repository root.

Two things need holding, and the Dart coverage test can hold neither.

The first is the SHAPES. Every commit on the branch that introduced this was
shape work - a solidus redrawn from a zig-zag to a staircase, И from a bar with
two wedges to a stepped diagonal, a check mark enlarged - and all of those
codepoints were in the font before and after. A test that asks whether a
codepoint is mapped cannot see a shape revert, so reverting the artwork would
leave the Dart test green. `test_shapes_round_trip` reads each glyph back out
of the built font and compares it to the ASCII art it was built from, which
pins the drawing in the representation a human reviews.

The second is the GUARDS. `write_bitmap` refusing an inkless grid, `parse`
refusing a ragged one, a redraw refusing a name that is not already in the
font, and `--check` noticing a deleted declaration are each the difference
between a silent wrong font and a red build - and each of them is code that
only runs when something is already wrong, which is exactly the code that rots
unnoticed. Every guard below is exercised by mutating a COPY of the tool in a
temporary directory; the repository's own files are never written.

Needs `pip install fonttools`. Run: `python tool/patch_pixel_font_test.py`.
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import patch_pixel_font as tool  # noqa: E402

from fontTools.ttLib import TTFont  # noqa: E402

FAILURES: list[str] = []


def check(ok: bool, name: str, detail: str = "") -> None:
    print(f"[{'PASS' if ok else 'FAIL'}] {name}")
    if not ok:
        if detail:
            print(f"         {detail}")
        FAILURES.append(name)


# --------------------------------------------------------------------------
# Shapes
# --------------------------------------------------------------------------


def test_shapes_round_trip() -> None:
    """Every glyph built from a literal bitmap reads back as that bitmap."""
    font = TTFont(tool.UPSTREAM, recalcTimestamp=False)
    tool.build(font)

    cases = [(name, art) for name, art, _, _ in tool.REDRAWN]
    cases += [
        (glyph, source)
        for _, glyph, how, source, _, _ in tool.DERIVED
        if how == "literal"
    ]

    for glyph_name, art in cases:
        want = tool.parse(art)
        got, _, _ = tool.read_bitmap(font, glyph_name)
        check(
            got == want,
            f"{glyph_name} reads back as the bitmap it was built from",
            f"wanted\n{render(want)}\ngot\n{render(got)}",
        )

    # Є is Э mirrored, and Ѝ must pick up the REDRAWN И rather than the
    # original - the ordering in `build` is load-bearing and easy to lose.
    mirror, _, _ = tool.read_bitmap(font, "afii10047")
    yeh, _, _ = tool.read_bitmap(font, "uni0404")
    check(yeh == tool.mirrored(mirror), "Є is Э mirrored")

    i_grave, _, _ = tool.read_bitmap(font, "uni040D")
    check(
        i_grave[3:] == tool.parse(tool.I_CAP),
        "Ѝ is built on the redrawn И, not the original",
    )


def render(grid) -> str:
    return "\n".join("".join("#" if c else "." for c in row) for row in grid)


def test_every_declared_glyph_has_ink() -> None:
    """A mapped glyph with an empty outline renders as nothing at all.

    That is worse than the missing-glyph fallback this font exists to fix: a
    missing glyph gets the system face, an empty one gets a hole.
    """
    font = TTFont(tool.UPSTREAM, recalcTimestamp=False)
    tool.build(font)
    cmap = font.getBestCmap()
    glyf = font["glyf"]
    blank = [
        f"U+{cp:04X}"
        for cp in tool.ADDED_CODEPOINTS
        if glyf[cmap[cp]].numberOfContours == 0
    ]
    check(not blank, "no codepoint this tool adds maps to a blank glyph", str(blank))


def test_added_codepoints_are_all_mapped() -> None:
    font = TTFont(tool.UPSTREAM, recalcTimestamp=False)
    tool.build(font)
    cmap = font.getBestCmap()
    missing = [f"U+{cp:04X}" for cp in tool.ADDED_CODEPOINTS if cp not in cmap]
    check(not missing, "every declared codepoint is in the cmap", str(missing))


# --------------------------------------------------------------------------
# Guards, exercised by mutating a copy of the tool
# --------------------------------------------------------------------------


class Sandbox:
    def __enter__(self) -> "Sandbox":
        self.root = Path(tempfile.mkdtemp(prefix="patch-pixel-font-test-"))
        (self.root / "tool").mkdir(parents=True)
        (self.root / "assets" / "font").mkdir(parents=True)
        shutil.copy(Path("tool/patch_pixel_font.py"), self.root / "tool")
        shutil.copy(tool.UPSTREAM, self.root / "tool")
        shutil.copy(tool.FONT, self.root / "assets" / "font")
        self.script = self.root / "tool" / "patch_pixel_font.py"
        self.pristine = self.script.read_text(encoding="utf-8")
        return self

    def __exit__(self, *exc) -> None:
        shutil.rmtree(self.root, ignore_errors=True)

    def run(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, "-I", "tool/patch_pixel_font.py", *args],
            cwd=self.root,
            capture_output=True,
            text=True,
        )

    def mutate(self, old: str, new: str) -> None:
        text = self.pristine
        if old not in text:
            raise AssertionError(f"mutation target not found: {old[:60]!r}")
        self.script.write_text(text.replace(old, new, 1), encoding="utf-8")

    def restore(self) -> None:
        self.script.write_text(self.pristine, encoding="utf-8")


def guard(box: Sandbox, name: str, old: str, new: str, args, code: int, says: str):
    box.mutate(old, new)
    result = box.run(*args)
    blob = (result.stdout + result.stderr).replace("\n", " ")
    check(
        result.returncode == code and says.lower() in blob.lower(),
        name,
        f"exit={result.returncode} (wanted {code}); said: {blob.strip()[:200]}",
    )
    box.restore()


def test_guards() -> None:
    with Sandbox() as box:
        result = box.run("--check")
        check(result.returncode == 0, "the committed font is up to date",
              (result.stdout + result.stderr).strip()[:200])

        # The reason the build starts from the vendored upstream rather than
        # from its own output: `build` only ever adds, so rebuilding from V3
        # could not see a declaration disappear.
        guard(
            box,
            "a deleted DERIVED row makes --check fail",
            '(0x2713, "checkmark", "literal", CHECK_MARK, 64, 64),',
            "",
            ["--check"],
            1,
            "out of date",
        )
        guard(
            box,
            "a deleted ALIAS makes --check fail",
            '0x0406: "I",  # Ukrainian І',
            "",
            ["--check"],
            1,
            "out of date",
        )
        guard(
            box,
            "an inkless bitmap is refused",
            'BULLET = """\n###\n###\n###\n"""',
            'BULLET = """\n...\n...\n...\n"""',
            [],
            1,
            "no ink",
        )
        guard(
            box,
            "a ragged bitmap is refused",
            'ARROW_RIGHT = """\n...##..',
            'ARROW_RIGHT = """\n...##',
            [],
            1,
            "ragged",
        )
        guard(
            box,
            "a redraw naming a glyph the font has not got is refused",
            '("afii10026", I_CAP, 64, 0),',
            '("afii1026", I_CAP, 64, 0),',
            [],
            1,
            "not in the font",
        )
        guard(
            box,
            "an addition naming a glyph that already exists is refused",
            '(0x0404, "uni0404", "mirror"',
            '(0x0404, "slash", "mirror"',
            [],
            1,
            "already exists",
        )
        guard(
            box,
            "a tampered upstream is refused",
            f'UPSTREAM_MD5 = "{tool.UPSTREAM_MD5}"',
            'UPSTREAM_MD5 = "0" * 32'.replace('"0" * 32', '"' + "0" * 32 + '"'),
            ["--check"],
            2,
            "expected",
        )

        # --output exists so that running the tool to see what it does cannot
        # quietly rewrite the asset the app ships.
        shipped = box.root / "assets" / "font" / "born2b-sporty-v3.ttf"
        before = shipped.read_bytes()
        elsewhere = box.root / "elsewhere.ttf"
        result = box.run("--output", str(elsewhere))
        check(
            result.returncode == 0
            and shipped.read_bytes() == before
            and elsewhere.exists(),
            "--output writes elsewhere and leaves the shipped font alone",
        )

        first = box.root / "a.ttf"
        second = box.root / "b.ttf"
        box.run("--output", str(first))
        box.run("--output", str(second))
        check(
            first.read_bytes() == second.read_bytes(),
            "two builds of the same input produce identical bytes",
        )


def test_upstream_is_pristine() -> None:
    digest = hashlib.md5(tool.UPSTREAM.read_bytes()).hexdigest()
    check(
        digest == tool.UPSTREAM_MD5,
        "the vendored upstream is still JapanYoshi's file",
        f"{digest} != {tool.UPSTREAM_MD5}",
    )


def main() -> int:
    if not tool.UPSTREAM.exists():
        print("run this from the repository root", file=sys.stderr)
        return 2
    test_upstream_is_pristine()
    test_added_codepoints_are_all_mapped()
    test_every_declared_glyph_has_ink()
    test_shapes_round_trip()
    test_guards()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}", file=sys.stderr)
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
