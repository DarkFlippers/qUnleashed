# 0005. Feeds are read tolerantly by a shared mechanism, not by code generation

Status: Accepted (2026-09-24)

## Context

The project has 135 hand-written `fromJson` methods and no code generation at
all — `pubspec.yaml` has no `build_runner`, `freezed`, `json_serializable` or
`json_annotation`. Against that, the reference project's `json_serializable`
looks like an obvious upgrade.

It is not, and there is direct evidence from this repository.

Issue #133 was precisely a hand-written decoder defect: one field changing
type upstream threw out of the decode and took every version of every channel
with it, disabling the firmware page for every user at once. PR #140 spent
three review rounds removing that behaviour.

**A generated decoder has the same flaw by default.** `json_serializable`
throws on the first bad field — exactly what #140 was written to stop. Reading
entry by entry, keeping what parses and naming what did not, is not something
codegen does; it would have to be written by hand *on top of* the generated
code.

Alternatives were checked rather than assumed:

- **`dart_mappable` hooks.** `beforeDecode` and `afterDecode` intercept values
  before and after decoding, not a failure during it. The built-in hooks
  (`EmptyToNullHook`, `UnescapeNewlinesHook`, `UnmappedPropertiesHook`) are not
  for recovery. A `beforeDecode` sanitiser could filter malformed entries, but
  then the validation is hand-written again — moved, not removed — and the
  report of what was dropped is lost.
- **Schema-first generation** (`openapi_generator`, `quicktype`). Both live
  feeds are third-party and carry no schema version. There is nothing to
  generate from.
- **`freezed`.** Same strictness, plus an analyzer-version conflict the
  reference project documents in its own notes.

What #140 actually produced is reusable: `_each`, `_text`, `_presentation`,
and a list of what was skipped. Each decoder above them is ~20 lines saying
which fields are required.

## Decision

**Keep hand-written decoding, and extract the mechanism so it is written once
rather than per decoder.**

`_each`, `_text`, `_presentation` and the skip list move out of
`lib/pages/devices/firmware/directory.dart` into a shared place. Every rule
they encode is domain-free:

- a list that is missing, is not a list, or produced nothing from entries it
  had, is unreadable at that level;
- an explicit `null` is the feed's own answer and means empty;
- a required scalar is a non-blank trimmed string;
- a shown-only field falls back and is still named.

The firmware-specific part — which fields are load-bearing, and when a partial
read becomes a failure — stays at the call site.

Issues #137 and #138 are where this pays next: `dartufbt` decodes the **same**
`directory.json` all-or-nothing, and the apps catalog loses a whole page of
apps to one bad field.

## Rejected alternatives (and why)

**`json_serializable`.** Throws on the first bad field. That is defect #133.

**`dart_mappable` with a sanitiser hook.** Moves the hand-written validation
rather than removing it, and loses the record of what was dropped — which is
the part a maintainer needs to diff a feed against.

**Leave each decoder to itself.** That is the state that produced #133, #137
and #138: three instances of one defect, in three places, found separately.

## Consequences

- No `build_runner` enters the project, so nothing to run before the code
  compiles and no generated files to gitignore or explain.
- New decoders are short, and the tolerance rules cannot drift between them.
- The mechanism becomes load-bearing for several features, so it needs tests
  of its own — PR #140 left 61 mutations of it, all caught, and that set moves
  with it.
- A contributor meets a local helper rather than a familiar package. That is a
  real cost, and the reason this ADR exists is to explain it in one place.

## Migration: what happens to legacy code

The other 134 `fromJson` methods stay as they are. They are converted only
when something is already being fixed in them — #137 and #138 are the two
places where that is already true.
