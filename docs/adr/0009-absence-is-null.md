# 0009. Absence is null, not a sentinel

Status: Accepted (2026-09-24)

## Context

Two fields in `FirmwareFile` / `FirmwareVersion` use a value to mean "there
isn't one", and in both cases that value is also a legal value.

**`sha256: ''`.** `RemoteFirmwareSource._verifySha256` trims the expected
checksum and returns early when it is empty — that is, an empty checksum means
*skip integrity verification on an archive about to be flashed to the device*.
`UnleashedParser.getUpdatePackage` mints `sha256: ''` on purpose for variant
builds, which publish no checksum. So the sentinel is load-bearing in one
place and indistinguishable from a parse default everywhere else.

PR #140 closed the feed-side hole: an empty or whitespace `sha256` coming from
the network is now rejected and the file dropped. What remains is that the
type still cannot tell the two cases apart, and nothing stops an empty string
arriving from somewhere new.

**`timestamp: 0`.** The reader manufactures `0` when the feed sends something
that is not a number. `0` is a valid epoch — 1 January 1970. This is safe today
only by accident: **nothing in `lib/` reads `FirmwareVersion.timestamp`**. The
day someone renders a release date, a malformed timestamp shows 1970 rather
than "unknown".

The sibling parser settles the direction. `lib/modules/dartufbt/lib/sdk/directory_index.dart`
models the same upstream document with `int? timestamp`, `String? sha256` and
`String? changelog`. Two decoders of one feed currently disagree about whether
"missing" is expressible.

## Decision

**`FirmwareFile.sha256` becomes `String?`.** `null` means "this build
publishes no checksum". `RemoteFirmwareSource._verifySha256` returns early on
`null` instead of on blank. `getUpdatePackage` passes `null` for variant
builds.

The gain is not stylistic: a caller that ignores a `String?` gets a
null-safety error, where a caller that ignores `''` silently skips verifying a
firmware image.

**`FirmwareVersion.timestamp` is deleted.**

Not made nullable — removed. Nothing reads it. Keeping it as `int?` would add
a nullable field with no consumer; keeping it as `int` keeps a manufactured
lie in the model's contract. Deleting it removes three lines of reader, four
lines of comment, a fixture parameter and two assertions. If a release date is
ever rendered, the field comes back then, as `int?`, with a consumer.

## Rejected alternatives (and why)

**A `Checksum` value type.** It would add validation (hex, length) that does
not exist today and is not the problem being solved. The problem is that
absence and emptiness are the same value; `String?` fixes exactly that.

**`timestamp` as `int?`.** A nullable field nobody reads. Reviewers split on
this one — the argument for it is that the sibling parser does it and that
manufacturing `0` is dishonest; the argument against is that the honest form
of an unread field is no field. The second won.

**Leave both and document them.** That is the current state, and it is how
`sha256: ''` came to mean two things in two files.

## Consequences

- `_verifySha256`'s signature changes, and its "variant builds publish no
  checksum" comment becomes a type rather than a sentence.
- Every construction site of `FirmwareFile` is touched — small, since there
  are few.
- Deleting `timestamp` touches the model, the reader, the fixture and two
  tests, and removes a field from a feed the project does not control. If it
  is ever wanted, it is a small change to add back.
- The two decoders of `directory.json` stop disagreeing about absence, which
  matters for issue #137.

## Migration: what happens to legacy code

Both changes are small and complete — there is no half-migrated state. The
tolerant reader ([0005](0005-tolerant-decoding.md)) already rejects an empty
`sha256` from the feed, so this only changes what the *type* can express, not
what the network can deliver.
