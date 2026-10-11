# Fonts

Two pixel faces, both free to use, modify and redistribute. Neither is a
Flipper Zero trademark and neither carries a reserved font name.

## Born2bSportyV3 — `born2b-sporty-v3.ttf`

The face on every `ProgressButton` and on the about page.

**Ours.** It is a derivative of **Born2bSportyV2 by JapanYoshi**, which is
public domain — the [u8g2 font
credits](https://github.com/olikraus/u8g2/wiki/fntgrpjapanyoshi) record it as
`Born2bSportyV2 by JapanYoshi — license : (Public Domain)`, and the copy we
started from is byte-for-byte [u8g2's
`Born2bSportyV2.ttf`](https://github.com/olikraus/u8g2/blob/master/tools/font/ttf/Born2bSportyV2.ttf)
(md5 `cdd8a53b6e378484bf5003d54fe35c7b`). V3 is public domain too.

Do not confuse it with **Born2bSporty FS**, a separate later FontForge revision
sold and given away under conflicting terms (SIL OFL on some sites, personal
use only on others). We do not ship that one.

`tool/patch_pixel_font.py` builds V3 and is the only thing that should write to
the .ttf. It is idempotent, so running it twice produces the same bytes:

```bash
python tool/patch_pixel_font.py           # rebuild
python tool/patch_pixel_font.py --check   # fail if the committed file is stale
python tool/patch_pixel_font.py --from /path/to/Born2bSportyV2.ttf   # from scratch
```

### What V3 changes

V2 covers ASCII, Latin-1, Latin Extended-A, Greek and most of Cyrillic. A
character it does not have is not an error in Flutter — the system face is
substituted for that one character and the rest of the string stays in the
pixel face, so a Ukrainian button read `НЕМА З'ЄДНАННЯ` with a serif `Є` in the
middle of it. V3 adds what the app can actually print:

| | Added |
|---|---|
| Ukrainian | `Є є І і Ї ї Ґ ґ` |
| Belarusian | `Ў ў` |
| Macedonian, Serbian | `Ѕ ѕ Ѓ ѓ Ќ ќ Ѐ ѐ Ѝ ѝ` |
| Romanian | `Ș ș Ț ț` (V2 already drew `Ş ş Ţ ţ` with a comma below, which is the Romanian form, so these reuse those glyphs) |
| Punctuation | `– — … • → − ✓ " " ' '` |

It also redraws `/` and `\`. V2 drew them as a zig-zag — two vertical bars
joined by one horizontal jog, a single step across ten rows — which read as a
lightning bolt in `Syncing 3/8` and `Installing firmware… 2/41 files`. V3 draws
a proper staircase, one column per two rows.

### Still not covered, on purpose

- **Han, kana, Hangul, Arabic, Hebrew, Thai, Devanagari.** Zero glyphs, and
  20,992 Han characters is not something anyone is drawing on a 6×9 grid. If a
  CJK locale is added, the question to answer is which face `ProgressButton`
  uses for that locale — a `fontFamilyFallback`, or dropping the pixel face
  there — not which glyphs to add here.
- **Vietnamese.** 30 of its 35 tone-marked letters are missing. The stacked
  diacritics need two rows above cap height and the grid has room for two, so
  it is drawable, but it is a real design job rather than a derivation and
  Vietnamese is not a target language.
- **`ẞ`, capital sharp s.** `'ß'.toUpperCase()` is `'SS'` in Dart, so
  uppercasing a German label never produces one.

`test/font_glyph_coverage_test.dart` holds all of this in place: it reads the
cmap out of the .ttf and fails if any character in any ARB file, in a script
the font claims, has no glyph.

## GravityBold8 — `gravity-bold-8.ttf`

The large display face on the about page, from the [Gravity Pixel Font
Pack](https://jotson.itch.io/gravity-pixel-font) by jotson, the fonts used in
Gravity Ace. Free for commercial and non-commercial projects; the pack ships
BitFontMaker2 `.txt` sources specifically so the fonts can be edited and
re-exported.

It has **no Cyrillic at all** and only ASCII plus a little punctuation. Every
string set in it is a hardcoded English word (`Unleashed`, `firmware`), so
nothing localised reaches it. Anything localised that ever does will fall back
wholesale — check before using this face for new text.
