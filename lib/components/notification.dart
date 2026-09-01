import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/logging.dart';
import '../theme/colors/status.dart';
import '../theme/theme.dart';

enum QNotificationType { error, info, warning, good }

class QNotification {
  const QNotification._();

  static const Duration defaultDuration = Duration(seconds: 2);
  static const double edgePadding = 14;

  static QNotificationHandle? _current;

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
    late final OverlayEntry entry;

    entry = OverlayEntry(
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
            onClosed: () {
              if (entry.mounted) entry.remove();
              if (identical(_current, notification)) _current = null;
            },
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

    LogService.log('[QNotification] status=${type.name}; message=$message');
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

  void close() {
    final entry = _entry;
    if (entry?.mounted ?? false) {
      entry!.remove();
    }
    _entry = null;
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
              Clipboard.setData(ClipboardData(text: message));
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
