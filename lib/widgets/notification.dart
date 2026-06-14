import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/colors/status.dart';
import '../theme.dart';

enum QNotificationType { error, info, warning, good }

class QNotification {
  const QNotification._();

  static const Duration defaultDuration = Duration(seconds: 2);
  static const double edgePadding = 14;

  static _QNotificationOverlay? _current;

  static void show(
    BuildContext context, {
    required String message,
    QNotificationType type = QNotificationType.info,
    Duration duration = defaultDuration,
  }) {
    _debugLog(message: message, type: type);
    _current?.close();

    final overlay = Overlay.of(context, rootOverlay: true);
    final notification = _QNotificationOverlay();
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
  }

  static void _debugLog({
    required String message,
    required QNotificationType type,
  }) {
    if (!kDebugMode) return;

    debugPrint('[QNotification] status=${type.name}; message=$message');
  }
}

extension QNotificationContext on BuildContext {
  void showNotification(
    String message, {
    QNotificationType type = QNotificationType.info,
    Duration duration = QNotification.defaultDuration,
  }) {
    QNotification.show(this, message: message, type: type, duration: duration);
  }
}

class _QNotificationOverlay {
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
    required this.onClosed,
  });

  final String message;
  final QNotificationType type;
  final Duration duration;
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
    required this.onClose,
  });

  final String message;
  final QNotificationType type;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final visual = _visual;

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: visual.color.withValues(
                    alpha: colors.isDark ? 0.2 : 0.14,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(visual.icon, color: visual.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      visual.title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(34),
                  maximumSize: const Size.square(34),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  Icons.close_rounded,
                  color: colors.textMuted,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _QNotificationVisual get _visual {
    switch (type) {
      case QNotificationType.error:
        return const _QNotificationVisual(
          title: 'Error',
          icon: Icons.error_outline_rounded,
          statusColor: StatusColor.error,
        );
      case QNotificationType.info:
        return const _QNotificationVisual(
          title: 'Information',
          icon: Icons.info_outline_rounded,
          statusColor: StatusColor.info,
        );
      case QNotificationType.warning:
        return const _QNotificationVisual(
          title: 'Warning',
          icon: Icons.warning_amber_rounded,
          statusColor: StatusColor.warning,
        );
      case QNotificationType.good:
        return const _QNotificationVisual(
          title: 'Done',
          icon: Icons.check_circle_outline_rounded,
          statusColor: StatusColor.good,
        );
    }
  }
}

class _QNotificationVisual {
  const _QNotificationVisual({
    required this.title,
    required this.icon,
    required this.statusColor,
  });

  final String title;
  final IconData icon;
  final StatusColor statusColor;

  Color get color => statusColor.color;
}
