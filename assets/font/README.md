# Fonts

Two pixel faces. Their terms differ — read each section before reusing either
outside this app.

## Born2bSportyV3 — `born2b-sporty-v3.ttf`

The face on every `ProgressButton` and on the about page.

**Ours, and public domain.** It is a derivative of **Born2bSportyV2 by
JapanYoshi**, which is public domain — the [u8g2 font
credits](https://github.com/olikraus/u8g2/wiki/fntgrpjapanyoshi) record it as
`Born2bSportyV2 by JapanYoshi — license : (Public Domain)`. The file we build
from is vendored at `tool/born2b-sporty-v2-upstream.ttf` and is byte-identical
to [u8g2's
`Born2bSportyV2.ttf`](https://github.com/olikraus/u8g2/blob/master/tools/font/ttf/Born2bSportyV2.ttf)
(md5 `cdd8a53b6e378484bf5003d54fe35c7b`, which the build verifies on every
run). V3 carries that status in its own name table: no rights reserved.

Do not confuse it with **Born2bSporty FS**, a separate later FontForge revision
given away under conflicting terms (SIL OFL on some sites, personal use only on
others). We do not ship that one.

`tool/patch_pixel_font.py` builds V3 and is the only thing that should write to
the `.ttf`. It needs `pip install fonttools` and must run from the repository
root:

```bash
python tool/patch_pixel_font.py                 # rebuild
python tool/patch_pixel_font.py --check         # fail if the committed file is stale
python tool/patch_pixel_font.py --output /tmp/x.ttf   # build without touching the asset
```

The build always starts from the vendored upstream, never from its own output.
That is what makes `--check` worth running: rebuilding V3 from V3 would only
ask whether the file is a fixed point, and since the build only ever *adds*
glyphs, deleting a declaration would leave the committed font untouched and
`--check` green.

### What V3 adds

V2 covers ASCII, Latin-1, Latin Extended-A, Greek and most of Cyrillic. A
character it has not got is not an error in Flutter — the system face is
substituted for that one character and the rest of the string stays in the
pixel face, so a Ukrainian button read `НЕМА З'ЄДНАННЯ` with a serif `Є` in the
middle of it.

| | Added |
|---|---|
| Ukrainian | `Є є І і Ї ї Ґ ґ` |
| Belarusian | `Ў ў` |
| Macedonian | `Ѕ ѕ Ѓ ѓ Ќ ќ` |
| Macedonian and Bulgarian | `Ѐ ѐ Ѝ ѝ` |
| Romanian | `Ș ș Ț ț` |
| Punctuation | `– — … • → − ✓` and `“ ” ‘ ’ ʼ` |

Serbian is **not** on that list: its own letters (`Ђ Ј Љ Њ Ћ Џ`) were already in
V2.

Some of those are reuses rather than new drawings. `І і Ї ї Ѕ ѕ` are the Latin
`I i Ï ï S s` shapes, which is what they are. `− ‘ ’ ʼ “ ”` get the straight
ASCII hyphen and quotes; no ARB file contains a curly quote today, and they are
mapped so that a translator who types one does not get the system face for that
character alone. `Ș ș Ț ț` reuse `Ş ş Ţ ţ`, whose mark is the **same artwork as
`Ç`'s cedilla** — at six by nine the face draws cedilla and comma-below with one
shape, so Romanian gets an approximation, not the correct comma-below form.

### What V3 redraws

`/` and `\`. V2 drew them as a zig-zag — two vertical bars joined by one
horizontal jog, a single step across ten rows — which reads as a lightning bolt.
V3 draws a staircase, one column per two rows. The solidus does reach this face:
`recover_page.dart` builds a `ProgressButton` label as `'$done / $total'`.

`И и Й й`. V2 put a full-height vertical bar between the two stems and glued a
wedge to the top of it on the right and the bottom on the left, so the letter
was three heavy verticals in an eight pixel box — the one glyph in the Cyrillic
set that reads as a blob. V3 steps it three rows at a time, merging with the
left stem at the bottom and the right stem at the top.

The face does mostly avoid diagonals — `N`, `М`, `Ж` and `Х` are stems plus a
bridge — so this was not a free choice. The precedent is `К`, which steps a
column per row; `И` steps at a shallower cadence because eight columns and nine
rows allow no better. It is a shape the face is comfortable with, not one it
already used at this cadence.

`✓` was also enlarged, from four rows to six of the x-height's eight.

### Still not covered, on purpose

- **Han, kana, Hangul, Arabic, Hebrew, Thai, Devanagari.** Zero glyphs, and Han
  alone is 20,992 codepoints. If a CJK locale is added, the question to answer
  is which face `ProgressButton` uses for it — its `fontFamilyFallback`, or
  dropping the pixel face there — not which glyphs to draw here.
- **Vietnamese.** 94 of its 134 precomposed letters are missing; the ones
  present are only those that fall inside Latin-1 and Latin Extended-A. It is
  not merely a gap to fill: the face's ascender is 768 units, three pixel rows
  above cap height, and a single acute already uses all three. A stacked pair
  like `Ế` needs four or five, which means raising the ascender for every
  glyph.
- **`ẞ`, capital sharp s.** Dart uses simple case mapping, so `'ß'.toUpperCase()`
  is `'ß'`, not `'SS'` — an uppercased German label keeps the lowercase `ß`,
  which the face has. `ẞ` therefore never appears.

### What holds it in place

`test/font_glyph_coverage_test.dart` reads the cmap and the `loca` table out of
the `.ttf` and fails if any character in any ARB file has no glyph *with ink*,
unless a script it names is deliberately left to fall back. It also checks that
the family `pubspec.yaml` declares is the one the Dart files ask for, since an
unresolvable `fontFamily` falls back silently and wholesale.

It cannot see a **shape**, which is why `tool/patch_pixel_font_test.py` reads
every redrawn glyph back out of the built font and compares it to the bitmap it
was built from. CI runs both, plus `--check`.

## GravityBold8 — `gravity-bold-8.ttf`

The large display face on the about page, from the [Gravity Pixel Font
Pack](https://jotson.itch.io/gravity-pixel-font) by jotson, the fonts used in
Gravity Ace.

**Its terms are narrower than V3's, and are only what that page says.** In full:
"two pixel-perfect TTF fonts — as seen in the game Gravity Ace — that you can
use in your commercial or non-commercial projects and games", plus "You can
import the included .txt files back into BitFontMaker2 to edit the fonts and
re-export new versions." That covers use in a project and editing. It says
nothing about redistributing the face on its own, there is no licence file in
the pack, and the `.ttf` carries no licence record — its copyright field is just
`JohnWatson`. Treat it as bundled-with-the-app only.

It maps exactly 96 codepoints: `U+0020`–`U+007E` plus `U+00A0`. **No Cyrillic at
all.** Every string set in it is a hardcoded English word (`Unleashed`,
`firmware`), so nothing localised reaches it; anything localised that ever does
will fall back wholesale. The source page also notes it is pixel-exact only at
sizes that are multiples of 8, and `about/widgets/pixel_button.dart` renders it
at 28.
