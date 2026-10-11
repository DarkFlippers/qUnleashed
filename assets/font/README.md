# Bundled fonts

Two pixel faces. Their terms differ — read both before reusing either.

## Born2bSportyV3 — `born2b-sporty-v3.ttf`

The face on every `ProgressButton` and on the about page. **Built, not
hand-edited**: the source is text in [`font/`](../../font/), one block of `#`
and `.` per glyph, and `python font/build.py` writes this file. Do not edit the
`.ttf` — CI runs `python font/build.py --check` and will reject a file the
source does not produce.

Public domain, derived from JapanYoshi's public-domain Born2bSportyV2.
[`font/README.md`](../../font/README.md) has the provenance, what changed from
V2, and what the face deliberately does not cover (CJK, Vietnamese).

`test/font_glyph_coverage_test.dart` is the app-side guard: it reads this file's
cmap and `loca` and fails if any character in any ARB file has no glyph with ink
in it. That is the test that would have caught the bug this font was forked over
— a Ukrainian button rendering `НЕМА З'ЄДНАННЯ` with a serif `Є` in the middle,
because Flutter substitutes the system face for a single missing character
without any error.

The family is named once, in `lib/components/pixel_font.dart`, because an
unresolvable `fontFamily` is not an error either — it falls back silently for
the whole string.

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
