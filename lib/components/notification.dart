import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/guarded.dart';
import '../services/logging.dart';
import '../theme/colors/status.dart';
import '../theme/theme.dart';

enum QNotificationType { error, info, warning, good }

class QNotification {
  const QNotification._();

  static const Duration defaultDuration = Duration(seconds: 2);
  static const double edgePadding = 14;

  static QNotificationHandle? _current;

  /// How many times [QNotificationHandle.close] has been *asked*, as against
  /// how many removals it performed.
  ///
  /// Test-only, and the difference is the whole reason it exists. The failure
  /// in QUNLEASHED-S is two asks and two removals; a fix is two asks and one.
  /// "No exception was thrown" cannot tell either from *one* ask - which is
  /// what a test gets if the fade-out stops finishing inside its window and
  /// the auto-close callback silently never runs. That is this repo's
  /// "passed for a different reason" shape, one edit away, so the count is
  /// asserted rather than the absence.
  @visibleForTesting
  static int debugCloseRequests = 0;

  /// Forget the notification on screen, and the count above.
  ///
  /// [_current] is a static that nothing resets by itself, so the last case
  /// in a file leaves it pointing at a live handle and the next `show()`
  /// closes an entry belonging to a torn-down tree. Harmless today only
  /// because `OverlayEntry.remove` returns early on an unmounted overlay -
  /// which is the framework's guarantee, not this component's, and this is
  /// cheaper than depending on it.
  @visibleForTesting
  static void debugReset() {
    // Closed and not merely forgotten. Nulling the pointer would leave the
    // entry of any notification a case left on screen removed-but-undisposed,
    // which is the very leak `close()` was changed to stop - reintroduced in
    // the harness, once per test, and invisible until somebody turns leak
    // tracking on. `close()` bumps the counter, so the zeroing comes after
    // it, and the explicit null covers a handle that was already spent (which
    // returns before it reaches its own clearing line).
    _current?.close();
    _current = null;
    debugCloseRequests = 0;
  }

  static QNotificationHandle show(
    BuildContext context, {
    required String message,
    QNotificationType type = QNotificationType.info,
    Duration duration = defaultDuration,
    VoidCallback? onTap,
  }) {
    _debugLog(message: message, type: type);
    _current?.close();

    final overlay = Overlay.of(context, rootOverlay: true);
    final notification = QNotificationHandle._();

    final entry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned(
          top: 0,
          left: edgePadding,
          right: edgePadding,
          child: _QNotificationHost(
            message: message,
            type: type,
            duration: duration,
            onTap: onTap,
            // The handle's own `close` rather than a removal of its own: two
            // paths that each take the entry off the overlay is the whole of
            // QUNLEASHED-S. See [QNotificationHandle.close].
            onClosed: notification.close,
          ),
        );
      },
    );

    notification._entry = entry;
    _current = notification;
    overlay.insert(entry);
    return notification;
  }

  static void _debugLog({
    required String message,
    required QNotificationType type,
  }) {
    if (!LogService.debugOn) return;

    LogService.info('[QNotification] status=${type.name}; message=$message');
  }
}

extension QNotificationContext on BuildContext {
  QNotificationHandle showNotification(
    String message, {
    QNotificationType type = QNotificationType.info,
    Duration duration = QNotification.defaultDuration,
    VoidCallback? onTap,
  }) {
    return QNotification.show(
      this,
      message: message,
      type: type,
      duration: duration,
      onTap: onTap,
    );
  }
}

class QNotificationHandle {
  QNotificationHandle._();

  OverlayEntry? _entry;

  /// Take the notification off the overlay, once, whoever asks.
  ///
  /// This field is the record of whether that has already happened, and
  /// [OverlayEntry.mounted] cannot stand in for it. `remove()` reads the
  /// entry's own `_overlay` and then nulls it, so it is the *second* call
  /// that reads `_overlay!` after the first one emptied it, while `mounted`
  /// tracks the `_OverlayEntryWidget` - which stays up until the overlay
  /// rebuilds, later in the same frame at the earliest and otherwise in the
  /// next. In that window `mounted` is still true and that second `remove()`
  /// throws `Null check operator used on a null value` out of
  /// `overlay.dart`, in release, where the assertion saying the same thing is
  /// compiled out.
  ///
  /// The window is not hypothetical. `_close` awaits a fade-out whose length
  /// is proportional to how far the card had faded in, so a notification
  /// dismissed early finishes closing itself inside the same frame a holder
  /// of this handle calls `close` in. `pages/archive/map/page.dart` closes its
  /// notice from `dispose` and again on every change of notice, which is the
  /// pair that reached a user. QUNLEASHED-S.
  ///
  /// Both paths come through here rather than one of them removing the entry
  /// for itself, because a removal that something else may also perform is
  /// not idempotent however carefully it is guarded: the callback used to
  /// remove the entry and leave this field set, which left the handle armed
  /// over an entry that was already gone.
  void close() {
    QNotification.debugCloseRequests++;
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    if (identical(QNotification._current, this)) QNotification._current = null;
    // Removed and then discarded, in that order - the order
    // `OverlayEntry.dispose` asserts, and the one Flutter's own
    // `_WrappingOverlayState.dispose` uses. Without the second call the
    // entry's `ValueNotifier` outlives every notification the app has ever
    // shown; nothing observable goes wrong, which is why it sat here
    // unnoticed through the bug above. `dispose` copes with being called
    // while the entry is still mounted by deferring the release to
    // `_didUnmount`, so this does not have to wait for the overlay to
    // rebuild - and it is only reachable once, which is what the field above
    // guarantees and what `dispose` asserts.
    entry
      ..remove()
      ..dispose();
  }
}

class _QNotificationHost extends StatefulWidget {
  const _QNotificationHost({
    required this.message,
    required this.type,
    required this.duration,
    required this.onTap,
    required this.onClosed,
  });

  final String message;
  final QNotificationType type;
  final Duration duration;
  final VoidCallback? onTap;
  final VoidCallback onClosed;

  @override
  State<_QNotificationHost> createState() => _QNotificationHostState();
}

class _QNotificationHostState extends State<_QNotificationHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 110),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    unawaited(_controller.forward());
    if (widget.duration > Duration.zero) {
      _timer = Timer(widget.duration, _close);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) widget.onClosed();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: SafeArea(
        top: true,
        bottom: false,
        minimum: const EdgeInsets.only(top: QNotification.edgePadding),
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Material(
                  color: Colors.transparent,
                  child: _QNotificationCard(
                    message: widget.message,
                    type: widget.type,
                    onTap: widget.onTap,
                    onClose: _close,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QNotificationCard extends StatelessWidget {
  const _QNotificationCard({
    required this.message,
    required this.type,
    required this.onTap,
    required this.onClose,
  });

  final String message;
  final QNotificationType type;
  final VoidCallback? onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final visual = _visual;

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(10),
      elevation: 3,
      child: Semantics(
        liveRegion: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            final action = onTap;
            if (action == null) {
              // Named rather than dropped. This write was a bare discarded
              // future, which is worse than the `unawaited` the ratchet
              // counts: `unawaited_futures` only fires inside an `async`
              // body and this closure is not one, so nothing saw it. A
              // refusal reached the zone as an unlabelled `[uncaught]` and
              // the user saw the toast close as if it had worked - the exact
              // shape `copyTextToClipboard` was extracted to retire,
              // surviving in the one place that cannot call it, because that
              // helper reports through a `BuildContext` and `onClose()` is
              // about to take this one out of the tree.
              //
              // Android carries a clipboard write over a Binder transaction
              // capped near a megabyte, so the throw is real and arrives
              // exactly when the message is longest.
              unawaited(
                guarded(
                  '[QNotification] copying a tapped message',
                  () => Clipboard.setData(ClipboardData(text: message)),
                ),
              );
            } else {
              action();
            }
            onClose();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(visual.icon, size: 18, color: visual.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _QNotificationVisual get _visual {
    switch (type) {
      case QNotificationType.error:
        return const _QNotificationVisual(
          icon: Icons.error_outline_rounded,
          statusColor: StatusColor.error,
        );
      case QNotificationType.info:
        return const _QNotificationVisual(
          icon: Icons.info_outline_rounded,
          statusColor: StatusColor.info,
        );
      case QNotificationType.warning:
        return const _QNotificationVisual(
          icon: Icons.warning_amber_rounded,
          statusColor: StatusColor.warning,
        );
      case QNotificationType.good:
        return const _QNotificationVisual(
          icon: Icons.check_circle_outline_rounded,
          statusColor: StatusColor.good,
        );
    }
  }
}

class _QNotificationVisual {
  const _QNotificationVisual({required this.icon, required this.statusColor});

  final IconData icon;
  final StatusColor statusColor;

  Color get color => statusColor.color;
}
