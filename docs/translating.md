# Translating qUnleashed

For translators, and short on purpose. The repository's own
[README](../README.md#translations) covers the mechanics — where the work
happens, why a file edited here is reverted, and how a language is enabled.
This is what is useful once you are in Crowdin looking at a string.

## Your work ships as you go

Nothing waits for a language to be finished. A string you translate ships; one
nobody has reached yet falls back to English in that same screen until it is
done. So a translation is useful from its first string and there is no
threshold to clear.

The sync runs once a day, so expect your work in the app within about a day.

## `languageName` — read this one first

One string behaves unlike every other:

```
languageName = "English"
```

Translate it as **the name of your language, written in your language** —
`Deutsch`, `Русский`, `Українська`, `Polski`. Not as a translation of the word
"English".

It is what the language picker shows for your language, whatever language the
app is currently running in, so it has to be readable to someone who does not
speak that one. Left as "English", it puts a second "English" in the list.

## Placeholders

211 strings carry a placeholder in braces. **Keep every one exactly as it is,
spelling included** — the app substitutes a value at runtime, and a renamed or
dropped placeholder is a blank where a number should be, or a crash.

```
{message}: {reason}
```

Move them wherever your grammar needs: `{reason} — {message}` is fine.
`{Reason}` or `{причина}` is not.

Eighteen strings pick a form by a number:

```
{count, plural, one{1 frame} other{{count} frames}}
```

Keep the structure and the keywords (`plural`, `one`, `other`, `=0`), and use
the categories your language actually has — Russian, Ukrainian and Polish need
`few` and `many` where English needs only `one` and `other`. Crowdin shows the
right set of boxes for your language.

## Terms to leave alone

Product, protocol and file names stay in Latin script, spelled exactly as
below. They are what a user searches the web for, and several are printed by the
Flipper on its own screen, where they are not translated either.

| | |
|---|---|
| **Products** | Flipper, Flipper Zero, Unleashed, qUnleashed |
| **Protocols and features** | MIFARE, Sub-GHz, NFC, RFID, iButton, Bad USB, Infrared, DFU, BLE |
| **Tools and sources** | uFBT, `manifest.yml`, `application.fam`, CubeProgrammer, Flipper-IRDB, IRDB, GitHub |
| **Formats and acronyms** | API, SDK, USB, GIF, PNG, RAW, URL, JavaScript |
| **Addresses** | `lab.flipper.net`, OpenCycleMap, and every other URL |

Every term above is one that actually appears in `app_en.arb`; the list is not
aspirational.

Two that look like mistakes and are not. **ApertureFox** is the name behind the
project. **Non-Return-to-Zero**, in `Pulse Code Modulation
(Non-Return-to-Zero)`, is an encoding's full name — the words can be translated,
but prefer whatever your language's technical writing already uses.

Where your language normally transliterates a name of this kind, say so in a
Crowdin comment rather than deciding alone. It is better settled once, for
everyone.

## Context is already there

All 1308 strings carry a description saying where the string appears and what it
means, and Crowdin shows it beside the string. For a bare word it says whether
it is a verb or a noun, which English leaves ambiguous and most languages do
not.

If a description is unclear or wrong, that is worth an issue. A description that
misleads a translator is a defect in this repository, not in the translation.

## Three things the descriptions will not tell you

- **Use your language's capitalisation, not English's.** Buttons and menu items
  are Title Case in English; most languages do not do that.
- **`\n` is a line break.** Keep it where the layout needs it, which is usually
  where English has it.
- **Length matters.** A label two or three times the English is likely to be cut
  off on a phone. Where your language has a shorter form, prefer it.

## Store listing

`short_description.txt`, `full_description.txt` and the changelogs under
`fastlane/metadata/android/` are translated in Crowdin alongside the app.
`title.txt` is the product name and `video.txt` is a URL; neither is
translated.
