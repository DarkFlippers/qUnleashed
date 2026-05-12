import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../devices/widgets/connection_dialog.dart';

const _kBackgroundColor = Color(0xFF000000);
const _kForegroundColor = Color(0xFFE0E0E0);
const _kStatusBarColor = Color(0xFF111111);

class CliPage extends StatefulWidget {
  const CliPage({super.key});

  @override
  State<CliPage> createState() => _CliPageState();
}

class _CliPageState extends State<CliPage> {
  final FlipperClient _client = FlipperOneClient().get();
  final FocusNode _terminalFocusNode = FocusNode(debugLabel: 'cli-terminal');

  late final Terminal _terminal;
  late final TerminalController _terminalController;

  StreamSubscription<String>? _textSub;
  StreamSubscription<FlipperConnectionState>? _connSub;

  String _status = 'Initializing…';
  bool _bleNotice = false;
  bool _ready = false;
  bool _busy = false;
  bool _awaitingInterrupt = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: 10000,
      onOutput: _onTerminalOutput,
      platform: _platform,
    );
    _terminalController = TerminalController();
    _client.cliExclusive = true;
    _connSub = _client.connectionStream.listen(_onConnectionState);
    _textSub = _client.textStream.listen(_onText);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _textSub?.cancel();
    _connSub?.cancel();
    if (_awaitingInterrupt) {
      try {
        _client.writeCliBytes(Uint8List.fromList([0x03]));
      } catch (_) {}
    }
    _client.cliExclusive = false;
    unawaited(_client.disconnect());
    _terminalController.dispose();
    _terminalFocusNode.dispose();
    super.dispose();
  }

  TerminalTargetPlatform get _platform {
    if (kIsWeb) return TerminalTargetPlatform.unknown;
    if (Platform.isAndroid) return TerminalTargetPlatform.android;
    if (Platform.isIOS) return TerminalTargetPlatform.ios;
    if (Platform.isWindows) return TerminalTargetPlatform.windows;
    if (Platform.isMacOS) return TerminalTargetPlatform.macos;
    if (Platform.isLinux) return TerminalTargetPlatform.linux;
    return TerminalTargetPlatform.unknown;
  }

  void _onTerminalOutput(String data) {
    if (!_ready) return;
    final bytes = Uint8List.fromList(utf8.encode(data));
    unawaited(_client.writeCliBytes(bytes).catchError((Object e) {
      LogService.log('[CLI] write error: $e');
    }));
  }

  Future<void> _bootstrap() async {
    if (_busy) return;
    _busy = true;
    try {
      final device = _client.connectedDevice;
      if (device == null) {
        await _promptForDevice();
        return;
      }
      if (device.isBle) {
        setState(() {
          _bleNotice = true;
          _status = 'BLE connection cannot host a CLI session.';
        });
        return;
      }
      await _resetUsbCliSession(device);
    } catch (e) {
      LogService.log('[CLI] bootstrap failed: $e');
      if (mounted) {
        setState(() => _status = 'Failed to start CLI session: $e');
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _promptForDevice() async {
    if (!mounted) return;
    setState(() => _status = 'Waiting for USB device…');
    final selected = await showConnectionDialog(
      context,
      usbOnly: true,
      skipRpc: true,
    );
    if (!mounted) return;
    if (selected == null) {
      Navigator.of(context).maybePop();
      return;
    }
    if (selected.isBle) {
      setState(() {
        _bleNotice = true;
        _status = 'BLE connection cannot host a CLI session.';
      });
      return;
    }
    setState(() => _status = 'Connecting…');
    try {
      await _client.connect(selected);
    } catch (e) {
      LogService.log('[CLI] connect failed: $e');
      if (mounted) {
        setState(() => _status = 'Connection failed: $e');
      }
      return;
    }
    await _enterCliReady();
  }

  Future<void> _resetUsbCliSession(FlipperDevice device) async {
    setState(() => _status = 'Resetting CLI session…');
    try {
      await _client.disconnect();
      await _client.connect(device);
    } catch (e) {
      LogService.log('[CLI] reconnect failed: $e');
      if (mounted) {
        setState(() => _status = 'Reconnect failed: $e');
      }
      return;
    }
    await _enterCliReady();
  }

  Future<void> _enterCliReady() async {
    if (!mounted) return;
    setState(() {
      _ready = true;
      _status = 'Connected';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _terminalFocusNode.requestFocus();
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      await _client.writeCliBytes(Uint8List.fromList([0x01]));
    } catch (e) {
      LogService.log('[CLI] init nudge failed: $e');
    }
  }

  void _onConnectionState(FlipperConnectionState state) {
    if (!mounted) return;
    if (!state.connected && _ready) {
      setState(() {
        _ready = false;
        _status = 'Device disconnected';
      });
    }
  }

  void _onText(String text) {
    _awaitingInterrupt = !text.contains('>:');
    _terminal.write(text);
  }

  void _clearOutput() {
    _terminal.write('\x1b[2J\x1b[H');
    _terminalFocusNode.requestFocus();
  }

  void _sendCtrlC() {
    if (!_ready) return;
    unawaited(_client.writeCliBytes(Uint8List.fromList([0x03])).catchError(
      (Object e) => LogService.log('[CLI] ctrl-c failed: $e'),
    ));
    _terminalFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackgroundColor,
      appBar: AppBar(
        title: const Text('CLI'),
        backgroundColor: _kBackgroundColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Send Ctrl+C',
            onPressed: _ready ? _sendCtrlC : null,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
          IconButton(
            tooltip: 'Clear',
            onPressed: _clearOutput,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_bleNotice) {
      return _buildBleNotice();
    }
    return Stack(
      children: [
        Positioned.fill(child: _buildTerminal()),
        if (!_ready)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              color: _kStatusBarColor,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Text(
                _status,
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTerminal() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 800;
        final fontSize = isCompact ? 6.0 : 13.0;
        final padding = isCompact ? 3.0 : 8.0;
        return TerminalView(
          _terminal,
          controller: _terminalController,
          focusNode: _terminalFocusNode,
          autofocus: true,
          backgroundOpacity: 1.0,
          padding: EdgeInsets.all(padding),
          cursorType: TerminalCursorType.block,
          alwaysShowCursor: true,
          keyboardType: TextInputType.text,
          hardwareKeyboardOnly: _useHardwareKeyboardOnly,
          theme: _terminalTheme,
          textStyle: TerminalStyle(
            fontSize: fontSize,
            fontFamily: _monospaceFontFamily,
            fontFamilyFallback: _monospaceFallback,
          ),
        );
      },
    );
  }

  Widget _buildBleNotice() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.bluetooth_disabled,
              color: Colors.white54,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'CLI session is not supported over BLE.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect the Flipper via USB to open a terminal session.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                setState(() => _bleNotice = false);
                await _promptForDevice();
              },
              child: const Text('Select USB device'),
            ),
          ],
        ),
      ),
    );
  }
}

bool get _useHardwareKeyboardOnly {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

const String _monospaceFontFamily = 'monospace';

const List<String> _monospaceFallback = [
  'Cascadia Mono',
  'Consolas',
  'Courier New',
  'Menlo',
  'Monaco',
  'DejaVu Sans Mono',
  'Liberation Mono',
  'Roboto Mono',
  'monospace',
];

const TerminalTheme _terminalTheme = TerminalTheme(
  cursor: _kForegroundColor,
  selection: Color(0x66BBBBBB),
  foreground: _kForegroundColor,
  background: _kBackgroundColor,
  black: Color(0xFF000000),
  red: Color(0xFFE06C75),
  green: Color(0xFF98C379),
  yellow: Color(0xFFE5C07B),
  blue: Color(0xFF61AFEF),
  magenta: Color(0xFFC678DD),
  cyan: Color(0xFF56B6C2),
  white: Color(0xFFD0D0D0),
  brightBlack: Color(0xFF5C6370),
  brightRed: Color(0xFFE06C75),
  brightGreen: Color(0xFF98C379),
  brightYellow: Color(0xFFE5C07B),
  brightBlue: Color(0xFF61AFEF),
  brightMagenta: Color(0xFFC678DD),
  brightCyan: Color(0xFF56B6C2),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFF888888),
  searchHitBackgroundCurrent: Color(0xFFFFFFFF),
  searchHitForeground: Color(0xFF000000),
);
