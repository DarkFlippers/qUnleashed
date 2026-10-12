// Everything the SDK is told, and the scope it is told it on.
//
// Its own file because this is where ADR 0013 §6's privacy decisions are read
// off, and a reader looking for them was scrolling past the whole lifecycle to
// get there. Pure: options in, options mutated, nothing of `Telemetry`'s own
// state touched - which is why these are top-level functions rather than
// methods.
import 'package:flutter/widgets.dart' show RawImage;
import 'package:flutter_map/flutter_map.dart' show FlutterMap;
import 'package:re_editor/re_editor.dart' show CodeEditor;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:xterm/xterm.dart' show TerminalView;

// §6.4's surfaces, imported for their types alone - `mask<T>()` takes a widget
// type and never an instance. This points from a service at three pages, which
// is the wrong way round and is the lesser of the two wrongs available: the
// alternative is `SentryMask` in those pages, which puts the SDK outside this
// folder and breaks §2's import rule and the test that holds it. A masking rule
// that stops matching is silent and streams card bytes, so the rules are
// checked in `test/telemetry_lifecycle_test.dart` rather than trusted.
import '../../pages/archive/editor/hex/view.dart' show HexTable;
import '../../pages/tools/plotter/plotter_view.dart' show PlotterView;
import '../../pages/tools/remote/desktop/widgets/screen.dart' show RemoteScreen;
import '../logging.dart';
import 'plan.dart';
import 'scrub_event.dart';

/// Everything the SDK is told, in one place so §6 can be read off it.
void configureOptions(SentryFlutterOptions options, TelemetryPlan plan) {
  options.dsn = plan.dsn;
  options.release = plan.release;
  // Null leaves the SDK's own default, which is the right fallback: a crash
  // report in an awkward place beats no crash report.
  options.nativeDatabasePath = plan.nativeDatabasePath;
  options.dist = plan.dist;
  options.environment = plan.environment;

  // §6.1, not collected. `attachScreenshot` is already the SDK's default;
  // it is written down anyway because a default that changes in a minor
  // version is not something a privacy decision should rest on.
  //
  // `attachViewHierarchy` is the one §6.1 names that is **not** set here. It
  // defaults to false, and the option is marked experimental - so touching
  // it raises `experimental_member_use`, which CI treats as fatal. Left at
  // its default, with the server-side rules in §6.3 as the backstop that
  // does not depend on an SDK default either way.
  options.sendDefaultPii = false;
  options.attachScreenshot = false;
  // On by default, and off here because `LogService` feeds Sentry directly
  // (§2). Left on, every line a talking build prints would arrive a second
  // time as a breadcrumb, unscrubbed by anything in this file.
  options.enablePrintBreadcrumbs = false;

  // Both on by default, and both inert unless something mounts
  // `SentryUserInteractionWidget`. Nothing does - `Telemetry.wrap` mounts
  // `SentryScreenshotWidget` alone - so these two lines are a guard rail and
  // not the fix: `SentryWidget` is the wrapper every example reaches for, it
  // mounts the interaction widget as well, and swapping to it would open both
  // of these without a word. Here is where that costs a failing diff instead.
  //
  // The breadcrumb carries `_getTouchPath`: the tapped widget's label plus up
  // to ten ancestors', as a list of maps. `scrubEvent` rewrites **top-level**
  // string values only - `scrub_event.dart` says so in as many words, on the
  // grounds that nothing the app puts in a breadcrumb has a nested one. The
  // SDK does, and those labels are file names and card names, so they would
  // leave without passing §6.2 at all.
  //
  // The tracing half is a `ui.action.click` **transaction** per tap at
  // `tracesSampleRate = 1.0`, on all six platforms including the four where
  // replay records nothing. That is a steadier stream of envelopes than
  // anything else in the app, into the cache already measured discarding error
  // events under load - the same argument that holds `sessionSampleRate` at
  // zero below, and it would be strange to make it there and not here.
  //
  // The breadcrumb half is reversible: teach `_scrubStringValues` to walk one
  // level of lists and maps and it becomes safe to switch back on. §4's title
  // is "Breadcrumbs come from flipperlib only", so that is an ADR amendment
  // and not just a code change.
  options.enableUserInteractionBreadcrumbs = false;
  options.enableUserInteractionTracing = false;

  // §6.2. Every event passes through the scrubber before it leaves.
  //
  // Three hooks, not one, because sentry 9 routes the three event classes
  // separately and §6.2's "runs before every event, breadcrumb, log and
  // transaction" was only true of the first. A log reaches
  // `beforeSendLog` and nothing else (`log_capture_pipeline.dart`); a
  // transaction reaches `beforeSendTransaction` and falls to `beforeSend`
  // only when that is unset. So without the other two, the Logs channel -
  // the highest-volume outbound channel in the feature - was held by a
  // single `Scrub.outbound` call in `_reportKept`, and span text by
  // per-call-site discipline.
  options.beforeSend = (event, hint) => scrubEvent(event);
  options.beforeSendTransaction = (transaction, hint) =>
      scrubTransaction(transaction);
  options.beforeSendLog = (log) => scrubLog(log);

  // Sentry Logs, which §2 feeds from `LogService`'s kept entries. Off by
  // default in this major and configured differently in 10 - which is the
  // one line §7's "10 is a version bump" now costs, and it says so.
  options.enableLogs = true;

  // §8: everything at 100%, revisited after a month of real volume. The
  // plan has the headroom and pay-as-you-go is capped at $0, so going over
  // drops events rather than producing a bill.
  //
  // This is also what makes the navigator observer do anything:
  // `isTracingEnabled()` is false while the rate is null, and a span with no
  // sampled transaction over it is discarded.
  options.tracesSampleRate = 1.0;

  // §1's replay, and §8's answer for it: a replay for every error, and no
  // session recording at all. The two rates are what `isEnabled` reads, so
  // leaving `onErrorSampleRate` at zero is also how the switch turns the
  // feature off - there is no app-facing pause API in this major (the SDK has
  // internal `replayPaused`/`replayResumed` plumbing and exposes none of it),
  // which is why `Telemetry._reconcile` restarts the SDK when that switch
  // moves.
  //
  // **`onErrorSampleRate` gates the upload, not the capture.** With it above
  // zero `isEnabled` is true, and `replayStarted` calls `_replayRecorder.start`
  // unconditionally; `replayIsBuffering` only decides whether the replay id
  // goes on the scope. So the screen is captured continuously into a rolling
  // buffer the native SDK discards unless an error arrives. What makes that an
  // acceptable default is the masking below, which runs at capture time - the
  // buffer never holds card bytes to begin with - and §1's switch, which is
  // how a user says no to it. The Diagnostics subtitle says so in those terms;
  // it is the one place the user is told, so the two must not drift.
  //
  // Session recording stays at zero on purpose and not pending a decision.
  // What it would add is not more recording - that is already happening - but a
  // steady stream of envelopes **leaving** the device, into the same cache
  // already measured discarding error events under load
  // (`client_discard`/`cache_overflow`, 2026-10-11), and an error is the only
  // moment a replay answers a question anybody asked.
  //
  // **Native-backed, so this is Android and iOS only.** `ReplayIntegration`
  // gates on `supportsReplay`, so the four desktop targets record nothing
  // whatever these say.
  options.replay.onErrorSampleRate = plan.shareReplay ? 1.0 : 0.0;
  options.replay.sessionSampleRate = 0.0;

  // §6.4's gate, and the whole reason replay could not simply be switched on.
  //
  // `maskAllText` and `maskAllImages` are both true by default and neither
  // reaches any of the three surfaces below. `buildMaskingConfig` adds rules
  // for `Text`, `EditableText` and `RichText`, and one for `Image` that spares
  // root-bundle assets. (`maskAllText`'s own dartdoc says "only `Text` and
  // `EditableText`" and is stale; the config is the source of truth. Read it
  // and not the doc when adding a surface - a `SelectableText` dump is already
  // covered by the `RichText` rule, a painted one is not.)
  //
  // **The rule, which matters more than the list:** a surface that paints its
  // own glyphs or pixels is unmasked until it is named here. `maskAllText`
  // reaches three widget types and `maskAllImages` one; a `CustomPainter` or a
  // `RenderBox` that draws text is none of them. Every entry below is an
  // instance of that one mechanism, and three of them were missed on the first
  // pass - so when a new screen renders device content, this block is the
  // thing to come back to.
  //
  // What the defaults miss:
  //
  // - `HexTable` paints card bytes with a `TextPainter` inside a
  //   `CustomPainter`, so there is no `Text` in the tree to match.
  // - `RemoteScreen` is a `RawImage`, which is not an `Image`.
  // - `PlotterView` paints the SubGHz pulse plot the same way, and the rest of
  //   that view - bits, histogram, raw RF - is the same capture in other forms.
  // - `FlutterMap` draws every tile as a `RawImage` (flutter_map 7.0.2), so the
  //   map records the user's own position, auto-centred, with GPS-tagged
  //   capture pins on it. The whole widget and not the tile layer: the
  //   position is the sensitive part, and it is not painted by the tiles.
  // - `CodeEditor` is `re_editor`, whose body is a `RenderBox` painting
  //   through `_drawText`. **This is the editor a user lands on** -
  //   `EditorMode.text` is the default and hex is the mode they have to switch
  //   into - so opening `/ext/nfc/card.nfc` shows the UID, ATQA, SAK and the
  //   plaintext key block, and `.mfkey32.log` and `.nested.log` show nonce
  //   dumps. Masking the opt-in hex view and not this one would have been
  //   close to backwards.
  // - `TerminalView` is `xterm`, also a `RenderBox`. The CLI is where
  //   `storage read`, `nfc` and `subghz` output lands as raw text.
  // - `RawImage` itself, as the net under all of this. In this app a raw image
  //   is device or user content by construction - there is no decorative one -
  //   which is what makes the broad rule cheap, and it covers the paint tool's
  //   preview and anything else that arrives the same way.
  //
  // Without these a replay records card dumps, the live device screen, decoded
  // radio captures and the user's location: the most sensitive content the app
  // holds, in the one feature that sends pictures. Both
  // `diagnosticsShareSubtitle` and §1's one-time notice promise the user that
  // captures and their location are never sent, so this is not only §6.4's
  // gate, it is whether those two sentences are true.
  //
  // Masked by enclosing type rather than per surface, so a new widget inside
  // any of them is covered the day it is written rather than the day somebody
  // remembers. `WidgetFilter._process` stops descending on a mask decision, so
  // the whole subtree goes with it.
  //
  // **No `description:` argument, deliberately.** Left out, the SDK defaults it
  // to the literal `'mask'` (or `'unmask'`), and `privacy.toJson()` is public
  // and emits `'<name>: <description>'` - so a test can assert the *decision*
  // over public API. With a description of our own it cannot: `mask<T>()` and
  // `unmask<T>()` both append a rule named `T.toString()`, so every name-based
  // assertion passes either way. That is not hypothetical - a one-word edit
  // here passed the whole suite, including the case named for these masks.
  // `unmask` is worse than deleting the line, because it applies to the
  // subtree and short-circuits later rules, so it would defeat `maskAllText`
  // inside the hex table too. The prose that used to sit in the argument is
  // above, where a reader was always better served by it.
  //
  // The ignores are not decoration. `mask<T>()` is `@experimental` in 9.30.1,
  // and `experimental_member_use` is fatal in CI - the same wall that left
  // `attachViewHierarchy` alone above. That precedent does not carry here:
  // there the default was already the safe value, so leaving it cost nothing,
  // and here the default is the unsafe one. Suppressing the warning is the
  // price of the masks; shipping replay without them is not an option and
  // leaving the warning unsuppressed is not a build.
  // ignore: experimental_member_use
  options.privacy.mask<HexTable>();
  // ignore: experimental_member_use
  options.privacy.mask<RemoteScreen>();
  // ignore: experimental_member_use
  options.privacy.mask<PlotterView>();
  // ignore: experimental_member_use
  options.privacy.mask<FlutterMap>();
  // ignore: experimental_member_use
  options.privacy.mask<CodeEditor>();
  // ignore: experimental_member_use
  options.privacy.mask<TerminalView>();
  // ignore: experimental_member_use
  options.privacy.mask<RawImage>();

  // Off, and not because it is unwanted. Frame timings need
  // `SentryWidgetsFlutterBinding`, and `_initCore` installs Flutter's own -
  // swapping it would mean `main.dart` importing the SDK, which §2's import
  // rule forbids, and installing Sentry's binding in a build that reports
  // nothing is the thing 0013's Consequences asks to verify first. Left
  // false so the SDK does not warn about a binding it was never given.
  options.enableFramesTracking = false;

  // §3: or their frames are folded away as third-party, which is the
  // opposite of true - a fault in either is this project's to fix.
  options.addInAppInclude('flipperlib');
  options.addInAppInclude('dartufbt');

  // The SDK's own diagnostics follow QLOG rather than the build type, so a
  // release build made to talk talks about this too, and a debug run told to
  // be quiet is quiet.
  options.debug = LogService.printing;
}

/// Puts 0014 §3's commits on every event.
///
/// On the scope rather than in the options, because the SDK has no
/// options-level tag map - and the scope is the right place regardless: it
/// is synced to the native layer, so a native crash carries them too, which
/// is the event class that cannot be assembled in Dart at all.
Future<void> tagScope(TelemetryPlan plan) async {
  await Sentry.configureScope((scope) async {
    for (final tag in plan.tags.entries) {
      await scope.setTag(tag.key, tag.value);
    }
  });
}
