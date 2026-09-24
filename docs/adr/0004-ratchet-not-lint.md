# 0004. Architectural rules are ratchet tests, not lint plugins

Status: Accepted (2026-09-24)

## Context

The reference project makes `riverpod_lint` mandatory, on the argument that a
rule catching a mistake during analysis beats a rule written in prose. The
principle transfers; the specific plugin does not, since there is no Riverpod
here.

The first proposal was an import restriction: ban `package:flipperlib` inside
`lib/pages/**/widgets/**`. An independent reviewer took it apart:

- **The rule cannot be written with what the project has.** `flutter_lints`
  has no directory-scoped import restriction, and `custom_lint` is not in
  `pubspec.yaml`. The price is a new analyzer plugin plus a CI step.
- **The glob catches 5 files, not 3** — the original count used
  `lib/pages/*/widgets/`, one level deep, and missed
  `archive/browser/widgets/storage_card.dart` and
  `tools/infrared/widgets/ir_file_viewer.dart`.
- **Two of the five are correct code.** `firmware_changelog_page.dart` imports
  `flipperlib` for exactly one line — `final FlipperClient client;`, a
  constructor parameter its parent passes in. That is already the pattern
  [0002](0002-dependencies-are-passed-in.md) wants. A lint punishing it teaches
  contributors to write `// ignore:`.
- **The real smell is not an import.** It is
  `final FlipperClient _client = FlipperOneClient().get();` in
  `firmware_card.dart:34` — a widget reaching for a global. The proposed rule
  does not catch it, and would not catch the same line moved one directory up.

The project already has the right instrument. `test/log_level_budget_test.dart`
counts occurrences with the `analyzer` package — a parser rather than a regex —
and fails when a number goes the wrong way. `analyzer ^14.4.0` is a dev
dependency precisely for that.

## Decision

**Express architectural rules as ratchet tests built on `analyzer`, not as
lint plugins.**

The first one counts `FlipperOneClient()` call sites under `lib/pages/**`,
currently 24, and fails when the number rises.

A ratchet is preferred to a plugin here because it:

- needs no new package and no CI step;
- carries its reasoning in a file a person reads when it fails, rather than in
  a rule id;
- measures the thing that is actually wrong, not a proxy for it;
- tolerates a backlog by design — the existing 24 are not a build failure,
  only a floor.

## Rejected alternatives (and why)

**`custom_lint` with a directory-scoped import rule.** New analyzer plugin,
new CI step, known analyzer-version pain, for 5 sites of which 2 are correct.

**Enable more `flutter_lints` rules.** They are generic; none expresses "a
widget must not reach for the device client".

**Write it as a rule in `CLAUDE.md` and rely on review.** That is what the
prose already says. The point of this ADR is that prose is not checkable, and
three review rounds on PR #140 showed reading misses exactly this class of
thing.

## Consequences

- One more test file, and it fails with a message explaining why rather than a
  lint code.
- The number is a scoreboard: it should fall as
  [0002](0002-dependencies-are-passed-in.md) progresses, and a rise is a
  signal rather than a blocker.
- A ratchet can be gamed by making the code worse in a way it does not count —
  `test/log_level_budget_test.dart` documents exactly that hazard for its own
  number. Any new ratchet should say what it cannot see.

## Migration: what happens to legacy code

The existing 24 call sites stay. The ratchet pins them as a ceiling, not a
debt to be paid on a schedule; they go away as [0002](0002-dependencies-are-passed-in.md)
and the `flipperlib` seam make them unnecessary.
