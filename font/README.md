# Born2bSportyV3

A pixel face for small screens and big buttons. Public domain.

It is a derivative of **Born2bSportyV2 by JapanYoshi**, which is public domain —
the [u8g2 font credits](https://github.com/olikraus/u8g2/wiki/fntgrpjapanyoshi)
record it as `Born2bSportyV2 by JapanYoshi — license : (Public Domain)`. V3
started from [u8g2's
`Born2bSportyV2.ttf`](https://github.com/olikraus/u8g2/blob/master/tools/font/ttf/Born2bSportyV2.ttf),
md5 `cdd8a53b6e378484bf5003d54fe35c7b`. V3 is public domain too, and says so in
its own name table.

Do not confuse V2 with **Born2bSporty FS**, a separate later FontForge revision
given away under conflicting terms (SIL OFL on some sites, personal use only on
others). This is not derived from that one.

## The source is text

`src/born2b-sporty-v3.pixelfont` is the font. Every glyph is a block of `#` and
`.` on the face's own 64-unit pixel grid:

```
glyph afii10026 9 1 0
  ##..####
  ##..####
  ##..####
  ##.##.##
  ##.##.##
  ##.##.##
  ####..##
  ####..##
  ####..##
```

That is `И`. Changing a letter is a one-character diff that a reviewer can read,
rather than 55 KB of opaque binary nobody can check. The `.ttf` is built from it
and committed, so nothing has to run before the app compiles.

```bash
python font/build.py              # build assets/font/born2b-sporty-v3.ttf
python font/build.py --check      # fail if the committed .ttf is out of date
python font/build.py --output /tmp/try.ttf
```

Needs `pip install fonttools`, and must run from the repository root. The build
is deterministic — the same source always produces the same bytes, which is what
makes `--check` meaningful. CI runs it.

The builder reads every glyph back after drawing it and refuses to write a font
whose glyphs are not the drawings they came from, so a bug in the rectangle
decomposition cannot produce a letter that is subtly wrong.

## What V3 changed from V2

| | |
|---|---|
| Ukrainian | added `Є є І і Ї ї Ґ ґ` |
| Belarusian | added `Ў ў` |
| Macedonian | added `Ѕ ѕ Ѓ ѓ Ќ ќ` |
| Macedonian and Bulgarian | added `Ѐ ѐ Ѝ ѝ` |
| Romanian | added `Ș ș Ț ț` |
| Punctuation | added `– — … • → − ✓` and `“ ” ‘ ’ ʼ` |
| `/` and `\` | redrawn |
| `И и Й й` | redrawn |

Serbian is **not** in that list: its own letters (`Ђ Ј Љ Њ Ћ Џ`) were already in
V2.

Some additions are reuses rather than new drawings. `І і Ї ї Ѕ ѕ` are the Latin
`I i Ï ï S s` shapes, which is what they are. `− ‘ ’ ʼ “ ”` get the straight
ASCII hyphen and quotes, so a translator who types one does not get a single
character in a different face. `Ș ș Ț ț` reuse `Ş ş Ţ ţ`, whose mark is the
**same artwork as `Ç`'s cedilla** — at six by nine the face has one shape for
cedilla and comma-below, so Romanian gets an approximation rather than the
correct comma-below form.

### The two redraws

`/` and `\` were a zig-zag: two vertical bars joined by one horizontal jog, a
single step across ten rows, which reads as a lightning bolt. They are
staircases now, one column per two rows.

`И и Й й` were two stems with a full-height vertical bar between them and a wedge
glued to the top of it on the right and the bottom on the left — three heavy
verticals in an eight pixel box, and the one glyph in the Cyrillic set that read
as a blob. Stepped now, three rows per step, merging with the left stem at the
bottom and the right stem at the top. The face mostly avoids diagonals (`N`, `М`,
`Ж` and `Х` are stems plus a bridge), so this was not a free choice; the
precedent is `К`, which steps a column per row.

## What it does not cover

- **Han, kana, Hangul, Arabic, Hebrew, Thai, Devanagari** — nothing. Han alone
  is 20,992 codepoints. Software using this face for those scripts needs a
  fallback, not more drawings.
- **Vietnamese** — 94 of its 134 precomposed letters are missing. The ascender
  is 768 units, three pixel rows above cap height, and a single acute already
  uses all three; a stacked pair like `Ế` needs four or five, so adding them
  means raising the ascender for every glyph.
- **`ẞ`** — never produced by Dart's `toUpperCase()`, which uses simple case
  mapping, so an uppercased German label keeps the `ß` the face already has.

## Notes for anyone reusing this

535 codepoints, 522 glyphs, 1024 units per em, 64 units per pixel. Ascender 768,
descender −256, cap height 576, x-height 512. No kerning, no `GPOS`/`GSUB`, no
hinting instructions. Rebuilt from source, it carries no `gasp`, `cvt` or `GDEF`
table — all four were inert in V2, and Skia ignores `gasp` entirely.

This directory is self-contained and is meant to move to a repository of its own.
