import 'dart:async';
import 'dart:io';

import 'package:flipperlib/flipperlib.dart';
import 'package:window_manager/window_manager.dart';

import '../services/connection/link_service.dart';
import '../services/guarded.dart';
import '../services/logging.dart';
import '../services/telemetry/telemetry.dart';

/// Closes the link before the desktop window takes the process down with it.
///
/// There was no shutdown path at all. [FlipperClient.dispose] - the method that
/// disconnects every link and cancels the USB presence watch - was never called
/// from anywhere, and neither was `LinkService.dispose`; both were dead code. No
/// `onWindowClose`, no `setPreventClose`. The process simply died and the OS was
/// left to reclaim the serial port.
///
/// Which is usually fine, and sometimes was not: a user reported the Flipper's
/// COM port surviving an exit. Flutter's Windows runner tears the engine down
/// *synchronously inside* `WM_DESTROY`, before `PostQuitMessage`, so anything
/// that stalls engine shutdown leaves the window gone and the process alive -
/// and a live process keeps its handles. Handing the port back ourselves, while
/// Dart is still running and can be relied on, is the part we control.
///
/// It is also the only place the exit path's *log* lines get out. Kept lines
/// reach Sentry through a batcher, so everything the teardown says about the
/// link - the one stretch where a wedged transport is most likely to be
/// described - was still sitting in it when the process went. Issues are not
/// batched and were never affected. See the flush in [_shutdown].
///
/// Desktop only. Android and iOS get no window-close event, their platforms
/// reclaim resources on process death, and `window_manager` does nothing there.
/// A mobile exit therefore still loses that buffer. The hook for it would be
/// `didChangeAppLifecycleState`, not this class - and not with this call: an
/// app that is only backgrounded comes back, and a [Telemetry.closeForExit]
/// there would leave reporting off for the rest of the session with the
/// Diagnostics switch still saying on.
class AppShutdown with WindowListener {
  AppShutdown(
    this._client,
    this._telemetry, {
    LinkService? links,
    void Function(int code)? exitProcess,
  }) : _links = links ?? LinkService.instance,
       _exit = exitProcess ?? exit;

  final FlipperClient _client;

  /// The reporting channel, closed here so its batcher is drained before the
  /// process dies.
  ///
  /// Positional and required, next to the client, because unlike [_links]
  /// there is no singleton to fall back to: `_runApp` is handed the one
  /// `_initCore` started, and anything else would be a second instance
  /// reporting to nowhere.
  final Telemetry _telemetry;

  /// The keeper that reconnects on its own. Taken as a parameter so a test can
  /// see that it is suspended; the app passes nothing and gets the singleton
  /// every other caller uses.
  final LinkService _links;

  /// `dart:io`'s [exit] in the app, a recorder in a test - calling the real one
  /// there would take the test runner down with it.
  final void Function(int code) _exit;

  bool _closing = false;

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Wires the window-close hook.
  ///
  /// Called from `_runApp`, never from `_initCore`: `widgetMain()` - the
  /// headless isolate a home-screen widget starts - never reaches `_runApp` and
  /// has no window to hook, and `_initCore` must never throw. Every call here
  /// carries its own catch for the same reason.
  Future<void> install() async {
    if (!_isDesktop) return;
    await guarded('[Shutdown] install the window hook', () async {
      await windowManager.ensureInitialized();
      // Listener first. `setPreventClose` is applied natively before its reply
      // comes back, so a channel failure after a successful call would leave
      // prevent-close on with nothing handling the close it intercepts - a
      // window that cannot be closed at all, announced by one startup log line
      // nobody has reason to read until they try to quit. Adding a listener is
      // a list insertion and cannot fail, so in this order there is no such
      // gap.
      windowManager.addListener(this);
      // The window would otherwise close while dispose() was still awaiting a
      // disconnect, which is the whole problem.
      await windowManager.setPreventClose(true);
    });
  }

  @override
  void onWindowClose() {
    // WindowListener is synchronous, so the real work is a detached future with
    // its own attribution - a bare unawaited would land in the log as
    // [uncaught] with nothing saying which operation it was.
    unawaited(guarded('[Shutdown] close the link and exit', _shutdown));
  }

  Future<void> _shutdown() async {
    // Re-entrant: setPreventClose keeps the window alive, so a user clicking
    // the X again while a disconnect is in flight arrives here a second time.
    // Destroying twice is harmless, disconnecting twice is not worth finding
    // out about.
    if (_closing) return;
    _closing = true;
    LogService.warn('[Shutdown] releasing the link before exit');

    // Before anything disconnects, and load-bearing: the link keeper watches
    // `sessionsStream` and debounces a reconcile 250 ms behind it. What follows
    // is not a *user* disconnect, so none of the keeper's own conditions refuse
    // it - it would open the serial port again in the middle of this teardown,
    // and the process would then die holding a handle it had just acquired.
    // Which is the symptom this class exists to remove.
    _links.suspended = true;

    // disconnectAll is the step that hands the port back, and the one worth a
    // budget of its own: it tears sessions down one at a time, and each USB
    // release waits up to two seconds for its isolate to run `port.close()` -
    // so two links do not fit in the three seconds this used to allow for the
    // whole of dispose(). Bounded separately also because dispose() calls it
    // first and then does thirteen other things with no try of its own: a
    // throw there used to take the controller closes down with it, and a
    // budget there was already spent before they began.
    await guarded(
      '[Shutdown] disconnect every link',
      () => _client.disconnectAll().timeout(const Duration(seconds: 4)),
    );
    // Bounded too, for a different reason: `Future.timeout` cancels nothing, so
    // a wedged disconnect still holds the client's serialisation lock when this
    // runs, and dispose() begins by queueing behind it. Without a bound here the
    // window below would never be destroyed.
    await guarded(
      '[Shutdown] dispose the client',
      () => _client.dispose().timeout(const Duration(seconds: 2)),
    );

    // The log lines leave here, before destroy() posts WM_QUIT and the process
    // starts winding down. Sentry batches kept lines behind a five-second timer
    // (`buffer_config.dart`), which outlasts an exit that hits none of the
    // budgets above - the normal exit. A local Windows build proved it: three
    // kept lines produced on the way out, none of them in the project. After
    // this point everything is console-only, which is what it already was.
    //
    // After the two disconnects, so that what they reported is in the batcher
    // when it drains. Their *issues* go out unbatched and never needed this; it
    // is the `warn` above and their log lines that did.
    //
    // [Telemetry.closeForExit] because there is no public flush that keeps the
    // hub: `Sentry.close()` is the only drain, and it installs a `NoOpHub`.
    // `stop()` is the wrong door - it is the switch's, and it ends by
    // reconciling against a switch that is still on, so it drained the batcher
    // and then started the SDK again, native layer and all, into a window that
    // was being destroyed. Found by a review of this very block.
    //
    // Bounded like the two above. It never throws, but the close waits on the
    // network, and a user quitting on a dead connection should not be made to
    // watch the window stand there while a report retries.
    await guarded(
      '[Shutdown] flush the reports',
      () => _telemetry.closeForExit().timeout(const Duration(seconds: 2)),
    );

    // `setPreventClose` leaves destroy() as the only way out, which is why it
    // is bounded and guarded rather than trusted: a swallowed one used to leave
    // a window only Task Manager could close, with `_closing` latched so
    // clicking the X again did nothing, for ever.
    //
    // It answers. `window_manager`'s Windows `destroy` is `PostQuitMessage(0)`
    // and the plugin replies `Success(true)` on the spot
    // (`window_manager.cpp:232`), so the message loop is told to end and Dart
    // carries on, racing it. This used to say the engine went down inside
    // WM_DESTROY before the reply could be delivered, which is the runner's
    // *default* close path and not this one. So the two lines below are the
    // usual case on Windows rather than the rare one, and a local build
    // confirms it: every quit logs "still running after destroy".
    await guarded(
      '[Shutdown] destroy the window',
      () => windowManager.destroy().timeout(const Duration(seconds: 2)),
    );
    // Nothing is left to free - dispose() has run, or has had its chance - so
    // taking the process down is the lesser of that and looking hung.
    //
    // `info`, which is to say console-only and compiled out of a release. It
    // used to be `error` on the belief that getting here meant the window had
    // outlived its own destruction; it does not, as the comment above now says,
    // and an `error` on every single quit is noise that would have reported
    // nothing wrong. A destroy that genuinely failed is already reported by its
    // own `guarded` a few lines up, and that one is a real failure.
    LogService.info('[Shutdown] still running after destroy; exiting');
    _exit(0);
  }
}
