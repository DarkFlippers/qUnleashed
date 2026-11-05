/// The pixel face, named once.
///
/// Three widgets set text in it - `ProgressButton`, the about page's wordmark
/// and `PixelButton` - and a `fontFamily` is a string nothing checks. A family
/// Flutter cannot resolve is not an error: it falls back to the platform face
/// for the whole string, silently, which is a louder version of the bug this
/// font was forked to fix.
library;

/// The family `pubspec.yaml` declares for `assets/font/born2b-sporty-v3.ttf`.
const String kPixelFontFamily = 'Born2bSportyV3';

/// What to use for a character the pixel face has not got.
///
/// `test/font_glyph_coverage_test.dart` keeps every translated string
/// printable in [kPixelFontFamily], so this is not for those. It is for the
/// labels that are not translated strings at all: `recover_page` and the
/// flibler project page interpolate Flipper filenames and device names, which
/// can carry any codepoint, and CJK is deliberately not drawn. Without a
/// fallback those resolve against whatever the platform picks first, which on
/// some platforms is nothing.
const List<String> kPixelFontFallback = ['Roboto', 'Arial', 'sans-serif'];
