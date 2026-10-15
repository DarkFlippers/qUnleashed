import 'package:flutter/widgets.dart';

/// A widget showing device or user content, which a screen replay must not
/// record. ADR 0013 §6.4.
///
/// **The app declares what is sensitive; `telemetry/options.dart` masks it.**
/// One `mask<SensitiveSurface>()` rule there replaces a list of seven widget
/// types, and with it the three page imports that pointed a service at the UI.
/// Nothing here imports the SDK, so §2's rule - and
/// `test/sentry_import_guard_test.dart`, which enforces it on
/// `package:sentry*` - is untouched.
///
/// The list was the problem, not its contents. Two of the seven types were
/// found only on a second review pass, because the thing that decides whether
/// a surface is sensitive is not a property the analyzer can see: `CodeEditor`
/// is a `StatefulWidget` whose `RenderBox` is built inside a private `State`,
/// and the alternative of masking by render mechanism is wrong in both
/// directions. `mask<RawImage>()` caught every [QIcon] in the app - icons are
/// `RawImage` here - so a replay came back with grey boxes where the chrome
/// was, while the paint tool's canvas, a `CustomPaint` over the user's own
/// artwork, went unmasked. "Does this show device or user content" is
/// knowledge only the page has.
///
/// Mixed into an app-owned widget, so every use of it is covered rather than
/// every use the author remembered. For a widget from a package, which cannot
/// be given a mixin, [SensitiveSurfaceBox] wraps it at the use site.
mixin SensitiveSurface on Widget {}

/// A widget a screen replay is **meant** to record, through `maskAllText`.
///
/// The inverse of [SensitiveSurface], and it exists because the blanket was
/// doing all the work. `maskAllText` masks every `Text`, `EditableText` and
/// `RichText` in the app, so a replay came back with grey boxes where the
/// buttons, the tabs and the titles were - unreadable, and so unused.
///
/// **Only the safe direction is enumerated here, and that is deliberate.**
/// Masking the sensitive surfaces instead would mean listing them, and this
/// file's other half records what that cost: two of seven were found only on
/// a second review pass. A surface nobody thought of stays masked under this
/// arrangement. The failure mode is a duller replay, not a card dump.
///
/// Two kinds of thing carry it, and they are not the same claim:
///
///  * **Chrome** - a label that is a translated constant. `_BottomTab` in
///    `app/nav_bar.dart` is the one that carries it; `_RailButton` beside it
///    renders an icon and no text, so a marker there would do nothing.
///    Buttons are covered by a type rule in `telemetry/options.dart` instead,
///    since they are the framework's and cannot be given a mixin.
///  * **Device identity the project has decided it is willing to see** - the
///    Flipper's name, its serial, its BLE MAC and the rest of `device info`,
///    through `_DeviceSubtitle` and `FlipperInfoLine`. Not chrome: content,
///    looked at and accepted. `telemetry/scrub.dart` stopped redacting the
///    same facts from the log and event channels in the same change.
///
/// What it must **not** go on, and the first entry is the one that will be
/// tempting: **a recovered MIFARE key or a card UID.** Those are sent in logs
/// now, but `diagnosticsShareSubtitle` and §1's one-time notice both promise
/// the user in as many words that keys are never sent, so the replay keeps
/// them masked until that copy is rewritten - ADR 0013 §6.4. Nor on a file or
/// folder name, a coordinate, a build log line carrying a host path, an
/// infrared dump, or a Sub-GHz seed.
///
/// Mind the subtree, in both directions. `WidgetFilter` stops descending on an
/// unmask decision, so everything inside one of these is unmasked too - which
/// is why these sit on leaf-ish widgets and never on a page or a scaffold. A
/// [SensitiveSurface] *above* one still wins, because the breadth-first walk
/// meets it first and never queues the subtree. A [SensitiveSurface] *below*
/// one **loses**, and silently: the walk stops before it is ever visited. That
/// is the hazard to check when adding a marker, and it applies to the
/// `ButtonStyleButton` rule too, which covers every `IconButton` in the app.
mixin VisibleSurface on Widget {}

/// [SensitiveSurface] for a widget this project does not own.
///
/// `FlutterMap`, `CodeEditor` and `TerminalView` each have exactly one use
/// site, and each shows device content: the map carries the user's position
/// with GPS-tagged pins, the editor is what `/ext/nfc/card.nfc` opens into by
/// default - UID, ATQA, SAK and the key block, as painted glyphs no text rule
/// reaches - and the terminal is where `storage read` output lands.
///
/// Transparent: it builds [child] and nothing else, so it cannot change
/// layout. Its only job is to be a type the masking rule matches, which is
/// `SentryMask`'s job in the SDK - owned here instead so §2's import rule
/// holds.
class SensitiveSurfaceBox extends StatelessWidget with SensitiveSurface {
  const SensitiveSurfaceBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
