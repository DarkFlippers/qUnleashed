import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../services/localization/l10n.dart';
import '../theme/theme.dart';

class QPageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const QPageAppBar({
    super.key,
    required this.title,
    required this.client,
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

  /// The device whose name and link the subtitle shows.
  ///
  /// Required since ADR 0011 put `DeviceScope` above the Navigator: every one
  /// of the sixteen pages that build one of these is inside it now, so each
  /// has a client to pass. It was optional, with the global as a fallback,
  /// for exactly as long as that was not true.
  final FlipperClient client;

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

    return AppBar(
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
        client: client,
        title: title,
        subtitle: subtitle,
        showDeviceStatus: showDeviceStatus,
        foregroundColor: foreground,
      ),
    );
  }
}

class _PageTitle extends StatefulWidget {
  const _PageTitle({
    required this.client,
    required this.title,
    required this.subtitle,
    required this.showDeviceStatus,
    required this.foregroundColor,
  });

  final FlipperClient client;
  final String title;
  final String? subtitle;
  final bool showDeviceStatus;
  final Color foregroundColor;

  @override
  State<_PageTitle> createState() => _PageTitleState();
}

class _PageTitleState extends State<_PageTitle> {
  StreamSubscription<FlipperConnectionState>? _connectionSubscription;
  StreamSubscription<Map<String, String>>? _deviceInfoSubscription;
  FlipperDevice? _device;
  String? _hardwareName;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(covariant _PageTitle old) {
    super.didUpdateWidget(old);
    // A subscription belongs to the client it was opened on. Nothing swaps
    // one today - the app has a single client - but the parameter exists so a
    // test can, and a stale subscription would be the same defect either way.
    if (old.client != widget.client ||
        old.showDeviceStatus != widget.showDeviceStatus ||
        (old.subtitle == null) != (widget.subtitle == null)) {
      _unwatch();
      _watch();
    }
  }

  void _unwatch() {
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _deviceInfoSubscription?.cancel();
    _deviceInfoSubscription = null;
  }

  /// Reads the link once, and follows it only where the subtitle shows it.
  ///
  /// The condition is load-bearing: sixteen pages build one of these, and a
  /// title that subscribed regardless would put sixteen listeners on the
  /// device's streams for subtitles that never render a word of it.
  void _watch() {
    final client = widget.client;
    _device = client.connectedDevice;
    _connected = client.isConnected;
    _hardwareName = client.getName();
    if (widget.showDeviceStatus && widget.subtitle == null) {
      _connectionSubscription = client.connectionStream.listen((state) {
        if (!mounted) return;
        setState(() {
          _connected = state.connected;
          if (state.device != null) {
            if (state.device!.id != _device?.id) _hardwareName = null;
            _device = state.device;
          }
        });
      });
      _deviceInfoSubscription = client.deviceInfoUpdates.listen((patch) {
        if (!mounted) return;
        final name = client.getName();
        if (name != null && name.isNotEmpty) {
          setState(() => _hardwareName = name);
        }
      });
    }
  }

  @override
  void dispose() {
    _unwatch();
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
    if (name.isEmpty) return l10n.deviceStateNoDevice;

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
    return IconButton(tooltip: tooltip, onPressed: onPressed, icon: icon);
  }
}
