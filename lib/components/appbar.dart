import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../services/localization/l10n.dart';
import '../theme/theme.dart';

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
