import 'dart:async';

import 'package:flutter/material.dart';

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
    _current?.close();

    final overlay = Overlay.of(context);
    final topOffset = _topOffsetFor(context, overlay.context);
    final notification = _QNotificationOverlay();
    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned(
          top: topOffset,
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

  static double _topOffsetFor(BuildContext context, BuildContext overlayContext) {
    final scaffold = Scaffold.maybeOf(context) ?? _findDescendantScaffold(context);
    final appBarHeight = scaffold?.appBarMaxHeight;
    final overlayBox = overlayContext.findRenderObject();
    final scaffoldBox = scaffold?.context.findRenderObject();

    if (appBarHeight != null && appBarHeight > 0) {
      if (overlayBox is RenderBox && scaffoldBox is RenderBox) {
        final scaffoldTop = scaffoldBox.localToGlobal(
          Offset.zero,
          ancestor: overlayBox,
        );
        return scaffoldTop.dy + appBarHeight + edgePadding;
      }
      return appBarHeight + edgePadding;
    }
    return MediaQuery.paddingOf(context).top + edgePadding;
  }

  static ScaffoldState? _findDescendantScaffold(BuildContext context) {
    ScaffoldState? scaffold;

    void visit(Element element) {
      if (scaffold != null) return;
      if (element is StatefulElement && element.state is ScaffoldState) {
        scaffold = element.state as ScaffoldState;
        return;
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return scaffold;
  }
}

extension QNotificationContext on BuildContext {
  void showNotification(
    String message, {
    QNotificationType type = QNotificationType.info,
    Duration duration = QNotification.defaultDuration,
  }) {
    QNotification.show(
      this,
      message: message,
      type: type,
      duration: duration,
    );
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
        top: false,
        bottom: false,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
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
    final accent = _accentColor(colors);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.34 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(_icon, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            padding: EdgeInsets.zero,
            onPressed: onClose,
            icon: Icon(Icons.close, color: colors.textMuted, size: 20),
          ),
        ],
      ),
    );
  }

  IconData get _icon {
    switch (type) {
      case QNotificationType.error:
        return Icons.error_outline_rounded;
      case QNotificationType.info:
        return Icons.info_outline_rounded;
      case QNotificationType.warning:
        return Icons.warning_amber_rounded;
      case QNotificationType.good:
        return Icons.check_circle_outline_rounded;
    }
  }

  Color _accentColor(QAppColors colors) {
    switch (type) {
      case QNotificationType.error:
        return colors.danger;
      case QNotificationType.info:
        return colors.info;
      case QNotificationType.warning:
        return const Color(0xFFFFA726);
      case QNotificationType.good:
        return colors.success;
    }
  }
}
