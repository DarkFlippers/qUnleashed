// Source of record for the JavaScript pasted into Crowdin's Custom Post-Export
// Processor app, at Project Settings -> File Processors. The live copy is in
// that app; this file is the one that gets reviewed, and the two have to agree.
// Paste it whole after any change here.
//
// Why it exists is 0016, and what it enforces is `.github/scripts/check_arb_locales.sh`,
// which is the same rule in bash and fails the Crowdin sync when this does not
// run. That script's header has the mechanism; the short version is that
// Crowdin writes `@@locale` from its own language id (`es-ES`), `crowdin.yml`'s
// `languages_mapping` decides the filename (`app_es.arb`), and flutter
// gen-l10n refuses the pair - it re-spells the parsed filename with
// underscores before comparing, so no hyphenated `@@locale` matches any
// filename that can exist.
//
// The app passes `content`, `fileName`, `languageId` and `projectId`, and takes
// back `content` and `fileName`. It runs sandboxed: no I/O, no npm, no network.
//
// Derived from `fileName` rather than from `languageId`, because the filename
// is what gen-l10n compares against and `crowdin.yml` already decided it.
// Mapping `languageId` here instead would be a second copy of that mapping,
// free to drift from the one in `crowdin.yml`.
//
// Every hyphenated entry in `languages_mapping` needs this, not just Spanish:
// enabling `pt-BR`, `zh-TW` or `sr-Latn` exercises the same path, and a
// filename this regex does not match leaves `@@locale` alone and fails the
// sync rather than corrupting the file.

var named = /_([A-Za-z0-9_-]+)\.arb$/.exec(fileName);
if (named) {
  // Underscores, not the hyphen BCP 47 would use: gen-l10n compares against
  // `Locale.tryParse(filename).toString().replaceAll('-', '_')`.
  var locale = named[1].replace(/-/g, '_');
  // Anchored to the start of a line, matching the bash extractor, so a
  // `"@@locale"` appearing inside some other string value is left alone.
  content = content.replace(
    /^(\s*"@@locale"\s*:\s*")[^"]*(")/m,
    '$1' + locale + '$2'
  );
}
