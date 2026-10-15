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
///  * **Chrome** - a label that is a translated constant. `_BottomTab` and
///    `_RailButton` in `app/nav_bar.dart`. Buttons are covered by a type rule
///    in `telemetry/options.dart` instead, since they are `ButtonStyleButton`
///    from the framework and cannot be given a mixin.
///  * **Device facts the project has decided it is willing to see** - the
///    Flipper's name, its serial, its BLE MAC, the rest of `device info`, and
///    a recovered MIFARE key with the card's UID. These are not chrome; they
///    are content, and somebody looked at each one and said yes. They are
///    also no longer redacted from the log and the event channels, so the
///    three agree - `telemetry/scrub.dart` carries that half.
///
/// What it must **not** go on: a file or folder name, a coordinate, a build
/// log line carrying a host path, an infrared dump, a Sub-GHz seed. Those are
/// the surfaces the blanket is still for.
///
/// Mind the subtree. `WidgetFilter` stops descending on an unmask decision, so
/// everything inside one of these is unmasked too - which is why these sit on
/// leaf-ish widgets and never on a page or a scaffold. A [SensitiveSurface]
/// *above* one still wins, because the walk meets it first.
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
