# 0010. The declared SDK window is the one CI covers

Status: Accepted (2026-09-24)

## Context

All three packages declared `sdk: ^3.11.1`. The app named no Flutter version
at all; `flipperlib` said `flutter: ">=3.10.0"`.

None of that had been built. The app's CI pins Flutter `3.47.1`
(`.github/actions/setup-flutter/action.yml:19`), which is Dart 3.13.1. Both
submodules run on `channel: stable` with no pin, so the only version they have
ever been green on is whatever stable was that day — the same 3.47.1.

The gap is not harmless. `setup-flutter` runs `pub get` with
`--enforce-lockfile`, and `flutter_test` pins `matcher`, `test_api`,
`vector_math` and `meta` to exact versions that move with the SDK. So a
contributor on an older SDK gets a `pub get` that resolves cleanly and a build
that fails somewhere further in, with nothing pointing back at the constraint.

## Decision

**Declare the floor CI actually covers**: `sdk: ^3.13.1` everywhere, plus
`flutter: ">=3.47.1"` where the package is a Flutter package.

## Rejected alternatives (and why)

**Leave `^3.11.1`.** It is a promise nobody tested. The failure it produces is
the confusing kind — green resolution, red build, no signal about why.

**Raise only to `^3.12.x` to avoid the formatter change** (see below).
Half-honest: still not the floor that is covered, and it buys only a smaller
diff.

**Pin the formatter style separately from the language version.** Not
possible — `dart format` has no flag for it, which was checked.

## Consequences

Two of these were not obvious and are the reason this ADR exists.

**The change is atomic with a whole-project reformat.** `dart format` takes
its style from the package's language version, so raising the floor reformatted
**84 files** in the app and 2 in `flipperlib`. The halves cannot be committed
separately: the reformat alone is red because the old formatter undoes it, and
the constraint alone is red because the new style fails
`--set-exit-if-changed`. A `.git-blame-ignore-revs` entry keeps that commit out
of blame; GitHub honours the file automatically, and locally it needs
`git config blame.ignoreRevsFile .git-blame-ignore-revs`.

**The same version raises `prefer_initializing_formals`** to cover private
fields, flagging 10 sites in 6 files. CI treats infos as fatal, so those came
too. They are `dart fix` output, and the transform was verified not to change
the API: Dart exposes `this._reader` as a named parameter called `reader`,
without the underscore, so existing callers still compile.

**The submodule pointers did not move with this.** Both submodules carry the
same fix on their own branches, but `flipperlib`'s `dev` also has breaking API
changes the app has not adopted (issue #144), which is why the pointer sits
three commits behind.

## Migration: what happens to legacy code

Nothing to migrate — a constraint is declarative. The consequences above are
one-off and already applied.
