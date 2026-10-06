import 'dart:async';
import 'dart:io';

import 'package:flipperlib/flipperlib.dart';
import 'package:window_manager/window_manager.dart';

import '../services/guarded.dart';
import '../services/logging.dart';

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
/// Desktop only. Android and iOS get no window-close event, their platforms
/// reclaim resources on process death, and `window_manager` does nothing there.
class AppShutdown with WindowListener {
  AppShutdown(this._client);

  final FlipperClient _client;
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
      // The window would otherwise close while dispose() was still awaiting a
      // disconnect, which is the whole problem.
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);
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

    // Bounded, because the window is already unresponsive by now. A device that
    // will not answer its disconnect must not hold the app open indefinitely -
    // better to leak a handle to a process that is about to die than to look
    // hung. dispose() is best-effort here for the same reason: whatever it
    // fails to free, process death will.
    await guarded(
      '[Shutdown] dispose the client',
      () => _client.dispose().timeout(const Duration(seconds: 3)),
    );

    await guarded('[Shutdown] destroy the window', windowManager.destroy);
  }
}
