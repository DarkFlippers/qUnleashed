# 0016. The translation branch has one owner, and the locale is settled in the export

Status: Accepted (2026-10-15).

**Crowdin's export is normalised before it is committed, not after.** A Custom
Post-Export Processor app rewrites `@@locale` to agree with the filename
Crowdin's own export pattern produced. The repository holds the source of that
app's code at [`.github/crowdin/normalise_locale.js`](../../.github/crowdin/normalise_locale.js)
and verifies the result with `.github/scripts/check_arb_locales.sh`, which is
the same rule in bash.

## The mechanism

Crowdin writes `@@locale` from its own **language id** — its Spanish *is*
`es-ES`; there is no plain `es` to pick. `crowdin.yml`'s `languages_mapping`
decides the **filename**, `app_es.arb`. The two are separate: the mapping
renames the file and never touches what is inside it. Crowdin support confirms
that is deliberate, and points at the file-processor apps as the only way to
change exported bytes — [community thread](https://community.crowdin.com/t/locale-settings-is-not-applied/13571).

`flutter gen-l10n` then refuses the pair. It parses the filename as a locale
and re-spells it with underscores before comparing, so the comparison is
`es-ES` against `es_ES` and **no filename can produce a hyphenated left-hand
side**. Every hyphenated entry in `languages_mapping` is the same shape;
Spanish is only the first anybody enabled.

`es` is also the right tag on the merits. BCP 47 §4.1 says to use no subtag
that adds no distinguishing information, and CLDR reduces `es-ES` to `es` for
exactly that reason. `es_ES` — the spelling gen-l10n would need — is not a BCP
47 tag at all. The one place the standard and the tool agree byte for byte is
a bare language code.

## Why the export, and not the branch

#321 settled it on the branch instead: the sync ran `check_arb_locales.sh
--write` in a worktree **after** the Crowdin action had already committed and
opened the pull request, then committed the repair itself.

That left the branch permanently one value away from what Crowdin exports. So
every nightly sync had a diff whether a translation had changed or not, opened
a pull request for it, and added two commits that cancelled each other. #323 is
that pull request with nothing else in it: two commits, no diff. The push also
retargeted `ci.yml`'s `pull_request` trigger, cancelling the run already in
flight and starting another — a full analyze job plus a macOS job, nightly, for
no change.

The cause was two owners of one branch. Collapsing to one is the decision; the
export is the one we picked.

## Alternatives, and what would change the answer

- **Own the download** — `push_translations: false`, normalise, then commit.
  Keeps the rule in one language, in this repository, covered by
  `check_arb_locales_test.sh`, with no external dependency. It costs branch
  creation, force-push semantics and pull request creation, which the action
  does today. `crowdin-rx.yml` declined this before #323 on the grounds of "one
  commit instead of two" — it under-priced its own option, and the plumbing
  scar it cited (the container running as root) is unaffected either way. **This
  is the fallback if the app proves unreliable**, and the gap between it and
  what we chose is small now that the snippet is in the repository.
- **Drop `@@locale` from the ARBs** — gen-l10n falls back to the filename, but
  Crowdin injects the key regardless (it is not a project string), so this needs
  the same app with a different snippet. Same dependency, and it retires the one
  mistake the key does catch: a file renamed by hand.
- **Language mapping** — cannot reach file contents. Confirmed, not inferred.
- **A custom Crowdin language coded `es`** — custom languages are not available
  on this plan, and it would have to be repeated per family.

## The consequence, stated plainly

**A repository invariant is now enforced by configuration CI cannot read.**
Nothing in a pull request can see the snippet; the first thing that notices it
missing is the nightly sync, after the fact. That is accepted because the sync
*does* notice — `check_arb_locales.sh` names the file, writes it into the pull
request body and fails the run — and because the snippet is in the repository
where it can be reviewed and pasted back.

What would reverse this: losing access to the app's settings, or a second
hyphenated language it mishandles in a way the snippet cannot express. Either
means moving to owning the download.
