import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

class QPageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const QPageAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.backgroundColor,
    this.foregroundColor,
    this.subtitle,
    this.showDeviceStatus = true,
    this.centerTitle = false,
    this.bottom,
    this.elevation = 0,
  });

  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final String? subtitle;
  final bool showDeviceStatus;
  final bool centerTitle;
  final PreferredSizeWidget? bottom;
  final double elevation;

  static const double toolbarHeight = 68;

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = foregroundColor ?? colors.onAccent;

    final background = backgroundColor ?? colors.accent;

    return _QPageAppBarColorScope(
      color: background,
      child: AppBar(
        toolbarHeight: toolbarHeight,
        backgroundColor: background,
        foregroundColor: foreground,
        iconTheme: IconThemeData(color: foreground),
        actionsIconTheme: IconThemeData(color: foreground),
        elevation: elevation,
        scrolledUnderElevation: elevation,
        centerTitle: centerTitle,
        titleSpacing: 0,
        leading: leading,
        actions: actions,
        bottom: bottom,
        title: _PageTitle(
          title: title,
          subtitle: subtitle,
          showDeviceStatus: showDeviceStatus,
          foregroundColor: foreground,
        ),
      ),
    );
  }
}

class _QPageAppBarColorScope extends InheritedWidget {
  const _QPageAppBarColorScope({required this.color, required super.child});

  final Color color;

  static Color? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_QPageAppBarColorScope>()
      ?.color;

  @override
  bool updateShouldNotify(_QPageAppBarColorScope oldWidget) =>
      color != oldWidget.color;
}

class _PageTitle extends StatefulWidget {
  const _PageTitle({
    required this.title,
    required this.subtitle,
    required this.showDeviceStatus,
    required this.foregroundColor,
  });

  final String title;
  final String? subtitle;
  final bool showDeviceStatus;
  final Color foregroundColor;

  @override
  State<_PageTitle> createState() => _PageTitleState();
}

class _PageTitleState extends State<_PageTitle> {
  final FlipperClient _client = FlipperOneClient().get();
  StreamSubscription<FlipperConnectionState>? _connectionSubscription;
  StreamSubscription<Map<String, String>>? _deviceInfoSubscription;
  FlipperDevice? _device;
  String? _hardwareName;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _device = _client.connectedDevice;
    _connected = _client.isConnected;
    _hardwareName = _client.getName();
    if (widget.showDeviceStatus && widget.subtitle == null) {
      _connectionSubscription = _client.connectionStream.listen((state) {
        if (!mounted) return;
        setState(() {
          _connected = state.connected;
          if (state.device != null) {
            if (state.device!.id != _device?.id) _hardwareName = null;
            _device = state.device;
          }
        });
      });
      _deviceInfoSubscription = _client.deviceInfoUpdates.listen((patch) {
        if (!mounted) return;
        final name = _client.getName();
        if (name != null && name.isNotEmpty) {
          setState(() => _hardwareName = name);
        }
      });
    }
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _deviceInfoSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        if (widget.subtitle != null)
          _Subtitle(text: widget.subtitle!, color: widget.foregroundColor)
        else if (widget.showDeviceStatus)
          _DeviceSubtitle(
            name: _displayDeviceName(_hardwareName ?? _device?.name),
            connected: _connected,
            color: widget.foregroundColor,
          ),
      ],
    );
  }

  String _displayDeviceName(String? rawName) {
    final name = rawName?.trim() ?? '';
    if (name.isEmpty) return 'No device';

    final withoutPrefix = name.replaceFirst(
      RegExp(r'^Flipper(?:\s+Zero)?[\s_-]+', caseSensitive: false),
      '',
    );
    return withoutPrefix.isEmpty ? name : withoutPrefix;
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color.withValues(alpha: 0.72),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DeviceSubtitle extends StatelessWidget {
  const _DeviceSubtitle({
    required this.name,
    required this.connected,
    required this.color,
  });

  final String name;
  final bool connected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color.withValues(alpha: 0.72),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected
                  ? const Color(0xFF34C759)
                  : const Color(0xFF8E8E93),
            ),
          ),
        ],
      ),
    );
  }
}

class QPageAppBarAction extends StatelessWidget {
  const QPageAppBarAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return QPageAppBarTooltip(
      message: tooltip,
      child: IconButton(onPressed: onPressed, icon: icon),
    );
  }
}

class QPageAppBarTooltip extends StatefulWidget {
  const QPageAppBarTooltip({
    super.key,
    required this.message,
    required this.child,
  });

  final String message;
  final Widget child;

  @override
  State<QPageAppBarTooltip> createState() => _QPageAppBarTooltipState();
}

class _QPageAppBarTooltipState extends State<QPageAppBarTooltip>
    with SingleTickerProviderStateMixin {
  Timer? _showTimer;
  OverlayEntry? _overlayEntry;
  late final AnimationController _animationController;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      reverseDuration: const Duration(milliseconds: 120),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  void _scheduleShow() {
    _showTimer?.cancel();
    if (_overlayEntry != null) {
      _animationController.forward();
      return;
    }
    _showTimer = Timer(const Duration(milliseconds: 350), _show);
  }

  void _show() {
    if (!mounted || _overlayEntry != null) return;
    final overlay = Overlay.of(context);
    final appBarColor = _QPageAppBarColorScope.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final buttonCenter = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height),
    );

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => _WideTooltip(
        text: widget.message,
        arrowCenter: buttonCenter.dx,
        animation: _animation,
        appBarColor: appBarColor,
      ),
    );
    overlay.insert(_overlayEntry!);
    _animationController.forward(from: 0);
  }

  Future<void> _hide() async {
    _showTimer?.cancel();
    _showTimer = null;
    final entry = _overlayEntry;
    if (entry == null) return;
    await _animationController.reverse();
    if (!mounted ||
        !identical(entry, _overlayEntry) ||
        _animationController.value > 0) {
      return;
    }
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _removeImmediately() {
    _showTimer?.cancel();
    _showTimer = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void didUpdateWidget(covariant QPageAppBarTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message != oldWidget.message) {
      _hide();
    }
  }

  @override
  void dispose() {
    _removeImmediately();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _scheduleShow(),
      onExit: (_) => _hide(),
      child: widget.child,
    );
  }
}

class _WideTooltip extends StatelessWidget {
  const _WideTooltip({
    required this.text,
    required this.arrowCenter,
    required this.animation,
    required this.appBarColor,
  });

  final String text;
  final double arrowCenter;
  final Animation<double> animation;
  final Color? appBarColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    const arrowSize = 8.0;
    final tooltipColor = Color.alphaBlend(
      (appBarColor ?? colors.accent).withValues(alpha: 0.30),
      colors.background,
    );
    final textColor = colors.textPrimary;
    final maxArrowLeft = media.size.width - arrowSize * 2;
    final arrowLeft = (arrowCenter - arrowSize).clamp(0.0, maxArrowLeft);

    return Positioned(
      top: media.padding.top + QPageAppBar.toolbarHeight - arrowSize,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  Positioned(
                    left: arrowLeft,
                    top: 0,
                    child: CustomPaint(
                      size: const Size(arrowSize * 2, arrowSize),
                      painter: _TooltipArrowPainter(tooltipColor),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: arrowSize),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    color: tooltipColor,
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TooltipArrowPainter extends CustomPainter {
  const _TooltipArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TooltipArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}
