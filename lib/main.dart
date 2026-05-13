import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import 'pages/devices/page.dart';
import 'theme.dart';
import 'widgets/flipper_busy_dialog.dart';

void main() {
  runApp(const QunleashedApp());
}

class QunleashedApp extends StatefulWidget {
  const QunleashedApp({super.key});

  @override
  State<QunleashedApp> createState() => _QunleashedAppState();
}

class _QunleashedAppState extends State<QunleashedApp> {
  final _themeController = QAppThemeController.instance;
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeController,
      builder: (context, _) => MaterialApp(
        title: 'Qunleashed',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(_themeController.activeFirmware),
        navigatorKey: _navKey,
        home: _RpcErrorWatcher(
          navigatorKey: _navKey,
          child: const DevicePage(),
        ),
      ),
    );
  }
}

class _RpcErrorWatcher extends StatefulWidget {
  const _RpcErrorWatcher({required this.child, required this.navigatorKey});

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<_RpcErrorWatcher> createState() => _RpcErrorWatcherState();
}

class _RpcErrorWatcherState extends State<_RpcErrorWatcher> {
  StreamSubscription<FlipperRpcException>? _sub;
  bool _busyShowing = false;

  @override
  void initState() {
    super.initState();
    final client = FlipperOneClient().get();
    _sub = client.errorStream.listen(_onRpcError);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onRpcError(FlipperRpcException error) {
    if (error is! FlipperRpcAppSystemLockedException) return;
    if (_busyShowing) return;
    final overlayContext = widget.navigatorKey.currentContext;
    if (overlayContext == null) return;
    _busyShowing = true;
    showFlipperBusyDialog(overlayContext).whenComplete(() {
      _busyShowing = false;
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
